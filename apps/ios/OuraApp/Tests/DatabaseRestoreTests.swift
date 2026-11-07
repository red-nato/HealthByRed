import XCTest
import SQLite3
@testable import OuraApp

final class DatabaseRestoreTests: XCTestCase {
    private let schema = """
    CREATE TABLE device(serial TEXT PRIMARY KEY, hardware_id TEXT, firmware TEXT, api_version TEXT, mac TEXT, updated_unix INTEGER NOT NULL);
    CREATE TABLE sync_state(serial TEXT PRIMARY KEY, next_cursor INTEGER NOT NULL, last_sync_unix INTEGER NOT NULL);
    CREATE TABLE events(id INTEGER PRIMARY KEY, serial TEXT, tag INTEGER, name TEXT, ring_timestamp INTEGER, body BLOB, decoded_json TEXT, captured_unix INTEGER);
    CREATE TABLE readings(id INTEGER PRIMARY KEY, serial TEXT, kind TEXT, value REAL, unit TEXT, captured_unix INTEGER);
    """

    private func database(_ url: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else { throw NSError(domain: "SQLiteTest", code: 1) }
        return db
    }

    private func execute(_ db: OpaquePointer, _ sql: String) throws {
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, String(cString: sqlite3_errmsg(db)))
    }

    private func serial(_ db: OpaquePointer) -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT serial FROM device", -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: value)
    }

    func testInvalidSchemaPreservesExistingStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("current.db"), candidate = dir.appendingPathComponent("unrelated.db")
        let target = try database(destination), invalid = try database(candidate)
        defer { sqlite3_close(target); sqlite3_close(invalid) }
        try execute(target, schema + "INSERT INTO device(serial, updated_unix) VALUES ('original', 1);")
        try execute(invalid, "CREATE TABLE unrelated(value TEXT);")
        XCTAssertThrowsError(try DatabaseRestore.restore(candidate: candidate, destination: destination))
        XCTAssertEqual(serial(target), "original")
        let newDestination = dir.appendingPathComponent("must-not-exist.db")
        XCTAssertThrowsError(try DatabaseRestore.restore(candidate: candidate, destination: newDestination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newDestination.path))
    }

    func testRestoreIncludesCommittedWALAndReplacesExistingWALStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("current.db"), candidate = dir.appendingPathComponent("backup.db")
        let target = try database(destination), source = try database(candidate)
        defer { sqlite3_close(target); sqlite3_close(source) }
        try execute(target, "PRAGMA journal_mode=WAL;" + schema + "INSERT INTO device(serial, updated_unix) VALUES ('original', 1);")
        try execute(source, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;" + schema + "INSERT INTO device(serial, updated_unix) VALUES ('from-wal', 2);")
        XCTAssertTrue(FileManager.default.fileExists(atPath: candidate.path + "-wal"))
        try DatabaseRestore.restore(candidate: candidate, destination: destination)
        XCTAssertEqual(serial(target), "from-wal")
    }

    func testMissingCandidateDoesNotCreateFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("missing.db"), target = dir.appendingPathComponent("new.db")
        XCTAssertThrowsError(try DatabaseRestore.restore(candidate: source, destination: target))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testLockedDestinationPreservesExistingStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let destination = dir.appendingPathComponent("current.db"), candidate = dir.appendingPathComponent("backup.db")
        let target = try database(destination), source = try database(candidate)
        defer { sqlite3_close(target); sqlite3_close(source) }
        try execute(target, schema + "INSERT INTO device(serial, updated_unix) VALUES ('original', 1); BEGIN IMMEDIATE;")
        defer { sqlite3_exec(target, "ROLLBACK", nil, nil, nil) }
        try execute(source, schema + "INSERT INTO device(serial, updated_unix) VALUES ('replacement', 2);")
        XCTAssertThrowsError(try DatabaseRestore.restore(candidate: candidate, destination: destination))
        XCTAssertEqual(serial(target), "original")
    }
}
