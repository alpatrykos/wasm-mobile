#ifndef WASM_HOST_RUNTIME_H
#define WASM_HOST_RUNTIME_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct wm_engine wm_engine_t;

wm_engine_t *wm_engine_create(const uint8_t *wasm_bytes, uint32_t wasm_len, char **error_out);
void wm_engine_destroy(wm_engine_t *engine);

uint8_t *wm_engine_evaluate(
    wm_engine_t *engine,
    const uint8_t *request_bytes,
    uint32_t request_len,
    uint32_t *response_len_out,
    char **error_out
);

void wm_buffer_free(uint8_t *buffer);
void wm_error_free(char *error_message);

#ifdef __cplusplus
}
#endif

#endif

