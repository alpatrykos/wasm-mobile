#include "wasm_host_runtime.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "wasm3.h"

struct wm_engine {
    uint8_t *wasm_bytes;
    uint32_t wasm_len;
    IM3Environment env;
    IM3Runtime runtime;
    IM3Module module;
    IM3Function alloc_fn;
    IM3Function free_fn;
    IM3Function evaluate_fn;
};

static char *wm_duplicate_string(const char *value) {
    if (value == NULL) {
        return NULL;
    }

    size_t len = strlen(value);
    char *copy = (char *)malloc(len + 1);
    if (copy == NULL) {
        return NULL;
    }

    memcpy(copy, value, len);
    copy[len] = '\0';
    return copy;
}

static void wm_set_error(char **error_out, const char *value) {
    if (error_out == NULL) {
        return;
    }

    *error_out = wm_duplicate_string(value);
}

static void wm_set_m3_error(
    struct wm_engine *engine,
    char **error_out,
    const char *context,
    M3Result result
) {
    if (error_out == NULL) {
        return;
    }

    char buffer[512];
    const char *message = result != NULL ? result : "unknown wasm3 error";

    if (engine != NULL && engine->runtime != NULL) {
        M3ErrorInfo info;
        m3_GetErrorInfo(engine->runtime, &info);
        if (info.message != NULL && info.message[0] != '\0') {
            snprintf(buffer, sizeof(buffer), "%s: %s (%s)", context, message, info.message);
            wm_set_error(error_out, buffer);
            return;
        }
    }

    snprintf(buffer, sizeof(buffer), "%s: %s", context, message);
    wm_set_error(error_out, buffer);
}

static void wm_call_free(struct wm_engine *engine, uint32_t pointer, uint32_t len) {
    if (engine == NULL || engine->free_fn == NULL || pointer == 0 || len == 0) {
        return;
    }

    const void *args[2] = { &pointer, &len };
    m3_Call(engine->free_fn, 2, args);
}

static uint8_t *wm_memory(struct wm_engine *engine, uint32_t *len_out) {
    return m3_GetMemory(engine->runtime, len_out, 0);
}

wm_engine_t *wm_engine_create(const uint8_t *wasm_bytes, uint32_t wasm_len, char **error_out) {
    M3Result result = m3Err_none;
    struct wm_engine *engine = NULL;

    if (wasm_bytes == NULL || wasm_len == 0) {
        wm_set_error(error_out, "missing wasm bytes");
        return NULL;
    }

    engine = (struct wm_engine *)calloc(1, sizeof(struct wm_engine));
    if (engine == NULL) {
        wm_set_error(error_out, "failed to allocate engine");
        return NULL;
    }

    engine->wasm_bytes = (uint8_t *)malloc(wasm_len);
    if (engine->wasm_bytes == NULL) {
        wm_set_error(error_out, "failed to allocate wasm copy");
        wm_engine_destroy(engine);
        return NULL;
    }

    memcpy(engine->wasm_bytes, wasm_bytes, wasm_len);
    engine->wasm_len = wasm_len;

    engine->env = m3_NewEnvironment();
    if (engine->env == NULL) {
        wm_set_error(error_out, "failed to create wasm environment");
        wm_engine_destroy(engine);
        return NULL;
    }

    engine->runtime = m3_NewRuntime(engine->env, 64 * 1024, NULL);
    if (engine->runtime == NULL) {
        wm_set_error(error_out, "failed to create wasm runtime");
        wm_engine_destroy(engine);
        return NULL;
    }

    result = m3_ParseModule(engine->env, &engine->module, engine->wasm_bytes, engine->wasm_len);
    if (result != m3Err_none) {
        wm_set_m3_error(engine, error_out, "failed to parse wasm module", result);
        wm_engine_destroy(engine);
        return NULL;
    }

    result = m3_LoadModule(engine->runtime, engine->module);
    if (result != m3Err_none) {
        wm_set_m3_error(engine, error_out, "failed to load wasm module", result);
        wm_engine_destroy(engine);
        return NULL;
    }
    engine->module = NULL;

    result = m3_FindFunction(&engine->alloc_fn, engine->runtime, "wasm_alloc");
    if (result != m3Err_none) {
        wm_set_m3_error(engine, error_out, "failed to bind wasm_alloc", result);
        wm_engine_destroy(engine);
        return NULL;
    }

    result = m3_FindFunction(&engine->free_fn, engine->runtime, "wasm_free");
    if (result != m3Err_none) {
        wm_set_m3_error(engine, error_out, "failed to bind wasm_free", result);
        wm_engine_destroy(engine);
        return NULL;
    }

    result = m3_FindFunction(&engine->evaluate_fn, engine->runtime, "evaluate_feature_flag");
    if (result != m3Err_none) {
        wm_set_m3_error(engine, error_out, "failed to bind evaluate_feature_flag", result);
        wm_engine_destroy(engine);
        return NULL;
    }

    return engine;
}

