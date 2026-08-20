import NIOCore
import VaporCSQLite

extension SQLiteConnection {
    /// Execute a multi-statement SQL script in one call, via `sqlite3_exec`.
    ///
    /// Opt-in escape hatch from the single-statement `query(_:_:)` path, for
    /// **static, trusted SQL only** (schema scripts, embedded migrations) — there
    /// is no parameter binding, so never build the script from runtime data.
    ///
    /// - Parameter script: `;`-separated SQL statements, split and executed in
    ///   order by SQLite's own parser. Any result rows are discarded. Execution
    ///   stops at the first error; earlier statements stay applied unless the
    ///   script itself uses a transaction.
    /// - Returns: A future that succeeds once every statement has run.
    public func executeScript(_ script: String) -> EventLoopFuture<Void> {
        self.threadPool.runIfActive(eventLoop: self.eventLoop) {
            guard let handle = self.handle.raw else {
                throw SQLiteError(reason: .misuse, message: "executeScript called on a closed connection")
            }
            self.logger.debug("executing SQL script (\(script.utf8.count) bytes)")
            var errorPointer: UnsafeMutablePointer<CChar>? = nil
            let status = sqlite_nio_sqlite3_exec(handle, script, nil, nil, &errorPointer)
            let message: String
            if let errorPointer {
                message = String(cString: errorPointer)
                sqlite_nio_sqlite3_free(errorPointer)
            }
            else {
                message = "Unknown"
            }
            guard status == SQLITE_OK else {
                throw SQLiteError(reason: .init(statusCode: status), message: message)
            }
        }
    }
}
