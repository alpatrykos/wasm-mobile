use std::fs;
use std::path::PathBuf;

use serde::Deserialize;
use serde_json::Value;
use shared_core::{evaluate_request, FeatureFlagRequest};

#[derive(Debug, Deserialize)]
struct FixtureCase {
    name: String,
    request: FeatureFlagRequest,
    expected_response: Value,
}

#[test]
fn fixture_cases_match_expected_json() {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../fixtures/feature_flag_cases.json");
    let bytes = fs::read(path).expect("fixture file");
    let fixtures: Vec<FixtureCase> = serde_json::from_slice(&bytes).expect("fixture json");

    for fixture in fixtures {
        let actual = serde_json::to_value(evaluate_request(&fixture.request)).expect("to value");
        assert_eq!(actual, fixture.expected_response, "fixture: {}", fixture.name);
    }
}
