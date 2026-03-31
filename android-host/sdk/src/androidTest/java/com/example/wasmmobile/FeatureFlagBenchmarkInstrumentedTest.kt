package com.example.wasmmobile

import android.content.Context
import android.os.Build
import android.util.Log
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class FeatureFlagBenchmarkInstrumentedTest {
    companion object {
        private const val BENCHMARK_TAG = "WasmMobileBench"
        private const val BENCHMARK_FILE_NAME = "benchmark.json"
        private const val SAMPLE_COUNT = 1_000
    }

    private val targetContext: Context
        get() = ApplicationProvider.getApplicationContext()

    private val instrumentationContext: Context
        get() = InstrumentationRegistry.getInstrumentation().context

    @Test
    fun emitsBenchmarkJson() {
        val request = FeatureFlagRequest(
            flagKey = "new_home",
            defaultVariant = "off",
            rules = listOf(
                FeatureRule(
                    attribute = "country",
                    op = "eq",
                    value = JsonPrimitive("DE"),
                    variant = "on",
                ),
                FeatureRule(
                    attribute = "app_version",
                    op = "gte",
                    value = JsonPrimitive(120),
                    variant = "canary",
                ),
            ),
            context = mapOf(
                "country" to JsonPrimitive("PL"),
                "app_version" to JsonPrimitive(130),
            ),
        )

        val initStart = System.nanoTime()
        FeatureFlagEngine.fromBundledWasm(targetContext).use { engine ->
            val initEnd = System.nanoTime()
            val firstResponse = engine.evaluate(request)
            val firstEnd = System.nanoTime()

            val steadyStart = System.nanoTime()
            repeat(SAMPLE_COUNT) {
                engine.evaluate(request)
            }
            val steadyEnd = System.nanoTime()

            assertTrue(firstResponse.ok)

            val wasmSizeBytes = targetContext.assets.open("shared-core.wasm").use { it.available().toLong() }
            val nativeLibSizeBytes = File(
                targetContext.applicationInfo.nativeLibraryDir,
                "libwasm_mobile.so",
            ).length()
            val coldStartMicros = (firstEnd - initStart) / 1_000.0
            val initMicros = (initEnd - initStart) / 1_000.0
            val steadyStateMeanMicros = (steadyEnd - steadyStart) / 1_000.0 / SAMPLE_COUNT.toDouble()
            val json = buildJsonObject {
                put("platform", "android")
                put("execution_target", executionTarget())
                put("device_name", "${Build.MANUFACTURER} ${Build.MODEL}")
                put("device_model", Build.MODEL)
                put("os_version", Build.VERSION.RELEASE ?: "unknown")
                put("arch", Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown")
                put("sample_count", SAMPLE_COUNT)
                put("wasm_size_bytes", wasmSizeBytes)
                put("native_lib_size_bytes", nativeLibSizeBytes)
                put("engine_init_micros", initMicros)
                put("cold_start_micros", coldStartMicros)
                put("steady_state_mean_micros", steadyStateMeanMicros)
                put("used_stub", engine.isUsingStub)
            }.toString()

            instrumentationContext.deleteFile(BENCHMARK_FILE_NAME)
            instrumentationContext.openFileOutput(BENCHMARK_FILE_NAME, Context.MODE_PRIVATE).use {
                it.write(json.toByteArray())
            }
            println("BENCHMARK_JSON: $json")
            Log.i(BENCHMARK_TAG, json)
        }
    }

    private fun executionTarget(): String {
        return if (isProbablyEmulator()) "emulator" else "physical_device"
    }

    private fun isProbablyEmulator(): Boolean {
        return Build.FINGERPRINT.startsWith("generic") ||
            Build.FINGERPRINT.contains("emulator", ignoreCase = true) ||
            Build.MODEL.contains("Emulator", ignoreCase = true) ||
            Build.MODEL.contains("Android SDK built for", ignoreCase = true) ||
            Build.PRODUCT.contains("sdk", ignoreCase = true) ||
            Build.HARDWARE.contains("ranchu", ignoreCase = true)
    }
}
