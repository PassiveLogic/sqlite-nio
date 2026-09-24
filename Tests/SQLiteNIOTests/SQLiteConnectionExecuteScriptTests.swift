import SQLiteNIO
import NIOCore
import Testing

@Suite("SQL script execution")
struct SQLiteConnectionExecuteScriptTests {
    @Test(arguments: [false, true])
    func executeScriptExecutesEveryStatement(useFuture: Bool) async throws {
        try await withOpenedConnection { connection in
            let script =
                """
                CREATE TABLE items(value INTEGER);
                INSERT INTO items VALUES (1);
                INSERT INTO items VALUES (2);
                """
            if useFuture {
                try await connection.executeScript(script).get()
            } else {
                try await connection.executeScript(script)
            }

            let rows = try await connection.query("SELECT value FROM items ORDER BY value")

            #expect(rows.compactMap { $0.column("value")?.integer } == [1, 2])
        }
    }

    @Test(arguments: [false, true])
    func executeScriptStopsAtFirstErrorAndLeavesTransactionOpen(useFuture: Bool) async throws {
        try await withOpenedConnection { connection in
            _ = try await connection.query("CREATE TABLE items(value INTEGER)")

            let script =
                """
                BEGIN;
                INSERT INTO items VALUES (1);
                INSERT INTO missing_table VALUES (2);
                COMMIT;
                """
            await #expect(throws: SQLiteError.self) {
                if useFuture {
                    try await connection.executeScript(script).get()
                } else {
                    try await connection.executeScript(script)
                }
            }

            let rowsBeforeRollback = try await connection.query("SELECT value FROM items")
            #expect(rowsBeforeRollback.first?.column("value")?.integer == 1)

            _ = try await connection.query("ROLLBACK")

            let rowsAfterRollback = try await connection.query("SELECT value FROM items")
            #expect(rowsAfterRollback.isEmpty)
        }
    }

    @Test(arguments: [false, true])
    func executeScriptRejectsClosedConnection(useFuture: Bool) async throws {
        let connection = try await SQLiteConnection.open(storage: .memory)
        try await connection.close()
        let error = await #expect(throws: SQLiteError.self) {
            if useFuture {
                try await connection.executeScript("SELECT 1;").get()
            } else {
                try await connection.executeScript("SELECT 1;")
            }
        }
        #expect(error?.reason == .misuse)
    }
}
