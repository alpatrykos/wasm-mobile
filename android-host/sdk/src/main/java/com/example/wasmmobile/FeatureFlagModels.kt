package com.example.wasmmobile

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive

@OptIn(ExperimentalSerializationApi::class)
internal val featureFlagJson = Json {
    encodeDefaults = true
    explicitNulls = false
}

@Serializable
data class FeatureFlagRequest(
    @SerialName("flag_key") val flagKey: String,
    @SerialName("default_variant") val defaultVariant: String,
    val rules: List<FeatureRule>,
    val context: Map<String, JsonPrimitive>,
)

@Serializable
data class FeatureRule(
    val attribute: String,
    val op: String,
    val value: JsonPrimitive,
    val variant: String,
)

@Serializable
data class FeatureFlagEnvelope(
    val ok: Boolean,
    val result: FeatureFlagResult? = null,
    val error: FeatureFlagError? = null,
)

@Serializable
data class FeatureFlagResult(
    @SerialName("flag_key") val flagKey: String,
    val variant: String,
    val reason: String,
    @SerialName("matched_rule_index") val matchedRuleIndex: Int? = null,
    val source: String,
)

@Serializable
data class FeatureFlagError(
    val code: String,
    val message: String,
)

internal fun FeatureFlagEnvelope.toJsonElement(): JsonElement =
    featureFlagJson.encodeToJsonElement(FeatureFlagEnvelope.serializer(), this)

internal fun stubResponse(request: FeatureFlagRequest): FeatureFlagEnvelope =
    FeatureFlagEnvelope(
        ok = true,
        result = FeatureFlagResult(
            flagKey = request.flagKey,
            variant = request.defaultVariant,
            reason = "default",
            matchedRuleIndex = null,
            source = "stub",
        ),
    )

internal fun internalError(message: String): FeatureFlagEnvelope =
    FeatureFlagEnvelope(
        ok = false,
        error = FeatureFlagError(
            code = "INTERNAL_ERROR",
            message = message,
        ),
    )

internal fun FeatureFlagEnvelope.toJsonString(): String =
    featureFlagJson.encodeToString(this)
