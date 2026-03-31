package com.example.wasmmobile

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.decodeFromStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@Serializable
private data class FixtureCase(
    val name: String,
    val request: FeatureFlagRequest,
    @SerialName("expected_response") val expectedResponse: FeatureFlagEnvelope,
)

@RunWith(AndroidJUnit4::class)
@OptIn(ExperimentalSerializationApi::class)
class FeatureFlagEngineInstrumentedTest {
    private val context: Context
        get() = ApplicationProvider.getApplicationContext()

    @Test
    fun evaluates_shared_fixtures_from_bundled_wasm() {
        val fixtures = context.assets.open("feature_flag_cases.json").use { input ->
            featureFlagJson.decodeFromStream<List<FixtureCase>>(input)
        }

        FeatureFlagEngine.fromBundledWasm(context).use { engine ->
            assertTrue(!engine.isUsingStub)

            fixtures.forEach { fixture ->
                val actual = engine.evaluate(fixture.request)
                assertEquals("fixture ${fixture.name}", fixture.expectedResponse, actual)
            }
        }
    }

    @Test
    fun falls_back_to_stub_when_wasm_asset_is_missing() {
        val request = FeatureFlagRequest(
            flagKey = "new_home",
            defaultVariant = "off",
            rules = emptyList(),
            context = emptyMap(),
        )

        FeatureFlagEngine.fromBundledWasm(context, wasmAssetName = "missing.wasm").use { engine ->
            assertTrue(engine.isUsingStub)
            val response = engine.evaluate(request)
            assertEquals("stub", response.result?.source)
            assertEquals("off", response.result?.variant)
        }
    }
}
