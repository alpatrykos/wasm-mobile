import Foundation

public final class WasmMobileBundleToken: NSObject {}

enum WasmMobileResources {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return Bundle(for: WasmMobileBundleToken.self)
        #endif
    }
}
