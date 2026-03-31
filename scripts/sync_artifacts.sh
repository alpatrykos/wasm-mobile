#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_WASM="${ROOT_DIR}/artifacts/shared-core.wasm"
ANDROID_WASM="${ROOT_DIR}/android-host/sdk/src/main/assets/shared-core.wasm"
IOS_WASM="${ROOT_DIR}/ios-host/Sources/WasmMobile/Resources/shared-core.wasm"

if [[ ! -f "${SOURCE_WASM}" ]]; then
  echo "missing ${SOURCE_WASM}; run ./scripts/build_wasm.sh first" >&2
  exit 1
fi

mkdir -p "$(dirname "${ANDROID_WASM}")" "$(dirname "${IOS_WASM}")"
cp "${SOURCE_WASM}" "${ANDROID_WASM}"
cp "${SOURCE_WASM}" "${IOS_WASM}"

echo "==> synced wasm artifact"
echo "android: ${ANDROID_WASM}"
echo "iOS:     ${IOS_WASM}"

