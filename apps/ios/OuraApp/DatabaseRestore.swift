import Foundation
import SQLite3

/// Restores a validated ring store using SQLite's transactional backup mechanism.
/// The caller stages the file and holds WorkGate for the entire operation. Do not
/// remove the destination or its WAL: SQLite owns commit/rollback and sidecars.
enum DatabaseRestore {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func restore(candidate: URL, destination: URL) throws {
        guard candidate.resolvingSymlinksInPath().standardizedFileURL != destination.resolvingSymlinksInPath().standardizedFileURL else {
            throw Failure(message: "Choose a different backup file.")
        }
        let source = try open(candidate, flags: SQLITE_OPEN_READONLY)
        defer { sqlite3_close(source) }
        // Hold the same source snapshot through integrity/schema validation and
        // backup. Committed candidate WAL pages are included by SQLite.
        try execute(source, "BEGIN")
        defer { sqlite3_exec(source, "ROLLBACK", nil, nil, nil) }
        try validate(source)

        let existed = FileManager.default.fileExists(atPath: destination.path)
        let target = try open(destination, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        var restored = false
        defer {
            sqlite3_close(target)
            if !existed && !restored {
                for suffix in ["", "-wal", "-shm", "-journal"] {
                    try? FileManager.default.removeItem(atPath: destination.path + suffix)
                }
            }
        }
        guard let backup = sqlite3_backup_init(target, "main", source, "main") else {
            throw failure(target, "Could not start restore")
        }
        let result = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finished == SQLITE_OK else {
            // An unfinished backup transaction is rolled back by backup_finish.
            throw failure(target, "Restore failed; previous data was preserved")
        }
        restored = true
    }

    private static func open(_ url: URL, flags: Int32) throws -> OpaquePointer {
        var connection: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &connection, flags | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let connection else {
            let error = failure(connection, "Could not open database")
            if let connection { sqlite3_close(connection) }
            throw error
        }
        sqlite3_busy_timeout(connection, 1_500)
        return connection
    }

    private static func execute(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw failure(db, "Could not read backup")
        }
    }

    private static func validate(_ db: OpaquePointer) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &statement, nil) == SQLITE_OK,
              let integrity = statement else { throw failure(db, "Invalid backup") }
        defer { sqlite3_finalize(integrity) }
        guard sqlite3_step(integrity) == SQLITE_ROW,
              let result = sqlite3_column_text(integrity, 0), String(cString: result) == "ok",
              sqlite3_step(integrity) == SQLITE_DONE else {
            throw Failure(message: "The backup failed its integrity check. Your data was preserved.")
        }

        // The ring store defined in vendor/oura-store/src/storage.rs. A healthy
        // unrelated SQLite database must not replace a working health store.
        let tables: [String: Set<String>] = [
            "device": ["serial", "hardware_id", "firmware", "api_version", "mac", "updated_unix"],
            "sync_state": ["serial", "next_cursor", "last_sync_unix"],
            "events": ["id", "serial", "tag", "name", "ring_timestamp", "body", "decoded_json", "captured_unix"],
            "readings": ["id", "serial", "kind", "value", "unit", "captured_unix"]
        ]
        // Native ring backups contain data and indexes, no executable schema.
        statement = nil
        guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type IN ('trigger', 'view')", -1, &statement, nil) == SQLITE_OK,
              let executable = statement else { throw failure(db, "Invalid backup schema") }
        defer { sqlite3_finalize(executable) }
        guard sqlite3_step(executable) == SQLITE_DONE else {
            throw Failure(message: "Backups containing views or triggers are not supported.")
        }
        for (table, required) in tables {
            statement = nil
            guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK,
                  let columns = statement else { throw failure(db, "Invalid backup schema") }
            defer { sqlite3_finalize(columns) }
            var found: Set<String> = []
            var code = sqlite3_step(columns)
            while code == SQLITE_ROW {
                if let name = sqlite3_column_text(columns, 1) { found.insert(String(cString: name)) }
                code = sqlite3_step(columns)
            }
            guard code == SQLITE_DONE, required.isSubset(of: found) else {
                throw Failure(message: "This is not a compatible ring backup. Your data was preserved.")
            }
        }
    }

    private static func failure(_ db: OpaquePointer?, _ operation: String) -> Failure {
        let detail = db.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite could not open the file"
        return Failure(message: "\(operation): \(detail)")
    }
}
