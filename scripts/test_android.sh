#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="${ROOT_DIR}/android-host"
AVD_NAME="${ANDROID_AVD_NAME:-Pixel_3a_API_34_extension_level_7_arm64-v8a}"
EMULATOR_BIN="${ANDROID_HOME:-$HOME/Library/Android/sdk}/emulator/emulator"
GRADLE_CMD="./gradlew"
STARTED_EMULATOR=0
EMU_PID=""

if [[ ! -f "${ROOT_DIR}/artifacts/shared-core.wasm" ]]; then
  "${ROOT_DIR}/scripts/build_wasm.sh"
fi
"${ROOT_DIR}/scripts/sync_artifacts.sh"

if [[ ! -x "${ANDROID_DIR}/gradlew" ]]; then
  GRADLE_CMD="gradle"
fi

has_device() {
  adb devices | awk 'NR > 1 && $2 == "device" { print $1; exit 0 } END { exit 1 }'
}

wait_for_boot() {
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

if ! has_device; then
  echo "==> starting emulator ${AVD_NAME}"
  "${EMULATOR_BIN}" -avd "${AVD_NAME}" -no-window -no-audio -no-boot-anim >/tmp/wasm-mobile-android-emulator.log 2>&1 &
  EMU_PID=$!
  STARTED_EMULATOR=1
  adb wait-for-device
  wait_for_boot
fi

(
  cd "${ANDROID_DIR}"
  ${GRADLE_CMD} :sdk:connectedDebugAndroidTest
)

if [[ ${STARTED_EMULATOR} -eq 1 ]]; then
  adb emu kill >/dev/null 2>&1 || true
  if [[ -n "${EMU_PID}" ]]; then
    wait "${EMU_PID}" || true
  fi
fi

