cmake_minimum_required(VERSION 3.22.1)
project(wasm_mobile LANGUAGES C CXX)

set(WASM3_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/wasm3/source)
set(HOST_BRIDGE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../shared-core/host-bridge)

add_library(
    wasm_mobile
    SHARED
    feature_flag_jni.cpp
    ${HOST_BRIDGE_DIR}/wasm_host_runtime.c
    ${WASM3_DIR}/m3_bind.c
    ${WASM3_DIR}/m3_code.c
    ${WASM3_DIR}/m3_compile.c
    ${WASM3_DIR}/m3_core.c
    ${WASM3_DIR}/m3_env.c
    ${WASM3_DIR}/m3_exec.c
    ${WASM3_DIR}/m3_function.c
    ${WASM3_DIR}/m3_info.c
    ${WASM3_DIR}/m3_module.c
    ${WASM3_DIR}/m3_parse.c
)

target_include_directories(
    wasm_mobile
    PRIVATE
    ${HOST_BRIDGE_DIR}
    ${WASM3_DIR}
)

target_compile_features(wasm_mobile PRIVATE c_std_99 cxx_std_17)
target_compile_options(wasm_mobile PRIVATE -Wall -Wextra)

find_library(log-lib log)
target_link_libraries(wasm_mobile PRIVATE ${log-lib})

