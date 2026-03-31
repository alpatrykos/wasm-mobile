import Foundation
import XCTest
@testable import WasmMobile

private struct FixtureCase: Decodable {
    let name: String
    let request: FeatureFlagRequest
    let expectedResponse: FeatureFlagEnvelope

    enum CodingKeys: String, CodingKey {
        case name
        case request
        case expectedResponse = "expected_response"
    }
}

final class FeatureFlagEngineTests: XCTestCase {
    func testEvaluatesSharedFixtures() throws {
        let fixtures = try loadFixtures()
        let engine = FeatureFlagEngine()
        XCTAssertFalse(engine.isUsingStub)

        for fixture in fixtures {
            let actual = engine.evaluate(fixture.request)
            XCTAssertEqual(actual, fixture.expectedResponse, fixture.name)
        }
    }

    func testFallsBackToStubWhenResourceIsMissing() {
        let engine = FeatureFlagEngine(wasmResourceName: "missing")
        XCTAssertTrue(engine.isUsingStub)

        let response = engine.evaluate(
            FeatureFlagRequest(
                flagKey: "new_home",
                defaultVariant: "off",
                rules: [],
                context: [:]
            )
        )

        XCTAssertEqual(response.result?.source, "stub")
        XCTAssertEqual(response.result?.variant, "off")
    }
}

private func loadFixtures() throws -> [FixtureCase] {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let fixtureURL = testFileURL
        .deletingLastPathComponent()
        .appendingPathComponent("../../../fixtures/feature_flag_cases.json")
        .standardizedFileURL
    let data = try Data(contentsOf: fixtureURL)
    return try FeatureFlagJSON.decoder.decode([FixtureCase].self, from: data)
}

