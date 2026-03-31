#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METRICS_DIR="${ROOT_DIR}/artifacts/metrics"
ANDROID_AVD_NAME="${ANDROID_AVD_NAME:-Pixel_3a_API_34_extension_level_7_arm64-v8a}"
ANDROID_TEST_PACKAGE="${ANDROID_TEST_PACKAGE:-com.example.wasmmobile.test}"
IOS_TEST_TARGET="${IOS_TEST_TARGET:-WasmMobileDeviceTests}"
BUNDLE_ID_PREFIX="${IOS_BUNDLE_ID_PREFIX:-com.example.wasmmobile}"
EMULATOR_BIN="${ANDROID_HOME:-$HOME/Library/Android/sdk}/emulator/emulator"
mkdir -p "${METRICS_DIR}"

"${ROOT_DIR}/scripts/build_wasm.sh"
"${ROOT_DIR}/scripts/sync_artifacts.sh"

WASM_SIZE="$(stat -f '%z' "${ROOT_DIR}/artifacts/shared-core.wasm")"
printf '{\n  "wasm_size_bytes": %s\n}\n' "${WASM_SIZE}" > "${METRICS_DIR}/size.json"

ANDROID_LOG="$(mktemp)"
IOS_LOG="$(mktemp)"
IOS_DESTINATION="${IOS_SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 16,OS=18.0}"
IOS_RESULT_DIR="$(mktemp -d)"
IOS_RESULT_BUNDLE="${IOS_RESULT_DIR}/WasmMobileDevice.xcresult"
STARTED_EMULATOR=0
EMU_PID=""
trap 'rm -f "${ANDROID_LOG}" "${IOS_LOG}"; rm -rf "${IOS_RESULT_DIR}"' EXIT

has_android_device() {
  adb devices | awk 'NR > 1 && $2 == "device" { found = 1 } END { exit(found ? 0 : 1) }'
}

wait_for_android_boot() {
  local attempts=0
  until adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' | grep -qx "1"; do
    attempts=$((attempts + 1))
    if [[ ${attempts} -gt 120 ]]; then
      echo "emulator did not boot in time" >&2
      exit 1
    fi
    sleep 5
  done
}

if ! has_android_device; then
  echo "==> starting emulator ${ANDROID_AVD_NAME}"
  "${EMULATOR_BIN}" -avd "${ANDROID_AVD_NAME}" -no-window -no-audio -no-boot-anim >/tmp/wasm-mobile-bench-emulator.log 2>&1 &
  EMU_PID=$!
  STARTED_EMULATOR=1
  adb wait-for-device
  wait_for_android_boot
fi

adb logcat -c >/dev/null 2>&1 || true

(
  cd "${ROOT_DIR}/android-host"
  if [[ -x ./gradlew ]]; then
    ./gradlew :sdk:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.wasmmobile.FeatureFlagBenchmarkInstrumentedTest
  else
    gradle :sdk:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.example.wasmmobile.FeatureFlagBenchmarkInstrumentedTest
  fi
) | tee "${ANDROID_LOG}"

ANDROID_JSON="$(
  adb shell run-as "${ANDROID_TEST_PACKAGE}" cat files/benchmark.json 2>/dev/null |
    tr -d '\r' || true
)"
if [[ -z "${ANDROID_JSON}" ]]; then
  ANDROID_JSON="$(grep 'BENCHMARK_JSON:' "${ANDROID_LOG}" | tail -n1 | sed 's/^.*BENCHMARK_JSON: //' || true)"
fi
if [[ -z "${ANDROID_JSON}" ]]; then
  ANDROID_JSON="$(adb logcat -d -s WasmMobileBench:I | tail -n1 | sed 's/^.*WasmMobileBench: //' || true)"
fi
if [[ -n "${ANDROID_JSON}" ]]; then
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
  printf '%s\n' "${ANDROID_JSON}" > "${METRICS_DIR}/android.json"
fi

if [[ ${STARTED_EMULATOR} -eq 1 ]]; then
  adb emu kill >/dev/null 2>&1 || true
  if [[ -n "${EMU_PID}" ]]; then
    wait "${EMU_PID}" || true
  fi
fi

if [[ ! -f "${ROOT_DIR}/ios-host/WasmMobile.xcodeproj/project.pbxproj" ]]; then
  ruby "${ROOT_DIR}/ios-host/scripts/generate_xcodeproj.rb"
fi
(
  cd "${ROOT_DIR}/ios-host"
  xcodebuild test \
    -project WasmMobile.xcodeproj \
    -scheme WasmMobileDevice \
    -destination "${IOS_DESTINATION}" \
    -only-testing:${IOS_TEST_TARGET}/FeatureFlagBenchmarkTests \
    -resultBundlePath "${IOS_RESULT_BUNDLE}" \
    CODE_SIGNING_ALLOWED=NO \
    BUNDLE_ID_PREFIX="${BUNDLE_ID_PREFIX}"
) | tee "${IOS_LOG}"

IOS_JSON=""
if python3 "${ROOT_DIR}/scripts/extract_xcresult_attachment.py" \
  "${IOS_RESULT_BUNDLE}" \
  "benchmark.json" \
  "${METRICS_DIR}/ios.json" >/dev/null 2>&1; then
  IOS_JSON="$(tr -d '\r' < "${METRICS_DIR}/ios.json")"
else
  IOS_JSON="$(grep 'BENCHMARK_JSON:' "${IOS_LOG}" | tail -n1 | sed 's/^.*BENCHMARK_JSON: //' || true)"
fi
  if [[ -n "${IOS_JSON}" ]]; then
  printf '%s\n' "${IOS_JSON}" > "${METRICS_DIR}/ios.json"
fi

echo "==> metrics written under ${METRICS_DIR}"
