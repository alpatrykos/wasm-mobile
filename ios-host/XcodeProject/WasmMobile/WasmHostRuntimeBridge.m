#import "WasmHostRuntimeBridge.h"

#import <stdint.h>

#import "wasm_host_runtime.h"

@implementation WasmHostRuntimeBridge

+ (NSNumber *)createEngineWithWasmData:(NSData *)wasmData
                          errorMessage:(NSString * _Nullable * _Nullable)errorMessage {
    char *error = NULL;
    wm_engine_t *engine = wm_engine_create(wasmData.bytes, (uint32_t)wasmData.length, &error);
    [self populateError:error into:errorMessage];
    if (engine == NULL) {
        return nil;
    }
    return @( (uintptr_t)engine );
}

+ (void)destroyEngineWithHandle:(NSNumber *)handle {
    wm_engine_destroy((wm_engine_t *)(uintptr_t)handle.unsignedLongLongValue);
}

+ (NSData *)evaluateWithHandle:(NSNumber *)handle
                   requestData:(NSData *)requestData
                  errorMessage:(NSString * _Nullable * _Nullable)errorMessage {
    char *error = NULL;
    uint32_t responseLength = 0;
    uint8_t *response = wm_engine_evaluate(
        (wm_engine_t *)(uintptr_t)handle.unsignedLongLongValue,
        requestData.bytes,
        (uint32_t)requestData.length,
        &responseLength,
        &error
    );
    [self populateError:error into:errorMessage];
    if (response == NULL) {
        return nil;
    }

    NSData *data = [NSData dataWithBytes:response length:responseLength];
    wm_buffer_free(response);
    return data;
}

+ (void)populateError:(char *)error into:(NSString * _Nullable * _Nullable)errorMessage {
    if (error != NULL && errorMessage != NULL) {
        *errorMessage = [NSString stringWithUTF8String:error];
    }
    wm_error_free(error);
}

@end
