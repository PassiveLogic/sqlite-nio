/// Supported SQLite column data types when defining schemas.
@available(*, deprecated, message: "This type is unused.")
public enum SQLiteDataType {
    /// `INTEGER`.
    case integer

    /// `REAL`.
    case real

    /// `TEXT`.
    case text

    /// `BLOB`.
    case blob

    /// `NULL`.
    case null

    // `any Encodable` requires runtime existentials that Embedded Swift does not provide. The
    // method is deprecated and unused, so it is simply elided there.
    #if !hasFeature(Embedded)
    public func serialize(_ binds: inout [any Encodable]) -> String {
        switch self {
        case .integer: return "INTEGER"
        case .real: return "REAL"
        case .text: return "TEXT"
        case .blob: return "BLOB"
        case .null: return "NULL"
        }
    }
    #endif  // !hasFeature(Embedded)
}
