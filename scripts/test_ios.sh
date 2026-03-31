#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="${ROOT_DIR}/ios-host"
DESTINATION="${IOS_SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 16,OS=18.0}"

if [[ ! -f "${ROOT_DIR}/artifacts/shared-core.wasm" ]]; then
  "${ROOT_DIR}/scripts/build_wasm.sh"
fi
"${ROOT_DIR}/scripts/sync_artifacts.sh"

(
  cd "${IOS_DIR}"
  xcodebuild test \
    -scheme WasmMobile \
    -destination "${DESTINATION}" \
    -skipPackagePluginValidation
)
