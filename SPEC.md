Build a small proof-of-concept that compiles a non-UI slice of a mobile SDK to WebAssembly and runs it from both Android and iOS.

Goal:
Reduce duplicated business logic across Android and iOS by implementing one shared core in Rust, compiling it to WebAssembly, and hosting it from thin native adapters on both platforms.

Scope:

- Pick one small, pure, deterministic module suitable for shared logic.
- Good candidates:
  - consent / privacy parsing and validation
  - lightweight rules engine
  - auction scoring / ranking helper
  - feature flag evaluation
- Avoid UI, networking, storage, threads, and platform-specific APIs.
- Keep the PoC intentionally small and reviewable.

Success criteria:

- A Rust library builds to a .wasm artifact.
- The same exported functions are callable from Android and iOS.
- The same golden tests / fixtures pass on both platforms.
- We produce a short evaluation of:
  - wasm binary size
  - runtime / host size overhead
  - cold start cost
  - steady-state call latency
  - integration complexity
  - notable risks and next steps

Technical requirements:

- Implement the shared logic in Rust.
- Expose a very small FFI surface:
  - prefer primitives and flat byte buffers
  - avoid complex nested structs over FFI
- Produce a wasm artifact suitable for embedding in mobile apps.
- Add a thin Android host layer and a thin iOS host layer.
- Keep platform adapters minimal; core logic must live in Rust.
- Include a fallback or stub strategy if wasm loading fails.

Expected repo structure:

- /shared-core          Rust source for shared logic
- /artifacts            built wasm artifact(s)
- /android-host         Android sample/integration wrapper
- /ios-host             iOS sample/integration wrapper
- /fixtures             shared test vectors / golden files
- /docs                 design notes + findings
- /scripts              build/test helper scripts

Implementation tasks:

1. Select a tiny target module and document why it is a good wasm candidate.
2. Define the public API for the shared core:
   - exported functions
   - input/output encoding
   - error model
3. Implement the Rust core with unit tests.
4. Compile it to wasm with release optimizations.
5. Add Android integration:
   - load wasm from bundled assets/resources
   - call exported functions from Kotlin/Java
   - return typed results to caller
6. Add iOS integration:
   - load wasm from app bundle
   - call exported functions from Swift/Objective-C
   - return typed results to caller
7. Create cross-platform golden tests using the same fixtures.
8. Benchmark basic performance:
   - first call after engine init
   - repeated calls in a loop
9. Measure artifact size impact.
10. Write a short findings report.

Constraints:

- Prioritize simplicity over completeness.
- Do not build a production-ready general-purpose cross-platform framework.
- Do not add unnecessary abstractions.
- Keep total code size low.
- Prefer explicitness and debuggability over cleverness.
- If runtime/library choice is uncertain, pick the smallest viable option and document tradeoffs.

Output requirements:
Produce:

1. Working code for the Rust wasm core.
2. Minimal Android and iOS host integrations.
3. Shared fixtures and tests.
4. A concise docs/REPORT.md covering:
   - what was built
   - what module was chosen
   - how the wasm boundary works
   - measured size/perf results
   - biggest pain points
   - whether this approach is worth expanding

Definition of done:

- The same sample function runs correctly on Android and iOS via wasm.
- Tests pass for the same fixtures on both platforms.
- There is a reproducible build path.
- REPORT.md includes concrete numbers and a recommendation:
  - proceed
  - proceed only for selected logic classes
  - do not proceed

Engineering style:

- Small commits / small diffs
- Clear README instructions
- No hidden magic
- Favor plain scripts over heavy tooling when possible
- Document assumptions explicitly

If blocked:

- Narrow the target module further.
- Replace complex interop with a string/JSON or byte-buffer boundary temporarily.
- Prefer getting one function working end-to-end before broadening the API.

Start by:

1. choosing the candidate module,
2. proposing the FFI/API shape,
3. sketching the repo structure,
4. implementing the smallest end-to-end exported function possible.
