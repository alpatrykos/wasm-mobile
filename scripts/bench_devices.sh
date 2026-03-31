#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METRICS_DIR="${ROOT_DIR}/artifacts/metrics"
ANDROID_DIR="${ROOT_DIR}/android-host"
IOS_DIR="${ROOT_DIR}/ios-host"
ANDROID_TEST_PACKAGE="${ANDROID_TEST_PACKAGE:-com.example.wasmmobile.test}"
ANDROID_BENCHMARK_CLASS="${ANDROID_BENCHMARK_CLASS:-com.example.wasmmobile.FeatureFlagBenchmarkInstrumentedTest}"
IOS_SCHEME="${IOS_SCHEME:-WasmMobileDevice}"
IOS_TEST_TARGET="${IOS_TEST_TARGET:-WasmMobileDeviceTests}"
IOS_CONFIGURATION="${IOS_CONFIGURATION:-Debug}"
IOS_CODE_SIGN_IDENTITY="${IOS_CODE_SIGN_IDENTITY:-Apple Development}"
IOS_BUNDLE_ID_PREFIX="${IOS_BUNDLE_ID_PREFIX:-com.example.wasmmobile}"
RESULT_BUNDLE_PATH="$(mktemp -d)/WasmMobileDevice.xcresult"

mkdir -p "${METRICS_DIR}"
trap 'rm -rf "${RESULT_BUNDLE_PATH%/*.xcresult}"' EXIT

if [[ -z "${IOS_DEVELOPMENT_TEAM:-}" ]]; then
  echo "IOS_DEVELOPMENT_TEAM is required for physical iPhone benchmarking" >&2
  exit 1
fi

select_android_serial() {
  local candidates=()
  while read -r serial state; do
    [[ -z "${serial}" || "${state}" != "device" ]] && continue
    if [[ "$(adb -s "${serial}" shell getprop ro.boot.qemu 2>/dev/null | tr -d '\r')" == "1" ]]; then
      continue
    fi
    candidates+=("${serial}")
  done < <(adb devices | awk 'NR > 1 { print $1, $2 }')

  if [[ -n "${ANDROID_SERIAL:-}" ]]; then
    local wanted="${ANDROID_SERIAL}"
    if [[ ! " ${candidates[*]} " =~ " ${wanted} " ]]; then
      echo "ANDROID_SERIAL=${wanted} is not an attached physical Android device" >&2
      exit 1
    fi
    printf '%s\n' "${wanted}"
    return
  fi

  case "${#candidates[@]}" in
    0)
      echo "no attached physical Android device found" >&2
      exit 1
      ;;
    1)
      printf '%s\n' "${candidates[0]}"
      ;;
    *)
      echo "multiple physical Android devices found; set ANDROID_SERIAL" >&2
      printf '  %s\n' "${candidates[@]}" >&2
      exit 1
      ;;
  esac
}

select_ios_device_id() {
  local device_lines=()
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    [[ "${line}" == *"Simulator"* ]] && continue
    [[ "${line}" == *"Mac"* ]] && continue
    [[ "${line}" != *"iPhone"* ]] && continue
    device_lines+=("${line}")
  done < <(
    xcrun xctrace list devices | awk '
      /^== Devices ==/ { in_devices = 1; next }
      /^== / { in_devices = 0 }
      in_devices { print }
    '
  )

  if [[ -n "${IOS_DEVICE_ID:-}" ]]; then
    if ! printf '%s\n' "${device_lines[@]}" | grep -Fq "(${IOS_DEVICE_ID})"; then
      echo "IOS_DEVICE_ID=${IOS_DEVICE_ID} is not an attached physical iPhone" >&2
      exit 1
    fi
    printf '%s\n' "${IOS_DEVICE_ID}"
    return
  fi

  case "${#device_lines[@]}" in
    0)
      echo "no attached physical iPhone found" >&2
      exit 1
      ;;
    1)
      printf '%s\n' "${device_lines[0]}" | sed -E 's/.*\(([A-F0-9-]+)\)$/\1/'
      ;;
    *)
      echo "multiple physical iPhones found; set IOS_DEVICE_ID" >&2
      printf '  %s\n' "${device_lines[@]}" >&2
      exit 1
      ;;
  esac
}

validate_json_payload() {
  local input_json="$1"
  local output_path="$2"
  INPUT_JSON="${input_json}" python3 - "${output_path}" <<'PY'
import json
import pathlib
import os
import sys

output_path = pathlib.Path(sys.argv[1])
payload = json.loads(os.environ["INPUT_JSON"])
if payload.get("used_stub"):
    raise SystemExit("benchmark payload reported used_stub=true")
output_path.write_text(json.dumps(payload, separators=(",", ":")) + "\n", encoding="utf-8")
PY
}

"${ROOT_DIR}/scripts/build_wasm.sh"
"${ROOT_DIR}/scripts/sync_artifacts.sh"

ANDROID_SERIAL_SELECTED="$(select_android_serial)"
IOS_DEVICE_ID_SELECTED="$(select_ios_device_id)"

(
  cd "${ANDROID_DIR}"
  ANDROID_SERIAL="${ANDROID_SERIAL_SELECTED}" ./gradlew \
    :sdk:connectedDebugAndroidTest \
    -Pandroid.testInstrumentationRunnerArguments.class="${ANDROID_BENCHMARK_CLASS}"
)

