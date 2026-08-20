import SQLiteNIO
import XCTest

final class SQLiteConnectionExecuteScriptTests: XCTestCase {
    func testExecuteScriptExecutesEveryStatement() async throws {
        try await withOpenedConnection { connection in
            let _: Void = try await connection.executeScript(
                """
                CREATE TABLE items(value INTEGER);
                INSERT INTO items VALUES (1);
                INSERT INTO items VALUES (2);
                """
            )

            let rows = try await connection.query("SELECT value FROM items ORDER BY value")

            XCTAssertEqual(rows.compactMap { $0.column("value")?.integer }, [1, 2])
        }
    }

    func testExecuteScriptStopsAtFirstErrorAndLeavesTransactionOpen() async throws {
        try await withOpenedConnection { connection in
            _ = try await connection.query("CREATE TABLE items(value INTEGER)")

            await XCTAssertThrowsErrorAsync(
                try await connection.executeScript(
                    """
                    BEGIN;
                    INSERT INTO items VALUES (1);
                    INSERT INTO missing_table VALUES (2);
                    COMMIT;
                    """
                )
            )

            let rowsBeforeRollback = try await connection.query("SELECT value FROM items")
            XCTAssertEqual(rowsBeforeRollback.first?.column("value")?.integer, 1)

            _ = try await connection.query("ROLLBACK")

            let rowsAfterRollback = try await connection.query("SELECT value FROM items")
            XCTAssertTrue(rowsAfterRollback.isEmpty)
        }
    }
}
