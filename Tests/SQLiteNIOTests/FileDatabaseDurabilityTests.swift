import XCTest
import SQLiteNIO
import Foundation

// MARK: - Helpers

/// Build a unique temporary database path that does not yet exist on disk.
private func makeTemporaryDatabasePath() -> String {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("sqlite-nio-opfs-test-\(UUID().uuidString).sqlite3")
        .path
}

/// Remove a database file and any rollback-journal / WAL sidecar files it left behind.
private func removeDatabaseFiles(at path: String) {
    let fm = FileManager.default
    for suffix in ["", "-journal", "-wal", "-shm"] {
        try? fm.removeItem(atPath: path + suffix)
    }
}

/// Open a file-backed connection at `path`, run `closure`, then close it. Because the
/// connection is fully closed afterwards, the same `path` can be reopened to assert that
/// data written by an earlier call survived — the on-disk analogue of a browser reload.
@discardableResult
private func withReopenableFileDatabase<T>(
    at path: String,
    _ closure: @escaping @Sendable (SQLiteConnection) async throws -> T
) async throws -> T {
    let connection = try await SQLiteConnection.open(storage: .file(path: path))
    do {
        let result = try await closure(connection)
        try await connection.close()
        return result
    } catch {
        try? await connection.close()
        throw error
    }
}

/// Run a statement for its side effects only, discarding any rows.
private func exec(_ conn: SQLiteConnection, _ sql: String, _ binds: [SQLiteData] = []) async throws {
    _ = try await conn.query(sql, binds)
}

/// Read the integer in the named column of the first row.
private func scalarInt(_ rows: [SQLiteRow], column: String) -> SQLiteInt64? {
    rows.first?.column(column)?.integer
}

// MARK: - .file(path:) durability

/// Native exercises of the durability guarantees that the browser relies on. They use a real
/// temporary file and the reopen pattern (close, then open the same path) to stand in for a
/// page reload.
final class FileDatabaseDurabilityTests: XCTestCase {
    func testDataRoundTripsAcrossReopen() async throws {
        let path = makeTemporaryDatabasePath()
        removeDatabaseFiles(at: path)
        defer { removeDatabaseFiles(at: path) }

        try await withReopenableFileDatabase(at: path) { conn in
            try await exec(conn, "CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")
            try await exec(conn, "INSERT INTO t (name) VALUES (?)", [.text("alice")])
            try await exec(conn, "INSERT INTO t (name) VALUES (?)", [.text("bob")])
        }

        // Reopen the same path: the rows must still be there.
        try await withReopenableFileDatabase(at: path) { conn in
            let rows = try await conn.query("SELECT COUNT(*) AS c FROM t")
            await XCTAssertEqualAsync(scalarInt(rows, column: "c"), 2)

            let names = try await conn.query("SELECT name FROM t ORDER BY id")
            XCTAssertEqual(names.compactMap { $0.column("name")?.string }, ["alice", "bob"])
        }
    }

    func testMigrationIsIdempotentAcrossReopen() async throws {
        let path = makeTemporaryDatabasePath()
        removeDatabaseFiles(at: path)
        defer { removeDatabaseFiles(at: path) }

        // Running "IF NOT EXISTS" migrations on every open must be safe.
        for _ in 0..<3 {
            try await withReopenableFileDatabase(at: path) { conn in
                try await exec(conn, "CREATE TABLE IF NOT EXISTS t (id INTEGER PRIMARY KEY, v INTEGER NOT NULL)")
                try await exec(conn, "INSERT INTO t (v) VALUES (1)")
            }
        }

        try await withReopenableFileDatabase(at: path) { conn in
            let rows = try await conn.query("SELECT COUNT(*) AS c FROM t")
            await XCTAssertEqualAsync(scalarInt(rows, column: "c"), 3)
        }
    }

    func testMemoryDoesNotPersistBetweenConnections() async throws {
        // A fresh in-memory database is empty even though a previous one created a table.
        let first = try await SQLiteConnection.open(storage: .memory)
        try await exec(first, "CREATE TABLE t (id INTEGER PRIMARY KEY)")
        try await exec(first, "INSERT INTO t DEFAULT VALUES")
        try await first.close()

        let second = try await SQLiteConnection.open(storage: .memory)
        await XCTAssertThrowsErrorAsync(try await second.query("SELECT COUNT(*) FROM t")) { error in
            // The table does not exist in the second, independent in-memory database.
            XCTAssertTrue(error is SQLiteError)
        }
        try await second.close()
    }

