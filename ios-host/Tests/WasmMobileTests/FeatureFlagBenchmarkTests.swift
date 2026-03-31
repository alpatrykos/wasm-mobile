import Foundation
import XCTest
@testable import WasmMobile

final class FeatureFlagBenchmarkTests: XCTestCase {
    func testEmitsBenchmarkJson() throws {
        let request = FeatureFlagRequest(
            flagKey: "new_home",
            defaultVariant: "off",
            rules: [
                FeatureRule(attribute: "country", op: "eq", value: .string("DE"), variant: "on"),
                FeatureRule(attribute: "app_version", op: "gte", value: .number(120), variant: "canary"),
            ],
            context: [
                "country": .string("PL"),
                "app_version": .number(130),
            ]
        )

        let initStart = DispatchTime.now().uptimeNanoseconds
        let engine = FeatureFlagEngine()
        let initEnd = DispatchTime.now().uptimeNanoseconds
        XCTAssertFalse(engine.isUsingStub)

        let firstStart = DispatchTime.now().uptimeNanoseconds
        let firstResponse = engine.evaluate(request)
        let firstEnd = DispatchTime.now().uptimeNanoseconds
        XCTAssertTrue(firstResponse.ok)

        let steadyStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<1_000 {
            _ = engine.evaluate(request)
        }
        let steadyEnd = DispatchTime.now().uptimeNanoseconds

        let wasmSize = try wasmResourceSize()
        let executableSize = try testBundleExecutableSize()

        let payload: [String: Any] = [
            "platform": "ios",
            "wasm_size_bytes": wasmSize,
            "host_binary_size_bytes": executableSize,
            "engine_init_micros": Double(initEnd - initStart) / 1_000.0,
            "cold_start_micros": Double(firstEnd - initStart) / 1_000.0,
            "steady_state_mean_micros": Double(steadyEnd - steadyStart) / 1_000.0 / 1_000.0,
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let jsonString = String(decoding: jsonData, as: UTF8.self)
        print("BENCHMARK_JSON: \(jsonString)")
    }

    private func wasmResourceSize() throws -> Int64 {
        guard let url = Bundle.module.url(forResource: "shared-core", withExtension: "wasm") else {
            throw NSError(domain: "WasmMobileTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing wasm resource"])
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private func testBundleExecutableSize() throws -> Int64 {
        guard let executableURL = Bundle(for: Self.self).executableURL else {
            throw NSError(domain: "WasmMobileTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "missing test bundle executable"])
        }
        let values = try executableURL.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }
}
