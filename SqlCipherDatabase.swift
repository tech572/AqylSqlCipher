// SqlCipherDatabase.swift — iOS counterpart of the Kotlin SqlCipherDatabase.
// vc 342 / Phase 1.G.
//
// Wraps the bundled SQLCipher 4.15.0 amalgamation (compiled into the
// pod via xcconfig flags in SqlCipher.podspec) with a Swift API
// mirroring the Kotlin SqlCipherDatabase shape. Both Kotlin and Swift
// callers see the same surface (`openOrCreate`, `execSQL`,
// `compileStatement`, `rawQuery`, `transaction`, etc.) so SDK-internal
// callers don't fork per-platform.
//
// Threading: opens with SQLITE_OPEN_FULLMUTEX so the connection is
// safe to share across threads. SQLite serializes writes internally.
//
// Encryption: passphrase is OPTIONAL — empty/nil string opens as
// plain SQLite (codec inactive). Same dual-mode contract as Android.

import Foundation
import os.log

private let log = OSLog(subsystem: "io.aqyl.sqlcipher", category: "SqlCipher")

public class SqlCipherDatabase {

    private var handle: OpaquePointer?
    public let path: String
    public let isEncrypted: Bool

    private init(handle: OpaquePointer, path: String, isEncrypted: Bool) {
        self.handle = handle
        self.path = path
        self.isEncrypted = isEncrypted
    }

    deinit {
        close()
    }

    public func close() {
        if let h = handle {
            sqlite3_close_v2(h)
            handle = nil
        }
    }

    public var isOpen: Bool { handle != nil }

    /// Run a single DDL/DML statement (no rows returned).
    /// Throws [SqlCipherError] on any sqlite3 error.
    public func execSQL(_ sql: String) throws {
        guard let h = handle else { throw SqlCipherError(code: 21 /* SQLITE_MISUSE */, message: "database is closed") }
        var errPtr: UnsafeMutablePointer<Int8>? = nil
        let rc = sqlite3_exec(h, sql, nil, nil, &errPtr)
        if rc != SQLITE_OK {
            let msg = errPtr.flatMap { String(cString: $0) } ?? String(cString: sqlite3_errmsg(h))
            sqlite3_free(errPtr)
            throw SqlCipherError(code: rc, message: msg)
        }
    }

    public func execSQL(_ sql: String, _ args: [Any?]) throws {
        let stmt = try compileStatement(sql)
        defer { stmt.close() }
        try stmt.bindArgs(args)
        try stmt.execute()
    }

    public func compileStatement(_ sql: String) throws -> SqlCipherStatement {
        guard let h = handle else { throw SqlCipherError(code: 21, message: "database is closed") }
        var stmtPtr: OpaquePointer? = nil
        let rc = sqlite3_prepare_v2(h, sql, -1, &stmtPtr, nil)
        guard rc == SQLITE_OK, let stmt = stmtPtr else {
            let msg = String(cString: sqlite3_errmsg(h))
            if let stmtPtr = stmtPtr { sqlite3_finalize(stmtPtr) }
            throw SqlCipherError(code: rc, message: msg)
        }
        return SqlCipherStatement(handle: stmt, owner: self)
    }

    public func rawQuery(_ sql: String, _ args: [Any?]?) throws -> SqlCipherCursor {
        guard let h = handle else { throw SqlCipherError(code: 21, message: "database is closed") }
        var stmtPtr: OpaquePointer? = nil
        let rc = sqlite3_prepare_v2(h, sql, -1, &stmtPtr, nil)
        guard rc == SQLITE_OK, let stmt = stmtPtr else {
            let msg = String(cString: sqlite3_errmsg(h))
            if let stmtPtr = stmtPtr { sqlite3_finalize(stmtPtr) }
            throw SqlCipherError(code: rc, message: msg)
        }
        if let args = args, !args.isEmpty {
            do {
                try Self.bindArgs(to: stmt, args: args)
            } catch {
                sqlite3_finalize(stmt)
                throw error
            }
        }
        return SqlCipherCursor(handle: stmt)
    }

    public func changes() -> Int32 {
        guard let h = handle else { return 0 }
        return sqlite3_changes(h)
    }

    public func lastInsertRowId() -> Int64 {
        guard let h = handle else { return 0 }
        return sqlite3_last_insert_rowid(h)
    }

