import Foundation
#if canImport(UIKit)
import UIKit
#endif
import XCTest
@testable import WasmMobile

final class FeatureFlagBenchmarkTests: XCTestCase {
    private let sampleCount = 1_000

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

        let firstResponse = engine.evaluate(request)
        let firstEnd = DispatchTime.now().uptimeNanoseconds
        XCTAssertTrue(firstResponse.ok)

        let steadyStart = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<sampleCount {
            _ = engine.evaluate(request)
        }
        let steadyEnd = DispatchTime.now().uptimeNanoseconds

        let wasmSize = try wasmResourceSize()
        let executableSize = try testBundleExecutableSize()

        let payload: [String: Any] = [
            "platform": "ios",
            "execution_target": executionTarget(),
            "device_name": deviceName(),
            "device_model": deviceModel(),
            "os_version": osVersion(),
            "arch": architecture(),
            "sample_count": sampleCount,
            "wasm_size_bytes": wasmSize,
            "host_binary_size_bytes": executableSize,
            "engine_init_micros": Double(initEnd - initStart) / 1_000.0,
            "cold_start_micros": Double(firstEnd - initStart) / 1_000.0,
            "steady_state_mean_micros": Double(steadyEnd - steadyStart) / 1_000.0 / 1_000.0,
            "used_stub": engine.isUsingStub,
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let jsonString = String(decoding: jsonData, as: UTF8.self)
        addBenchmarkAttachment(jsonData: jsonData)
        print("BENCHMARK_JSON: \(jsonString)")
    }

    private func wasmResourceSize() throws -> Int64 {
        guard let url = WasmMobileResources.bundle.url(forResource: "shared-core", withExtension: "wasm") else {
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

    private func addBenchmarkAttachment(jsonData: Data) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("benchmark.json")
        try? jsonData.write(to: url, options: [.atomic])

        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.name = "benchmark.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func executionTarget() -> String {
        #if targetEnvironment(simulator)
        return "simulator"
        #else
        return "physical_device"
        #endif
    }

    private func deviceName() -> String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "unknown"
        #endif
    }

    private func deviceModel() -> String {
        if let simulatedModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulatedModel
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
    }

    private func osVersion() -> String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    private func architecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
