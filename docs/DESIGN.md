# Design Notes

## Scope

This PoC shares one deterministic SDK-style module across Android and iOS by compiling Rust to WebAssembly and embedding the same wasm artifact in both hosts.

## Module Choice

The chosen module is single-flag evaluation with ordered rules and a default variant.

Why it fits:

- no platform APIs
- no I/O or storage
- easy to validate with golden fixtures
- representative of business logic that often drifts between mobile codebases

## Boundary

The wasm ABI is intentionally tiny:

- host allocates guest memory with `wasm_alloc`
- host copies a UTF-8 JSON request into guest memory
- host invokes `evaluate_feature_flag`
- host reads the packed pointer/length result from guest memory
- host frees both input and output buffers with `wasm_free`

All structural complexity stays inside Rust and the native adapters. The FFI surface stays limited to integers and byte buffers.

## Request Model

Each request contains:

- `flag_key`
- `default_variant`
- ordered `rules`
- `context`

Supported operators in v1:

- `eq`
- `neq`
- `gte`

Supported values in v1:

- string
- number
- bool

## Host Strategy

Android:

- Kotlin public API
- JNI/C++ bridge
- bundled `shared-core.wasm` asset
- stub fallback if wasm init/load fails

iOS:

- Swift public API
- C bridge compiled into a hosted Xcode project path for simulator and device automation
- bundled `shared-core.wasm` resource
- stub fallback if wasm init/load fails

Why the project path exists:

- the original Swift package layout is still useful for shared source organization
- physical-device XCTest execution needs a signed host app and result bundle handling that is more reliable through an Xcode project than a package-only flow

## Runtime Choice

Wasm3 is vendored because it has a small interpreter footprint, explicit Android/iOS support, and a straightforward C embedding API. The report calls out its minimal-maintenance status as a material risk.

## Fallback Behavior

If a host cannot load the bundled wasm or initialize the runtime, it returns a stub success response using the request's `default_variant` and `source = "stub"`.
