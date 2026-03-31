import Foundation
import WasmHostBridge

public final class FeatureFlagEngine {
    private var handle: OpaquePointer?

    public var isUsingStub: Bool {
        handle == nil
    }

    public init(
        bundle: Bundle? = nil,
        wasmResourceName: String = "shared-core",
        wasmExtension: String = "wasm"
    ) {
        let resolvedBundle = bundle ?? .module
        guard let url = resolvedBundle.url(forResource: wasmResourceName, withExtension: wasmExtension),
              let wasmData = try? Data(contentsOf: url) else {
            handle = nil
            return
        }

        var errorPointer: UnsafeMutablePointer<CChar>?
        handle = wasmData.withUnsafeBytes { rawBuffer in
            wm_engine_create(
                rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                UInt32(wasmData.count),
                &errorPointer
            )
        }
        wm_error_free(errorPointer)
    }

    deinit {
        close()
    }

    public func close() {
        guard let handle else {
            return
        }
        wm_engine_destroy(handle)
        self.handle = nil
    }

    public func evaluate(_ request: FeatureFlagRequest) -> FeatureFlagEnvelope {
        guard let handle else {
            return stubResponse(for: request)
        }

        guard let requestData = try? FeatureFlagJSON.encoder.encode(request) else {
            return internalError("failed to encode request")
        }

        var responseLen: UInt32 = 0
        var errorPointer: UnsafeMutablePointer<CChar>?
        let responsePointer = requestData.withUnsafeBytes { rawBuffer in
            wm_engine_evaluate(
                handle,
                rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                UInt32(requestData.count),
                &responseLen,
                &errorPointer
            )
        }
        defer {
            wm_error_free(errorPointer)
            wm_buffer_free(responsePointer)
        }

        let errorMessage = errorPointer.map { String(cString: $0) }
        guard let responsePointer else {
            if let errorMessage {
                return internalError("native runtime failed to evaluate request: \(errorMessage)")
            }
            return internalError("native runtime failed to evaluate request")
        }

        let responseData = Data(bytes: responsePointer, count: Int(responseLen))
        do {
            return try FeatureFlagJSON.decoder.decode(FeatureFlagEnvelope.self, from: responseData)
        } catch {
            return internalError("failed to decode native response: \(error)")
        }
    }
}