    public func transaction<T>(_ block: (SqlCipherDatabase) throws -> T) throws -> T {
        try execSQL("BEGIN IMMEDIATE TRANSACTION")
        do {
            let result = try block(self)
            try execSQL("COMMIT TRANSACTION")
            return result
        } catch {
            try? execSQL("ROLLBACK TRANSACTION")
            throw error
        }
    }

    public func setPragma(_ name: String, _ value: String) throws {
        let cursor = try rawQuery("PRAGMA \(name) = \(value)", nil)
        defer { cursor.close() }
        _ = try? cursor.moveToFirst()
    }

    public func pragma(_ stmt: String) throws -> String? {
        let c = try rawQuery(stmt, nil)
        defer { c.close() }
        if try c.moveToFirst() {
            return c.getString(0)
        }
        return nil
    }

    // ── Public open APIs ────────────────────────────────────────────

    /// Open (or create) a database. Encrypted iff passphrase non-nil
    /// non-empty; plain otherwise.
    public static func openOrCreate(file: URL, passphrase: String?) throws -> SqlCipherDatabase {
        let parent = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        var handle: OpaquePointer? = nil
        let rc = sqlite3_open_v2(
            file.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard rc == SQLITE_OK, let h = handle else {
            if let h = handle { sqlite3_close(h) }
            throw SqlCipherError(code: rc, message: "sqlite3_open failed")
        }

        var encrypted = false
        if let pw = passphrase, !pw.isEmpty {
            encrypted = true
            // PRAGMA key — must be the FIRST statement on the connection
            // so the codec engages before any read.
            let escaped = pw.replacingOccurrences(of: "'", with: "''")
            let keyStmt = "PRAGMA key = '\(escaped)';"
            var errPtr: UnsafeMutablePointer<Int8>? = nil
            let kc = sqlite3_exec(h, keyStmt, nil, nil, &errPtr)
            if kc != SQLITE_OK {
                let msg = errPtr.flatMap { String(cString: $0) } ?? "PRAGMA key failed"
                sqlite3_free(errPtr)
                sqlite3_close(h)
                throw SqlCipherError(code: kc, message: msg)
            }
        }

        // Verify-open ping. Wrong key surfaces as SQLITE_NOTADB here.
        var errPtr: UnsafeMutablePointer<Int8>? = nil
        let vc = sqlite3_exec(h, "SELECT count(*) FROM sqlite_master;", nil, nil, &errPtr)
        if vc != SQLITE_OK {
            let msg = errPtr.flatMap { String(cString: $0) } ?? String(cString: sqlite3_errmsg(h))
            sqlite3_free(errPtr)
            sqlite3_close(h)
            throw SqlCipherError(code: vc, message: msg)
        }

        return SqlCipherDatabase(handle: h, path: file.path, isEncrypted: encrypted)
    }

    public static func openPlain(file: URL) throws -> SqlCipherDatabase {
        return try openOrCreate(file: file, passphrase: nil)
    }

    // ── Internal binding helpers ────────────────────────────────────

    static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func bindArgs(to stmt: OpaquePointer, args: [Any?]) throws {
        for (i, arg) in args.enumerated() {
            let pos = Int32(i + 1)
            try bindOne(stmt, pos, arg)
        }
    }

    static func bindOne(_ stmt: OpaquePointer, _ idx: Int32, _ value: Any?) throws {
        if value == nil {
            sqlite3_bind_null(stmt, idx)
            return
        }
        if let v = value as? Bool {
            sqlite3_bind_int64(stmt, idx, v ? 1 : 0)
        } else if let v = value as? Int {
            sqlite3_bind_int64(stmt, idx, Int64(v))
        } else if let v = value as? Int32 {
            sqlite3_bind_int64(stmt, idx, Int64(v))
        } else if let v = value as? Int64 {
            sqlite3_bind_int64(stmt, idx, v)
        } else if let v = value as? Double {
            sqlite3_bind_double(stmt, idx, v)
        } else if let v = value as? Float {
            sqlite3_bind_double(stmt, idx, Double(v))
        } else if let v = value as? String {
            sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
        } else if let v = value as? Data {
            v.withUnsafeBytes { bytes in
                sqlite3_bind_blob(stmt, idx, bytes.baseAddress, Int32(v.count), SQLITE_TRANSIENT)
            }
        } else if let v = value as? [UInt8] {
            v.withUnsafeBufferPointer { buf in
                sqlite3_bind_blob(stmt, idx, buf.baseAddress, Int32(v.count), SQLITE_TRANSIENT)
            }
        } else {
            // Fallback — toString.
            let s = String(describing: value!)
            sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
        }
    }
}
