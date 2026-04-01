# REPORT

## What Was Built

- Rust feature-flag evaluator compiled to wasm
- Android Kotlin/JNI host integration
- iOS Swift/C host integration
- shared fixtures consumed by all three test paths

## Chosen Module

Single-feature flag evaluation with ordered rules and a default variant.

Why:

- deterministic
- representative of shared SDK logic
- easy to expose through a byte-buffer ABI

## Wasm Boundary

- Request: UTF-8 JSON bytes copied into guest memory
- Response: UTF-8 JSON bytes returned by packed pointer/length
- Exports: `wasm_alloc`, `wasm_free`, `evaluate_feature_flag`

## Emulator And Simulator Baseline

Baseline measurements come from `scripts/bench.sh` on March 31, 2026 on this development machine, using:

- Android emulator: `Pixel_3a_API_34_extension_level_7_arm64-v8a`
- iOS simulator: `iPhone 16` on iOS 18.0

Concrete baseline results:

- wasm artifact size: `121,595` bytes (`118.7 KiB`)
- Android host native library size: `2,395,160` bytes (`2.29 MiB`)
- iOS host test-bundle executable size: `199,768` bytes (`195.1 KiB`)
- Android engine init: `19,833.92 µs` (`19.83 ms`)
- Android cold start through first evaluation: `52,071.29 µs` (`52.07 ms`)
- Android steady-state mean latency: `885.64 µs`
- iOS engine init: `1,737.25 µs` (`1.74 ms`)
- iOS cold start through first evaluation: `18,139.79 µs` (`18.14 ms`)
- iOS steady-state mean latency: `310.19 µs`

## Physical-Device Measurements

Android-only physical-device measurements can be written by `scripts/bench_android_device.sh` to:

- `artifacts/metrics/android-device.json`
- `artifacts/metrics/device-summary.json`

iOS-only physical-device measurements can be written by `scripts/bench_ios_device.sh` to:

- `artifacts/metrics/ios-device.json`
- `artifacts/metrics/device-summary.json`

Cross-platform physical-device measurements are written by `scripts/bench_devices.sh` to:

- `artifacts/metrics/android-device.json`
- `artifacts/metrics/ios-device.json`
- `artifacts/metrics/device-summary.json`

Current status on this machine:

- Android phone: benchmark captured via `scripts/bench_android_device.sh`
- iPhone: not attached
- full Android+iPhone run: pending first signed hardware run

## Delta Summary

- The Android-only command already records Android cold-start, steady-state, and engine-init deltas against `artifacts/metrics/android.json` in `device-summary.json`.
- The iOS-only command records iOS deltas against `artifacts/metrics/ios.json` in the same file once a signed device run exists.
- The iOS fields in `device-summary.json` stay `null` until either `scripts/bench_ios_device.sh` or `scripts/bench_devices.sh` completes with a signed iPhone run.
- The hosted iOS project path changes the simulator-side binary being measured, so the next baseline run should refresh the iOS numbers before any hardware comparison is interpreted.

Raw machine-readable outputs live in:

- `artifacts/metrics/size.json`
- `artifacts/metrics/android.json`
- `artifacts/metrics/ios.json`

## Biggest Pain Points

- iOS forbids JIT, so interpreter-style runtimes are the practical baseline.
- The ABI is deliberately primitive, which keeps interop debuggable but adds JSON serialization overhead.
- Vendoring a runtime is simple for a PoC but increases upgrade and maintenance responsibility.
- The runtime and host adapter footprint is materially larger than the wasm artifact itself, especially on Android.
- Emulator and simulator numbers are good enough for a PoC recommendation, but they are not a substitute for measurements on production device classes.
- The iOS automation path now uses a hosted Xcode project so hardware runs can be signed and exported through `.xcresult` attachments.

## Runtime Risk

Wasm3 is in a minimal-maintenance phase. That is acceptable for a PoC but not enough by itself for broad production adoption without an explicit ownership and upgrade strategy.

## Recommendation

- proceed only for selected logic classes, and confirm the recommendation on physical devices before broadening adoption

Rationale:

- The shared core itself is small enough to be attractive.
- Steady-state latency is acceptable for low-frequency deterministic SDK logic.
- The host/runtime size overhead is significant relative to the wasm artifact, especially on Android.
- Cold-start cost is noticeable, so this should not be the default answer for startup-critical or ultra-hot logic.
- Wasm3's maintenance posture is still a real adoption risk.

Practical conclusion:

- expand only for small, deterministic, high-value logic slices such as feature evaluation, consent parsing, or rules helpers
- avoid broad framework-style adoption until physical-device measurements and runtime ownership are clearer
