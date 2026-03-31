#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_TOOLCHAIN="${RUST_TOOLCHAIN:-stable}"

echo "==> ensuring Rust toolchain: ${RUST_TOOLCHAIN}"
rustup toolchain install "${RUST_TOOLCHAIN}" >/dev/null

echo "==> trying preferred target wasm32v1-none"
if rustup +"${RUST_TOOLCHAIN}" target add wasm32v1-none >/dev/null 2>&1; then
  echo "installed wasm32v1-none"
else
  echo "warning: failed to install wasm32v1-none; falling back to wasm32-unknown-unknown" >&2
  rustup +"${RUST_TOOLCHAIN}" target add wasm32-unknown-unknown >/dev/null
  echo "note: fallback uses '-Ctarget-cpu=mvp -Ctarget-feature=+mutable-globals' in build_wasm.sh" >&2
fi

echo "==> bootstrap complete"
echo "next:"
echo "  ${ROOT_DIR}/scripts/build_wasm.sh"
echo "  ${ROOT_DIR}/scripts/sync_artifacts.sh"