ANDROID_JSON="$(
  adb -s "${ANDROID_SERIAL_SELECTED}" shell run-as "${ANDROID_TEST_PACKAGE}" cat files/benchmark.json 2>/dev/null |
    tr -d '\r'
)"
if [[ -z "${ANDROID_JSON}" ]]; then
  echo "failed to read Android benchmark artifact from ${ANDROID_TEST_PACKAGE}/files/benchmark.json" >&2
  exit 1
fi

ANDROID_SO_PATH="$(find "${ROOT_DIR}/android-host/sdk/build/intermediates/cxx/Debug" -name libwasm_mobile.so | head -n1 || true)"
ANDROID_SO_SIZE=0
if [[ -n "${ANDROID_SO_PATH}" ]]; then
  ANDROID_SO_SIZE="$(stat -f '%z' "${ANDROID_SO_PATH}")"
fi

ANDROID_JSON="$(
  ANDROID_JSON="${ANDROID_JSON}" ANDROID_SO_SIZE="${ANDROID_SO_SIZE}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["ANDROID_JSON"])
payload["native_lib_size_bytes"] = int(os.environ["ANDROID_SO_SIZE"])
print(json.dumps(payload, separators=(",", ":")))
PY
)"
validate_json_payload "${ANDROID_JSON}" "${METRICS_DIR}/android-device.json"

if [[ ! -f "${IOS_DIR}/WasmMobile.xcodeproj/project.pbxproj" ]]; then
  ruby "${IOS_DIR}/scripts/generate_xcodeproj.rb"
fi
xcodebuild test \
  -project "${IOS_DIR}/WasmMobile.xcodeproj" \
  -scheme "${IOS_SCHEME}" \
  -configuration "${IOS_CONFIGURATION}" \
  -destination "id=${IOS_DEVICE_ID_SELECTED}" \
  -only-testing:"${IOS_TEST_TARGET}/FeatureFlagBenchmarkTests" \
  -resultBundlePath "${RESULT_BUNDLE_PATH}" \
  -allowProvisioningUpdates \
  IOS_DEVELOPMENT_TEAM="${IOS_DEVELOPMENT_TEAM}" \
  IOS_CODE_SIGN_IDENTITY="${IOS_CODE_SIGN_IDENTITY}" \
  BUNDLE_ID_PREFIX="${IOS_BUNDLE_ID_PREFIX}"

python3 "${ROOT_DIR}/scripts/extract_xcresult_attachment.py" \
  "${RESULT_BUNDLE_PATH}" \
  "benchmark.json" \
  "${METRICS_DIR}/ios-device.raw.json"

IOS_JSON="$(tr -d '\r' < "${METRICS_DIR}/ios-device.raw.json")"
validate_json_payload "${IOS_JSON}" "${METRICS_DIR}/ios-device.json"
rm -f "${METRICS_DIR}/ios-device.raw.json"

python3 - <<'PY' "${METRICS_DIR}/android-device.json" "${METRICS_DIR}/ios-device.json" "${METRICS_DIR}/android.json" "${METRICS_DIR}/ios.json" "${METRICS_DIR}/device-summary.json"
import json
import pathlib
import sys
from datetime import datetime, timezone

android_device_path = pathlib.Path(sys.argv[1])
ios_device_path = pathlib.Path(sys.argv[2])
android_baseline_path = pathlib.Path(sys.argv[3])
ios_baseline_path = pathlib.Path(sys.argv[4])
summary_path = pathlib.Path(sys.argv[5])

def load_optional(path: pathlib.Path):
    if not path.exists():
        return None
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)

def delta(device, baseline, field):
    if device is None or baseline is None:
        return None
    return device.get(field) - baseline.get(field)

android_device = load_optional(android_device_path)
ios_device = load_optional(ios_device_path)
android_baseline = load_optional(android_baseline_path)
ios_baseline = load_optional(ios_baseline_path)

summary = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "android": {
        "device_metrics_path": str(android_device_path.relative_to(summary_path.parent.parent)),
        "baseline_metrics_path": str(android_baseline_path.relative_to(summary_path.parent.parent)) if android_baseline else None,
        "cold_start_delta_micros": delta(android_device, android_baseline, "cold_start_micros"),
        "steady_state_delta_micros": delta(android_device, android_baseline, "steady_state_mean_micros"),
        "engine_init_delta_micros": delta(android_device, android_baseline, "engine_init_micros"),
    },
    "ios": {
        "device_metrics_path": str(ios_device_path.relative_to(summary_path.parent.parent)),
        "baseline_metrics_path": str(ios_baseline_path.relative_to(summary_path.parent.parent)) if ios_baseline else None,
        "cold_start_delta_micros": delta(ios_device, ios_baseline, "cold_start_micros"),
        "steady_state_delta_micros": delta(ios_device, ios_baseline, "steady_state_mean_micros"),
        "engine_init_delta_micros": delta(ios_device, ios_baseline, "engine_init_micros"),
    },
}

summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
PY

echo "==> physical-device metrics written under ${METRICS_DIR}"
