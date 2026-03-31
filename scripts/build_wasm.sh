#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_TOOLCHAIN="${RUST_TOOLCHAIN:-stable}"
PREFERRED_TARGET="${WASM_TARGET:-wasm32v1-none}"
FALLBACK_TARGET="wasm32-unknown-unknown"

choose_target() {
  if rustup +"${RUST_TOOLCHAIN}" target list --installed | grep -qx "${PREFERRED_TARGET}"; then
    printf '%s' "${PREFERRED_TARGET}"
    return
  fi

  if rustup +"${RUST_TOOLCHAIN}" target list --installed | grep -qx "${FALLBACK_TARGET}"; then
    printf '%s' "${FALLBACK_TARGET}"
    return
  fi

  echo "missing wasm target; run ./scripts/bootstrap.sh first" >&2
  exit 1
}

TARGET="$(choose_target)"
ARTIFACT_DIR="${ROOT_DIR}/artifacts"
mkdir -p "${ARTIFACT_DIR}"

RUSTFLAGS_EXTRA=()
if [[ "${TARGET}" == "${FALLBACK_TARGET}" ]]; then
  RUSTFLAGS_EXTRA=(-Ctarget-cpu=mvp -Ctarget-feature=+mutable-globals)
  echo "warning: building fallback target ${TARGET}" >&2
fi

echo "==> building shared-core for ${TARGET}"
(
  cd "${ROOT_DIR}"
  CARGO_TARGET_DIR="${ROOT_DIR}/shared-core/target" \
  RUSTFLAGS="${RUSTFLAGS_EXTRA[*]:-}" \
  cargo +"${RUST_TOOLCHAIN}" build --release --target "${TARGET}" --manifest-path shared-core/Cargo.toml
)

SOURCE_WASM="${ROOT_DIR}/shared-core/target/${TARGET}/release/shared_core.wasm"
DEST_WASM="${ARTIFACT_DIR}/shared-core.wasm"

cp "${SOURCE_WASM}" "${DEST_WASM}"
echo "==> wrote ${DEST_WASM}"
stat -f "size=%z bytes" "${DEST_WASM}"

