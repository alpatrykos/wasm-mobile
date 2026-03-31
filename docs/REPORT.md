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

## Measured Results

Measurements below come from `scripts/bench.sh` on March 31, 2026 on this development machine, using:

- Android emulator: `Pixel_3a_API_34_extension_level_7_arm64-v8a`
- iOS simulator: `iPhone 16` on iOS 18.0

Concrete results:

- wasm artifact size: `121,595` bytes (`118.7 KiB`)
- Android host native library size: `2,395,160` bytes (`2.29 MiB`)
- iOS host test-bundle executable size: `1,110,560` bytes (`1.06 MiB`)
- Android engine init: `16,310.46 µs` (`16.31 ms`)
- Android cold start through first evaluation: `47,187.50 µs` (`47.19 ms`)
- Android steady-state mean latency: `921.81 µs`
- iOS engine init: `20,582.88 µs` (`20.58 ms`)
- iOS cold start through first evaluation: `56,548.96 µs` (`56.55 ms`)
- iOS steady-state mean latency: `319.91 µs`

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

## Runtime Risk

Wasm3 is in a minimal-maintenance phase. That is acceptable for a PoC but not enough by itself for broad production adoption without an explicit ownership and upgrade strategy.

## Recommendation

- proceed only for selected logic classes

Rationale:

- The shared core itself is small enough to be attractive.
- Steady-state latency is acceptable for low-frequency deterministic SDK logic.
- The host/runtime size overhead is significant relative to the wasm artifact, especially on Android.
- Cold-start cost is noticeable, so this should not be the default answer for startup-critical or ultra-hot logic.
- Wasm3's maintenance posture is still a real adoption risk.

Practical conclusion:

- expand only for small, deterministic, high-value logic slices such as feature evaluation, consent parsing, or rules helpers
- avoid broad framework-style adoption until physical-device measurements and runtime ownership are clearer
