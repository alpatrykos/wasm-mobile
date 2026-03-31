#include <jni.h>

#include <vector>

#include "wasm_host_runtime.h"

namespace {

std::vector<uint8_t> to_vector(JNIEnv *env, jbyteArray source) {
    if (source == nullptr) {
        return {};
    }

    const jsize len = env->GetArrayLength(source);
    std::vector<uint8_t> bytes(static_cast<size_t>(len));
    if (len > 0) {
        env->GetByteArrayRegion(source, 0, len, reinterpret_cast<jbyte *>(bytes.data()));
    }
    return bytes;
}

}  // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_com_example_wasmmobile_WasmNativeBridge_nativeCreateEngine(
    JNIEnv *env,
    jobject /* this */,
    jbyteArray wasmBytes
) {
    std::vector<uint8_t> wasm = to_vector(env, wasmBytes);
    char *error = nullptr;
    wm_engine_t *engine =
        wm_engine_create(wasm.data(), static_cast<uint32_t>(wasm.size()), &error);
    wm_error_free(error);
    return reinterpret_cast<jlong>(engine);
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_example_wasmmobile_WasmNativeBridge_nativeEvaluate(
    JNIEnv *env,
    jobject /* this */,
    jlong handle,
    jbyteArray requestBytes
) {
    if (handle == 0) {
        return nullptr;
    }

    std::vector<uint8_t> request = to_vector(env, requestBytes);
    uint32_t response_len = 0;
    char *error = nullptr;
    uint8_t *response = wm_engine_evaluate(
        reinterpret_cast<wm_engine_t *>(handle),
        request.data(),
        static_cast<uint32_t>(request.size()),
        &response_len,
        &error
    );
    wm_error_free(error);
    if (response == nullptr) {
        return nullptr;
    }

    jbyteArray output = env->NewByteArray(static_cast<jsize>(response_len));
    if (output != nullptr && response_len > 0) {
        env->SetByteArrayRegion(
            output,
            0,
            static_cast<jsize>(response_len),
            reinterpret_cast<jbyte *>(response)
        );
    }
    wm_buffer_free(response);
    return output;
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_wasmmobile_WasmNativeBridge_nativeDestroyEngine(
    JNIEnv * /* env */,
    jobject /* this */,
    jlong handle
) {
    wm_engine_destroy(reinterpret_cast<wm_engine_t *>(handle));
}

