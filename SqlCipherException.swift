// SqlCipherException.swift — iOS counterpart of the Kotlin
// SqlCipherException class. vc 342 / Phase 1.G.

import Foundation

public struct SqlCipherError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String

    public var description: String {
        return "sqlcipher error code=\(code) :: \(message)"
    }
}
