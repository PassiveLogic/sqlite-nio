import Logging
import NIOCore
import SQLiteNIO
import Testing

private struct FutureOnlyDatabase: SQLiteDatabase {
    let connection: SQLiteConnection

    var logger: Logger { self.connection.logger }
    var eventLoop: any EventLoop { self.connection.eventLoop }

    func query(
        _ query: String,
        _ binds: [SQLiteData],
        logger: Logger,
        _ onRow: @escaping @Sendable (SQLiteRow) -> Void
    ) -> EventLoopFuture<Void> {
        self.connection.query(query, binds, logger: logger, onRow)
    }

    func withConnection<T>(
        _ closure: @escaping @Sendable (SQLiteConnection) -> EventLoopFuture<T>
    ) -> EventLoopFuture<T> {
        self.connection.withConnection(closure)
    }
}

@Test
func futureOnlyDatabaseRetainsAsyncDefaults() async throws {
    try await withOpenedConnection { connection in
        let database: any SQLiteDatabase = FutureOnlyDatabase(connection: connection)
        let rows = try await database.query("SELECT 42 AS value")
        #expect(rows.first?.column("value")?.integer == 42)

        let value: SQLiteInt64? = try await database.withConnection { connection in
            try await connection.query("SELECT 43 AS value").first?.column("value")?.integer
        }
        #expect(value == 43)
    }
}
