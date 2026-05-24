// SqlCipherStatement.swift — iOS counterpart of the Kotlin
// SqlCipherStatement class. vc 342 / Phase 1.G.

import Foundation

public class SqlCipherStatement {

    fileprivate var handle: OpaquePointer?
    private weak var owner: SqlCipherDatabase?

    init(handle: OpaquePointer, owner: SqlCipherDatabase) {
        self.handle = handle
        self.owner = owner
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

    public func execute() throws {
        guard let h = handle else { throw SqlCipherError(code: 21, message: "statement is closed") }
        let rc = sqlite3_step(h)
        if rc != SQLITE_DONE {
            throw SqlCipherError(code: rc, message: "expected DONE, got \(rc)")
        }
    }

    public func executeInsert() throws -> Int64 {
        try execute()
        guard let owner = owner else { return -1 }
        return owner.changes() == 0 ? -1 : owner.lastInsertRowId()
    }

    public func executeUpdateDelete() throws -> Int32 {
        try execute()
        return owner?.changes() ?? 0
    }

    public func reset() {
        if let h = handle {
            sqlite3_reset(h)
        }
    }

    public func clearBindings() {
        if let h = handle {
            sqlite3_clear_bindings(h)
        }
    }

    public func bindAt(_ idx: Int32, _ value: Any?) throws {
        guard let h = handle else { throw SqlCipherError(code: 21, message: "statement is closed") }
        try SqlCipherDatabase.bindOne(h, idx, value)
    }

    public func bindArgs(_ args: [Any?]) throws {
        for (i, arg) in args.enumerated() {
            try bindAt(Int32(i + 1), arg)
        }
    }
}
