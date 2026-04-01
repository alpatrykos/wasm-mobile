# wasm-mobile

Small proof-of-concept for compiling a deterministic slice of mobile SDK logic to WebAssembly in Rust and running it from thin Android and iOS host adapters.

## What This Builds

- `shared-core`: Rust feature-flag evaluator with a tiny JSON byte-buffer wasm ABI.
- `android-host`: Android library module with Kotlin API and JNI/C++ bridge to Wasm3.
- `ios-host`: Swift sources shared between a Swift package path and an Xcode project used for hosted simulator and device tests.
- `fixtures`: shared golden test vectors consumed by Rust, Android, and iOS tests.
- `scripts`: plain shell entrypoints for bootstrap, build, sync, test, and benchmark flows.

## Chosen Module

The shared module is a single-feature flag evaluator with ordered rules and a default variant. It is a good wasm candidate because it is:

- pure and deterministic
- easy to represent as flat JSON buffers
- representative of duplicated SDK business logic
- simple to test with shared golden fixtures

## Repo Layout

```text
shared-core/
artifacts/
android-host/
ios-host/
fixtures/
docs/
scripts/
third_party/wasm3/
```

## Quickstart

```bash
./scripts/bootstrap.sh
./scripts/build_wasm.sh
./scripts/sync_artifacts.sh
cargo test --manifest-path shared-core/Cargo.toml
./scripts/test_ios.sh
./scripts/test_android.sh
./scripts/bench.sh
IOS_DEVELOPMENT_TEAM=YOURTEAMID ./scripts/bench_devices.sh
```

## Wasm Boundary

The wasm module exports exactly three functions:

- `wasm_alloc(len: i32) -> i32`
- `wasm_free(ptr: i32, len: i32)`
- `evaluate_feature_flag(ptr: i32, len: i32) -> i64`

Inputs and outputs are UTF-8 JSON byte buffers. The return value from `evaluate_feature_flag` packs the response pointer into the high 32 bits and the response length into the low 32 bits.

## Build Notes

- The preferred target is `wasm32v1-none`.
- If that target is unavailable, the scripts fall back to `wasm32-unknown-unknown` with MVP-oriented codegen flags and print a warning.
- Both hosts load `artifacts/shared-core.wasm` as a bundled resource and fall back to a stub response if wasm loading fails.
- iOS simulator and device automation now runs through `ios-host/WasmMobile.xcodeproj`; the Swift package layout remains as the shared source container, not the primary automation entrypoint.

## Device Benchmarking

Physical-device benchmarking uses:

- `ANDROID_SERIAL` or a single attached non-emulator Android device
- `IOS_DEVICE_ID` or a single attached physical iPhone
- required `IOS_DEVELOPMENT_TEAM`
- optional `IOS_CODE_SIGN_IDENTITY`, `IOS_BUNDLE_ID_PREFIX`, and `IOS_CONFIGURATION`

The command writes:

- `artifacts/metrics/android-device.json`
- `artifacts/metrics/ios-device.json`
- `artifacts/metrics/device-summary.json`

## Next Steps

1. Replace the JSON buffer ABI with a slimmer binary encoding only if profiling shows the JSON boundary is material.
2. Re-evaluate Wasm3 against WAMR if maintenance posture becomes a blocker.
3. Add more rule operators only after validating the minimal host/runtime path.
4. Run `./scripts/bench_devices.sh` on attached hardware and fold the first Android/iPhone measurements into `docs/REPORT.md`.
5. Decide whether to expand only to deterministic SDK logic or stop after the evaluation report.
