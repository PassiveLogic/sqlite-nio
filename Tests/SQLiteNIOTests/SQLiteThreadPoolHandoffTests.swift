import NIOCore
@testable import SQLiteNIO
import Testing

private enum HandoffError: Error {
    case expected
}

@Test
func threadPoolResultHandoffPreservesOptionalValues() async throws {
    let value: Int? = try await NIOThreadPool.singleton.runSQLite { nil }
    #expect(value == nil)
}

@Test
func threadPoolResultHandoffPreservesErrors() async {
    await #expect(throws: HandoffError.expected) {
        try await NIOThreadPool.singleton.runSQLite { () throws -> Int in
            throw HandoffError.expected
        }
    }
}

@Test
func threadPoolResultHandoffRejectsInactivePool() async throws {
    let pool = NIOThreadPool(numberOfThreads: 1)
    try await pool.shutdownGracefully()
    await #expect(throws: (any Error).self) {
        try await pool.runSQLite { 42 }
    }
}

@Test(arguments: [false, true])
func concurrentConnectionsPublishRows(useFuture: Bool) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<4 {
            group.addTask {
                for _ in 0..<10 {
                    try await withOpenedConnection { connection in
                        #expect(connection.isClosed == false)
                        let sql = """
                            WITH RECURSIVE values_to_read(value) AS (
                                VALUES(1)
                                UNION ALL SELECT value + 1 FROM values_to_read WHERE value < 64
                            )
                            SELECT value FROM values_to_read ORDER BY value
                            """
                        let rows: [SQLiteRow]
                        if useFuture {
                            let result: EventLoopFuture<[SQLiteRow]> = connection.query(sql)
                            rows = try await result.get()
                        } else {
                            rows = try await connection.query(sql)
                        }
                        #expect(rows.compactMap { $0.column("value")?.integer } == (1...64).map { SQLiteInt64($0) })
                    }
                }
            }
        }
        try await group.waitForAll()
    }
}

@Test
func threadPoolResultHandoffPreservesCancellation() async {
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await NIOThreadPool.singleton.runSQLite {
            Issue.record("Cancelled work must not execute")
            return 42
        }
    }
    await #expect(throws: CancellationError.self) {
        try await task.value
    }
}
