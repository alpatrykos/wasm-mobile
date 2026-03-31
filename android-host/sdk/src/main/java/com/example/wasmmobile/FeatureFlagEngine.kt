package com.example.wasmmobile

import android.content.Context
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString

class FeatureFlagEngine private constructor(private var engineHandle: Long?) : AutoCloseable {
    val isUsingStub: Boolean
        get() = engineHandle == null

    fun evaluate(request: FeatureFlagRequest): FeatureFlagEnvelope {
        val handle = engineHandle ?: return stubResponse(request)
        val requestJson = featureFlagJson.encodeToString(request).encodeToByteArray()
        val responseBytes = WasmNativeBridge.evaluate(handle, requestJson)
            ?: return internalError("native runtime failed to evaluate request")

        return runCatching {
            featureFlagJson.decodeFromString<FeatureFlagEnvelope>(responseBytes.decodeToString())
        }.getOrElse { error ->
            internalError("failed to decode native response: ${error.message}")
        }
    }

    override fun close() {
        val handle = engineHandle ?: return
        WasmNativeBridge.destroy(handle)
        engineHandle = null
    }

    companion object {
        fun fromBundledWasm(
            context: Context,
            wasmAssetName: String = "shared-core.wasm",
        ): FeatureFlagEngine {
            val wasmBytes = runCatching {
                context.assets.open(wasmAssetName).use { it.readBytes() }
            }.getOrNull()

            val handle = wasmBytes?.let { WasmNativeBridge.createEngine(it) }?.takeIf { it != 0L }
            return FeatureFlagEngine(handle)
        }
    }
}

internal object WasmNativeBridge {
    private val isLoaded = runCatching {
        System.loadLibrary("wasm_mobile")
    }.isSuccess

    fun createEngine(wasmBytes: ByteArray): Long {
        if (!isLoaded) {
            return 0L
        }
        return nativeCreateEngine(wasmBytes)
    }

    fun evaluate(handle: Long, requestBytes: ByteArray): ByteArray? {
        if (!isLoaded) {
            return null
        }
        return nativeEvaluate(handle, requestBytes)
    }

    fun destroy(handle: Long) {
        if (!isLoaded || handle == 0L) {
            return
        }
        nativeDestroyEngine(handle)
    }

    private external fun nativeCreateEngine(wasmBytes: ByteArray): Long
    private external fun nativeEvaluate(handle: Long, requestBytes: ByteArray): ByteArray?
    private external fun nativeDestroyEngine(handle: Long)
}

