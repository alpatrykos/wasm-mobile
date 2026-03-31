import Foundation

public enum ScalarValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        throw DecodingError.typeMismatch(
            ScalarValue.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "expected string, number, or bool"
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        }
    }
}

public struct FeatureFlagRequest: Codable, Equatable {
    public let flagKey: String
    public let defaultVariant: String
    public let rules: [FeatureRule]
    public let context: [String: ScalarValue]

    public init(
        flagKey: String,
        defaultVariant: String,
        rules: [FeatureRule],
        context: [String: ScalarValue]
    ) {
        self.flagKey = flagKey
        self.defaultVariant = defaultVariant
        self.rules = rules
        self.context = context
    }

    enum CodingKeys: String, CodingKey {
        case flagKey = "flag_key"
        case defaultVariant = "default_variant"
        case rules
        case context
    }
}

public struct FeatureRule: Codable, Equatable {
    public let attribute: String
    public let op: String
    public let value: ScalarValue
    public let variant: String

    public init(attribute: String, op: String, value: ScalarValue, variant: String) {
        self.attribute = attribute
        self.op = op
        self.value = value
        self.variant = variant
    }
}

public struct FeatureFlagEnvelope: Codable, Equatable {
    public let ok: Bool
    public let result: FeatureFlagResult?
    public let error: FeatureFlagError?

    public init(ok: Bool, result: FeatureFlagResult? = nil, error: FeatureFlagError? = nil) {
        self.ok = ok
        self.result = result
        self.error = error
    }
}

public struct FeatureFlagResult: Codable, Equatable {
    public let flagKey: String
    public let variant: String
    public let reason: String
    public let matchedRuleIndex: Int?
    public let source: String

    public init(
        flagKey: String,
        variant: String,
        reason: String,
        matchedRuleIndex: Int?,
        source: String
    ) {
        self.flagKey = flagKey
        self.variant = variant
        self.reason = reason
        self.matchedRuleIndex = matchedRuleIndex
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case flagKey = "flag_key"
        case variant
        case reason
        case matchedRuleIndex = "matched_rule_index"
        case source
    }
}

public struct FeatureFlagError: Codable, Equatable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

enum FeatureFlagJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder = JSONDecoder()
}

func stubResponse(for request: FeatureFlagRequest) -> FeatureFlagEnvelope {
    FeatureFlagEnvelope(
        ok: true,
        result: FeatureFlagResult(
            flagKey: request.flagKey,
            variant: request.defaultVariant,
            reason: "default",
            matchedRuleIndex: nil,
            source: "stub"
        )
    )
}

func internalError(_ message: String) -> FeatureFlagEnvelope {
    FeatureFlagEnvelope(
        ok: false,
        error: FeatureFlagError(code: "INTERNAL_ERROR", message: message)
    )
}

