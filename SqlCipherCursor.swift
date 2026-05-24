// SqlCipherCursor.swift — iOS counterpart of the Kotlin SqlCipherCursor.
// vc 342 / Phase 1.G.

import Foundation

public class SqlCipherCursor {

    private var handle: OpaquePointer?

    init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        close()
    }

    public func close() {
        if let h = handle {
            sqlite3_finalize(h)
            handle = nil
        }
    }

    public func moveToFirst() throws -> Bool {
        return try moveToNext()
    }

    public func moveToNext() throws -> Bool {
        guard let h = handle else { throw SqlCipherError(code: 21, message: "cursor is closed") }
        let rc = sqlite3_step(h)
        switch rc {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default:
            throw SqlCipherError(code: rc, message: "step error")
        }
    }

    public var columnCount: Int32 {
        guard let h = handle else { return 0 }
        return sqlite3_column_count(h)
    }

    public func columnNames() -> [String] {
        guard let h = handle else { return [] }
        var out: [String] = []
        let n = sqlite3_column_count(h)
        for i in 0..<n {
            if let cName = sqlite3_column_name(h, i) {
                out.append(String(cString: cName))
            } else {
                out.append("")
            }
        }
        return out
    }

    public func getType(_ col: Int32) -> Int32 {
        guard let h = handle else { return 5 /* SQLITE_NULL */ }
        return sqlite3_column_type(h, col)
    }

    public func isNull(_ col: Int32) -> Bool {
        return getType(col) == 5 /* SQLITE_NULL */
    }

    public func getLong(_ col: Int32) -> Int64 {
        guard let h = handle else { return 0 }
        return sqlite3_column_int64(h, col)
    }

    public func getInt(_ col: Int32) -> Int32 {
        return Int32(getLong(col))
    }

    public func getDouble(_ col: Int32) -> Double {
        guard let h = handle else { return 0 }
        return sqlite3_column_double(h, col)
    }

    public func getString(_ col: Int32) -> String? {
        guard let h = handle else { return nil }
        guard let cStr = sqlite3_column_text(h, col) else { return nil }
        return String(cString: cStr)
    }

    public func getBlob(_ col: Int32) -> Data? {
        guard let h = handle else { return nil }
        guard let blob = sqlite3_column_blob(h, col) else { return nil }
        let size = sqlite3_column_bytes(h, col)
        return Data(bytes: blob, count: Int(size))
    }
}