void wm_engine_destroy(wm_engine_t *engine) {
    if (engine == NULL) {
        return;
    }

    if (engine->module != NULL) {
        m3_FreeModule(engine->module);
        engine->module = NULL;
    }

    if (engine->runtime != NULL) {
        m3_FreeRuntime(engine->runtime);
        engine->runtime = NULL;
    }

    if (engine->env != NULL) {
        m3_FreeEnvironment(engine->env);
        engine->env = NULL;
    }

    if (engine->wasm_bytes != NULL) {
        free(engine->wasm_bytes);
        engine->wasm_bytes = NULL;
    }

    free(engine);
}

uint8_t *wm_engine_evaluate(
    wm_engine_t *engine,
    const uint8_t *request_bytes,
    uint32_t request_len,
    uint32_t *response_len_out,
    char **error_out
) {
    M3Result result = m3Err_none;
    uint32_t request_ptr = 0;
    uint64_t packed_result = 0;
    uint32_t response_ptr = 0;
    uint32_t response_len = 0;
    uint32_t memory_len = 0;
    uint8_t *memory = NULL;
    uint8_t *response_copy = NULL;

    if (response_len_out != NULL) {
        *response_len_out = 0;
    }

    if (engine == NULL || request_bytes == NULL) {
        wm_set_error(error_out, "engine or request bytes were null");
        return NULL;
    }

    const void *alloc_args[1] = { &request_len };
    result = m3_Call(engine->alloc_fn, 1, alloc_args);
    if (result != m3Err_none) {
        wm_set_m3_error(engine, error_out, "failed to allocate guest request buffer", result);
        return NULL;
    }

    const void *alloc_results[1] = { &request_ptr };
    result = m3_GetResults(engine->alloc_fn, 1, alloc_results);
    if (result != m3Err_none) {
        wm_set_m3_error(engine, error_out, "failed to read guest request pointer", result);
        return NULL;
    }

    memory = wm_memory(engine, &memory_len);
    if (memory == NULL || request_ptr + request_len > memory_len) {
        wm_call_free(engine, request_ptr, request_len);
        wm_set_error(error_out, "guest request pointer was out of bounds");
        return NULL;
    }

    if (request_len > 0) {
        memcpy(memory + request_ptr, request_bytes, request_len);
    }

    const void *eval_args[2] = { &request_ptr, &request_len };
    result = m3_Call(engine->evaluate_fn, 2, eval_args);
    if (result != m3Err_none) {
        wm_call_free(engine, request_ptr, request_len);
        wm_set_m3_error(engine, error_out, "failed to call evaluate_feature_flag", result);
        return NULL;
    }

    const void *eval_results[1] = { &packed_result };
    result = m3_GetResults(engine->evaluate_fn, 1, eval_results);
    wm_call_free(engine, request_ptr, request_len);
    if (result != m3Err_none) {
        wm_set_m3_error(engine, error_out, "failed to read evaluate_feature_flag result", result);
        return NULL;
    }

    response_ptr = (uint32_t)(packed_result >> 32);
    response_len = (uint32_t)(packed_result & 0xffffffffu);
    memory = wm_memory(engine, &memory_len);
    if (memory == NULL || response_ptr + response_len > memory_len) {
        wm_call_free(engine, response_ptr, response_len);
        wm_set_error(error_out, "guest response pointer was out of bounds");
        return NULL;
    }

    response_copy = (uint8_t *)malloc(response_len == 0 ? 1 : response_len);
    if (response_copy == NULL) {
        wm_call_free(engine, response_ptr, response_len);
        wm_set_error(error_out, "failed to allocate host response buffer");
        return NULL;
    }

    if (response_len > 0) {
        memcpy(response_copy, memory + response_ptr, response_len);
    }
    wm_call_free(engine, response_ptr, response_len);

    if (response_len_out != NULL) {
        *response_len_out = response_len;
    }

    return response_copy;
}

void wm_buffer_free(uint8_t *buffer) {
    if (buffer != NULL) {
        free(buffer);
    }
}

void wm_error_free(char *error_message) {
    if (error_message != NULL) {
        free(error_message);
    }
}
