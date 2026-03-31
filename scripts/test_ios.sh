#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="${ROOT_DIR}/ios-host"
DESTINATION="${IOS_SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 16,OS=18.0}"
BUNDLE_ID_PREFIX="${IOS_BUNDLE_ID_PREFIX:-com.example.wasmmobile}"

if [[ ! -f "${ROOT_DIR}/artifacts/shared-core.wasm" ]]; then
  "${ROOT_DIR}/scripts/build_wasm.sh"
fi
"${ROOT_DIR}/scripts/sync_artifacts.sh"
if [[ ! -f "${IOS_DIR}/WasmMobile.xcodeproj/project.pbxproj" ]]; then
  ruby "${IOS_DIR}/scripts/generate_xcodeproj.rb"
fi

(
  cd "${IOS_DIR}"
  xcodebuild test \
    -project WasmMobile.xcodeproj \
    -scheme WasmMobileDevice \
    -destination "${DESTINATION}" \
    CODE_SIGNING_ALLOWED=NO \
    BUNDLE_ID_PREFIX="${BUNDLE_ID_PREFIX}"
)
