#![cfg_attr(target_family = "wasm", no_std)]

extern crate alloc;

#[cfg(any(test, not(target_family = "wasm")))]
extern crate std;

#[cfg(target_family = "wasm")]
use alloc::boxed::Box;
use alloc::collections::BTreeMap;
use alloc::format;
use alloc::string::{String, ToString};
#[cfg(target_family = "wasm")]
use alloc::vec;
use alloc::vec::Vec;
#[cfg(target_family = "wasm")]
use core::mem;
#[cfg(target_family = "wasm")]
use core::slice;

use serde::{Deserialize, Serialize};

#[cfg(target_family = "wasm")]
#[global_allocator]
static ALLOCATOR: wee_alloc::WeeAlloc = wee_alloc::WeeAlloc::INIT;

#[cfg(target_family = "wasm")]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo<'_>) -> ! {
    core::arch::wasm32::unreachable()
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct FeatureFlagRequest {
    pub flag_key: String,
    pub default_variant: String,
    pub rules: Vec<FeatureRule>,
    pub context: BTreeMap<String, ScalarValue>,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct FeatureRule {
    pub attribute: String,
    pub op: String,
    pub value: ScalarValue,
    pub variant: String,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(untagged)]
pub enum ScalarValue {
    String(String),
    Number(f64),
    Bool(bool),
}

#[derive(Debug, Deserialize, PartialEq, Serialize)]
pub struct SuccessEnvelope {
    pub ok: bool,
    pub result: FeatureFlagResult,
}

#[derive(Debug, Deserialize, PartialEq, Serialize)]
pub struct ErrorEnvelope {
    pub ok: bool,
    pub error: ErrorDetails,
}

#[derive(Debug, Deserialize, PartialEq, Serialize)]
pub struct ErrorDetails {
    pub code: String,
    pub message: String,
}

#[derive(Debug, Deserialize, PartialEq, Serialize)]
pub struct FeatureFlagResult {
    pub flag_key: String,
    pub variant: String,
    pub reason: String,
    pub matched_rule_index: Option<usize>,
    pub source: String,
}

#[derive(Debug, Deserialize, PartialEq, Serialize)]
#[serde(untagged)]
pub enum ResponseEnvelope {
    Success(SuccessEnvelope),
    Error(ErrorEnvelope),
}

pub fn evaluate_request(request: &FeatureFlagRequest) -> ResponseEnvelope {
    match validate_request(request) {
        Ok(()) => {}
        Err(error) => return error,
    }

    for (index, rule) in request.rules.iter().enumerate() {
        let context_value = match request.context.get(&rule.attribute) {
            Some(value) => value,
            None => continue,
        };

        let is_match = match apply_rule(context_value, &rule.op, &rule.value) {
            Ok(value) => value,
            Err(error) => return error,
        };

        if is_match {
            return ResponseEnvelope::Success(SuccessEnvelope {
                ok: true,
                result: FeatureFlagResult {
                    flag_key: request.flag_key.clone(),
                    variant: rule.variant.clone(),
                    reason: "rule_match".to_string(),
                    matched_rule_index: Some(index),
                    source: "wasm".to_string(),
                },
            });
        }
    }

    ResponseEnvelope::Success(SuccessEnvelope {
        ok: true,
        result: FeatureFlagResult {
            flag_key: request.flag_key.clone(),
            variant: request.default_variant.clone(),
            reason: "default".to_string(),
            matched_rule_index: None,
            source: "wasm".to_string(),
        },
    })
}

pub fn evaluate_json_bytes(input: &[u8]) -> Vec<u8> {
    let response = match serde_json::from_slice::<FeatureFlagRequest>(input) {
        Ok(request) => evaluate_request(&request),
        Err(error) => ResponseEnvelope::Error(ErrorEnvelope {
            ok: false,
            error: ErrorDetails {
                code: "INVALID_JSON".to_string(),
                message: format!("invalid json: {error}"),
            },
        }),
    };

    serde_json::to_vec(&response).unwrap_or_else(|error| {
        serde_json::to_vec(&ResponseEnvelope::Error(ErrorEnvelope {
            ok: false,
            error: ErrorDetails {
                code: "INTERNAL_ERROR".to_string(),
                message: format!("failed to serialize response: {error}"),
            },
        }))
        .unwrap_or_else(|_| br#"{"ok":false,"error":{"code":"INTERNAL_ERROR","message":"failed to serialize response"}}"#.to_vec())
    })
}

fn validate_request(request: &FeatureFlagRequest) -> Result<(), ResponseEnvelope> {
    if request.flag_key.trim().is_empty() {
        return Err(invalid_request("flag_key must not be empty"));
    }

    if request.default_variant.trim().is_empty() {
        return Err(invalid_request("default_variant must not be empty"));
    }

    for rule in &request.rules {
        if rule.attribute.trim().is_empty() {
            return Err(invalid_request("rule attribute must not be empty"));
        }

        if rule.variant.trim().is_empty() {
            return Err(invalid_request("rule variant must not be empty"));
        }

        if !matches!(rule.op.as_str(), "eq" | "neq" | "gte") {
            return Err(ResponseEnvelope::Error(ErrorEnvelope {
                ok: false,
                error: ErrorDetails {
                    code: "UNSUPPORTED_OPERATOR".to_string(),
                    message: format!("unsupported operator: {}", rule.op),
                },
            }));
        }
    }

    Ok(())
}

fn apply_rule(
    context_value: &ScalarValue,
    op: &str,
    rule_value: &ScalarValue,
) -> Result<bool, ResponseEnvelope> {
    match op {
        "eq" => Ok(values_equal(context_value, rule_value)),
        "neq" => Ok(!values_equal(context_value, rule_value)),
        "gte" => {
            let (ScalarValue::Number(context), ScalarValue::Number(rule)) = (context_value, rule_value)
            else {
                return Err(invalid_request(
                    "gte operator requires numeric context and rule values",
                ));
            };
            Ok(context >= rule)
        }
        _ => Err(ResponseEnvelope::Error(ErrorEnvelope {
            ok: false,
            error: ErrorDetails {
                code: "UNSUPPORTED_OPERATOR".to_string(),
                message: format!("unsupported operator: {op}"),
            },
        })),
    }
}

fn values_equal(left: &ScalarValue, right: &ScalarValue) -> bool {
    match (left, right) {
        (ScalarValue::String(left), ScalarValue::String(right)) => left == right,
        (ScalarValue::Number(left), ScalarValue::Number(right)) => left == right,
        (ScalarValue::Bool(left), ScalarValue::Bool(right)) => left == right,
        _ => false,
    }
}

fn invalid_request(message: &str) -> ResponseEnvelope {
    ResponseEnvelope::Error(ErrorEnvelope {
        ok: false,
        error: ErrorDetails {
            code: "INVALID_REQUEST".to_string(),
            message: message.to_string(),
        },
    })
}

#[cfg(any(target_family = "wasm", test))]
fn pack_pointer_and_length(pointer: u32, len: u32) -> i64 {
    (((pointer as u64) << 32) | len as u64) as i64
}

pub fn unpack_pointer_and_length(value: i64) -> (u32, u32) {
    let raw = value as u64;
    ((raw >> 32) as u32, raw as u32)
}

#[cfg(target_family = "wasm")]
#[no_mangle]
pub extern "C" fn wasm_alloc(len: i32) -> i32 {
    if len <= 0 {
        return 0;
    }

    let len = len as usize;
    let mut buffer = vec![0_u8; len].into_boxed_slice();
    let pointer = buffer.as_mut_ptr();
    mem::forget(buffer);
    pointer as i32
}

#[cfg(target_family = "wasm")]
#[no_mangle]
pub extern "C" fn wasm_free(ptr: i32, len: i32) {
    if ptr == 0 || len <= 0 {
        return;
    }

    unsafe {
        let raw_slice = slice::from_raw_parts_mut(ptr as *mut u8, len as usize);
        let _ = Box::<[u8]>::from_raw(raw_slice);
    }
}

#[cfg(target_family = "wasm")]
#[no_mangle]
pub extern "C" fn evaluate_feature_flag(ptr: i32, len: i32) -> i64 {
    if ptr == 0 || len < 0 {
        let bytes = evaluate_json_bytes(b"");
        return leak_response(bytes);
    }

    let input = unsafe { slice::from_raw_parts(ptr as *const u8, len as usize) };
    let response = evaluate_json_bytes(input);
    leak_response(response)
}

#[cfg(target_family = "wasm")]
fn leak_response(response: Vec<u8>) -> i64 {
    let len = response.len() as u32;
    let mut response = response.into_boxed_slice();
    let pointer = response.as_mut_ptr() as u32;
    mem::forget(response);
    pack_pointer_and_length(pointer, len)
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloc::collections::BTreeMap;

    fn sample_request() -> FeatureFlagRequest {
        let mut context = BTreeMap::new();
        context.insert("country".to_string(), ScalarValue::String("PL".to_string()));
        context.insert("app_version".to_string(), ScalarValue::Number(130.0));

        FeatureFlagRequest {
            flag_key: "new_home".to_string(),
            default_variant: "off".to_string(),
            rules: vec![
                FeatureRule {
                    attribute: "country".to_string(),
                    op: "eq".to_string(),
                    value: ScalarValue::String("PL".to_string()),
                    variant: "on".to_string(),
                },
                FeatureRule {
                    attribute: "app_version".to_string(),
                    op: "gte".to_string(),
                    value: ScalarValue::Number(120.0),
                    variant: "canary".to_string(),
                },
            ],
            context,
        }
    }

    #[test]
    fn evaluates_rule_match() {
        let response = evaluate_request(&sample_request());
        let ResponseEnvelope::Success(response) = response else {
            panic!("expected success response");
        };

        assert_eq!(response.result.variant, "on");
        assert_eq!(response.result.matched_rule_index, Some(0));
    }

    #[test]
    fn returns_default_when_nothing_matches() {
        let mut request = sample_request();
        request.context.insert(
            "country".to_string(),
            ScalarValue::String("US".to_string()),
        );
        request.context.insert("app_version".to_string(), ScalarValue::Number(99.0));

        let response = evaluate_request(&request);
        let ResponseEnvelope::Success(response) = response else {
            panic!("expected success response");
        };

        assert_eq!(response.result.variant, "off");
        assert_eq!(response.result.reason, "default");
        assert_eq!(response.result.matched_rule_index, None);
    }

    #[test]
    fn rejects_unsupported_operator() {
        let mut request = sample_request();
        request.rules[0].op = "contains".to_string();

        let response = evaluate_request(&request);
        let ResponseEnvelope::Error(response) = response else {
            panic!("expected error response");
        };

        assert_eq!(response.error.code, "UNSUPPORTED_OPERATOR");
    }

    #[test]
    fn rejects_non_numeric_gte() {
        let mut request = sample_request();
        request.context.insert(
            "country".to_string(),
            ScalarValue::String("US".to_string()),
        );
        request.context.insert(
            "app_version".to_string(),
            ScalarValue::String("130".to_string()),
        );

        let response = evaluate_request(&request);
        let ResponseEnvelope::Error(response) = response else {
            panic!("expected error response");
        };

        assert_eq!(response.error.code, "INVALID_REQUEST");
    }

    #[test]
    fn round_trips_packed_pointer_and_length() {
        let packed = pack_pointer_and_length(0xAABBCCDD, 0x11223344);
        assert_eq!(unpack_pointer_and_length(packed), (0xAABBCCDD, 0x11223344));
    }

}