    func testDistinctPathsAreIsolated() async throws {
        let pathA = makeTemporaryDatabasePath()
        let pathB = makeTemporaryDatabasePath()
        removeDatabaseFiles(at: pathA)
        removeDatabaseFiles(at: pathB)
        defer { removeDatabaseFiles(at: pathA); removeDatabaseFiles(at: pathB) }

        try await withReopenableFileDatabase(at: pathA) { conn in
            try await exec(conn, "CREATE TABLE t (id INTEGER PRIMARY KEY)")
            try await exec(conn, "INSERT INTO t DEFAULT VALUES")
            try await exec(conn, "INSERT INTO t DEFAULT VALUES")
        }

        // A different path is a different database: the table should not exist there.
        try await withReopenableFileDatabase(at: pathB) { conn in
            await XCTAssertThrowsErrorAsync(try await conn.query("SELECT COUNT(*) FROM t"))
        }

        // The original path still has its two rows.
        try await withReopenableFileDatabase(at: pathA) { conn in
            let rows = try await conn.query("SELECT COUNT(*) AS c FROM t")
            await XCTAssertEqualAsync(scalarInt(rows, column: "c"), 2)
        }
    }

    func testDeletedFileReopensEmpty() async throws {
        let path = makeTemporaryDatabasePath()
        removeDatabaseFiles(at: path)
        defer { removeDatabaseFiles(at: path) }

        try await withReopenableFileDatabase(at: path) { conn in
            try await exec(conn, "CREATE TABLE t (id INTEGER PRIMARY KEY)")
            try await exec(conn, "INSERT INTO t DEFAULT VALUES")
        }

        // Simulate wiping storage (the POC's reset button does the OPFS equivalent).
        removeDatabaseFiles(at: path)

        try await withReopenableFileDatabase(at: path) { conn in
            // A brand new, empty database: the old table is gone.
            await XCTAssertThrowsErrorAsync(try await conn.query("SELECT COUNT(*) FROM t"))
        }
    }

    func testFailedTransactionRollbackLeavesFileUnchanged() async throws {
        let path = makeTemporaryDatabasePath()
        removeDatabaseFiles(at: path)
        defer { removeDatabaseFiles(at: path) }

        try await withReopenableFileDatabase(at: path) { conn in
            try await exec(conn, "CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER NOT NULL)")
            try await exec(conn, "INSERT INTO t (v) VALUES (1)")
        }

        // Begin a transaction, write, then roll it back: nothing should persist.
        try await withReopenableFileDatabase(at: path) { conn in
            try await exec(conn, "BEGIN")
            try await exec(conn, "INSERT INTO t (v) VALUES (2)")
            try await exec(conn, "INSERT INTO t (v) VALUES (3)")
            try await exec(conn, "ROLLBACK")
        }

        try await withReopenableFileDatabase(at: path) { conn in
            let rows = try await conn.query("SELECT COUNT(*) AS c FROM t")
            await XCTAssertEqualAsync(scalarInt(rows, column: "c"), 1)
        }
    }

    func testUniqueConstraintViolationMapsToSQLiteError() async throws {
        let path = makeTemporaryDatabasePath()
        removeDatabaseFiles(at: path)
        defer { removeDatabaseFiles(at: path) }

        try await withReopenableFileDatabase(at: path) { conn in
            try await exec(conn, "CREATE TABLE u (id INTEGER PRIMARY KEY, name TEXT UNIQUE)")
            try await exec(conn, "INSERT INTO u (name) VALUES (?)", [.text("dup")])

            await XCTAssertThrowsErrorAsync(
                try await conn.query("INSERT INTO u (name) VALUES (?)", [.text("dup")])
            ) { error in
                guard let sqliteError = error as? SQLiteError else {
                    return XCTFail("Expected a SQLiteError, got \(error)")
                }
                switch sqliteError.reason {
                case .constraint, .constraintUniqueFailed, .constraintPrimaryKeyFailed:
                    break // expected
                default:
                    XCTFail("Expected a constraint-violation reason, got \(sqliteError.reason)")
                }
            }
        }
    }
}
