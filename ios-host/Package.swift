// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WasmMobile",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "WasmMobile",
            targets: ["WasmMobile"]
        ),
    ],
    targets: [
        .target(
            name: "WasmHostBridge",
            path: "Sources/WasmHostBridge",
            sources: [
                "vendor/host-bridge/wasm_host_runtime.c",
                "vendor/wasm3/m3_bind.c",
                "vendor/wasm3/m3_code.c",
                "vendor/wasm3/m3_compile.c",
                "vendor/wasm3/m3_core.c",
                "vendor/wasm3/m3_env.c",
                "vendor/wasm3/m3_exec.c",
                "vendor/wasm3/m3_function.c",
                "vendor/wasm3/m3_info.c",
                "vendor/wasm3/m3_module.c",
                "vendor/wasm3/m3_parse.c",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("vendor/host-bridge"),
                .headerSearchPath("vendor/wasm3"),
            ]
        ),
        .target(
            name: "WasmMobile",
            dependencies: ["WasmHostBridge"],
            path: "Sources/WasmMobile",
            resources: [
                .copy("Resources/shared-core.wasm"),
            ]
        ),
        .testTarget(
            name: "WasmMobileTests",
            dependencies: ["WasmMobile"],
            path: "Tests/WasmMobileTests"
        ),
    ]
)
