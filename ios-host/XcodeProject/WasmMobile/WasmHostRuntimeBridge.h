#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WasmHostRuntimeBridge : NSObject

+ (nullable NSNumber *)createEngineWithWasmData:(NSData *)wasmData
                                   errorMessage:(NSString * _Nullable * _Nullable)errorMessage;
+ (void)destroyEngineWithHandle:(NSNumber *)handle;
+ (nullable NSData *)evaluateWithHandle:(NSNumber *)handle
                            requestData:(NSData *)requestData
                           errorMessage:(NSString * _Nullable * _Nullable)errorMessage;

@end

NS_ASSUME_NONNULL_END
