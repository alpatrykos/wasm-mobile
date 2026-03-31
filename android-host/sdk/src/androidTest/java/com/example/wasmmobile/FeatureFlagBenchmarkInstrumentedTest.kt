package com.example.wasmmobile

import android.content.Context
import android.util.Log
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class FeatureFlagBenchmarkInstrumentedTest {
    companion object {
        private const val BENCHMARK_TAG = "WasmMobileBench"
    }

    private val context: Context
        get() = ApplicationProvider.getApplicationContext()

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
        FeatureFlagEngine.fromBundledWasm(context).use { engine ->
            val initEnd = System.nanoTime()
            val firstResponse = engine.evaluate(request)
            val firstEnd = System.nanoTime()

            val steadyStart = System.nanoTime()
            repeat(1_000) {
                engine.evaluate(request)
            }
            val steadyEnd = System.nanoTime()

            assertTrue(firstResponse.ok)

            val wasmSizeBytes = context.assets.open("shared-core.wasm").use { it.available().toLong() }
            val nativeLibSizeBytes = File(
                context.applicationInfo.nativeLibraryDir,
                "libwasm_mobile.so",
            ).length()
            val coldStartMicros = (firstEnd - initStart) / 1_000.0
            val initMicros = (initEnd - initStart) / 1_000.0
            val steadyStateMeanMicros = (steadyEnd - steadyStart) / 1_000.0 / 1_000.0

            val json = "{" +
                "\"platform\":\"android\"," +
                "\"wasm_size_bytes\":${wasmSizeBytes}," +
                "\"native_lib_size_bytes\":${nativeLibSizeBytes}," +
                "\"engine_init_micros\":${"%.2f".format(initMicros)}," +
                "\"cold_start_micros\":${"%.2f".format(coldStartMicros)}," +
                "\"steady_state_mean_micros\":${"%.2f".format(steadyStateMeanMicros)}" +
                "}"
            println("BENCHMARK_JSON: $json")
            Log.i(BENCHMARK_TAG, json)
        }
    }
}
