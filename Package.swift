// swift-tools-version:5.10
import PackageDescription

/// This list matches the [supported platforms on the Swift 5.10 release of SPM](https://github.com/swiftlang/swift-package-manager/blob/release/5.10/Sources/PackageDescription/SupportedPlatforms.swift#L34-L71)
/// Don't add new platforms here unless raising the swift-tools-version of this manifest.
let allPlatforms: [Platform] = [.macOS, .macCatalyst, .iOS, .tvOS, .watchOS, .visionOS, .driverKit, .linux, .windows, .android, .wasi, .openbsd]
let nonWASIPlatforms: [Platform] = allPlatforms.filter { $0 != .wasi }
let wasiPlatform: [Platform] = [.wasi]

let package = Package(
    name: "sqlite-nio",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .watchOS(.v6),
        .tvOS(.v13),
    ],
    products: [
        .library(name: "SQLiteNIO", targets: ["SQLiteNIO"]),
    ],
    dependencies: [
        // Local clones for the embedded-wasm port (see /Users/scottm/git/c34/EMBEDDED_WASM_NOTES.md)
        .package(path: "../swift-nio"),
        .package(path: "../swift-log"),
    ],
    targets: [
        .plugin(
            name: "VendorSQLite",
            capability: .command(
                intent: .custom(verb: "vendor-sqlite", description: "Vendor SQLite"),
                permissions: [
                    .allowNetworkConnections(scope: .all(ports: [443]), reason: "Retrieve the latest build of SQLite"),
                    .writeToPackageDirectory(reason: "Update the vendored SQLite files"),
                ]
            ),
            exclude: ["001-warnings-and-data-race.patch"]
        ),
        .target(
            name: "CSQLite",
            cSettings: sqliteCSettings
        ),
        .target(
            name: "SQLiteNIO",
            dependencies: [
                .target(name: "CSQLite"),
                .product(name: "Logging", package: "swift-log"),
                // The SwiftNIO stack is elided on WASI (normal + Embedded); .when(platforms:) is
                // target-evaluated, so these aren't built when cross-compiling to wasm32-unknown-wasip1.
                // The WASI path is a NIO-free, Swift-Concurrency driver over CSQLite, gated in source
                // with `#if os(WASI)`.
                .product(name: "NIOCore", package: "swift-nio", condition: .when(platforms: nonWASIPlatforms)),
                .product(name: "NIOPosix", package: "swift-nio", condition: .when(platforms: nonWASIPlatforms)),
                .product(name: "NIOFoundationCompat", package: "swift-nio", condition: .when(platforms: nonWASIPlatforms)),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SQLiteNIOTests",
            dependencies: [
                .target(name: "SQLiteNIO"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("ConciseMagicFile"),
    .enableUpcomingFeature("ForwardTrailingClosures"),
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableExperimentalFeature("StrictConcurrency=complete"),
] }

var sqliteCSettings: [CSetting] { [
    // Derived from sqlite3 version 3.43.0
    .define("SQLITE_DEFAULT_MEMSTATUS", to: "0"),
    .define("SQLITE_DISABLE_PAGECACHE_OVERFLOW_STATS"),
    .define("SQLITE_DQS", to: "0"),
    .define("SQLITE_ENABLE_API_ARMOR", .when(configuration: .debug)),
    .define("SQLITE_ENABLE_COLUMN_METADATA"),
    .define("SQLITE_ENABLE_DBSTAT_VTAB"),
    .define("SQLITE_ENABLE_FTS3"),
    .define("SQLITE_ENABLE_FTS3_PARENTHESIS"),
    .define("SQLITE_ENABLE_FTS3_TOKENIZER"),
    .define("SQLITE_ENABLE_FTS4"),
    .define("SQLITE_ENABLE_FTS5"),
    .define("SQLITE_ENABLE_NULL_TRIM"),
    .define("SQLITE_ENABLE_RTREE"),
    .define("SQLITE_ENABLE_SESSION"),
    .define("SQLITE_ENABLE_STMTVTAB"),
    .define("SQLITE_ENABLE_UNKNOWN_SQL_FUNCTION"),
    .define("SQLITE_ENABLE_UNLOCK_NOTIFY"),
    .define("SQLITE_MAX_VARIABLE_NUMBER", to: "250000"),
    .define("SQLITE_LIKE_DOESNT_MATCH_BLOBS"),
    .define("SQLITE_OMIT_COMPLETE"),
    .define("SQLITE_OMIT_DEPRECATED"),
    .define("SQLITE_OMIT_DESERIALIZE"),
    .define("SQLITE_OMIT_GET_TABLE"),
    .define("SQLITE_OMIT_LOAD_EXTENSION"),
    .define("SQLITE_OMIT_PROGRESS_CALLBACK"),
    .define("SQLITE_OMIT_SHARED_CACHE"),
    .define("SQLITE_OMIT_TCL_VARIABLE"),
    .define("SQLITE_OMIT_TRACE"),
    .define("SQLITE_SECURE_DELETE"),
    .define("SQLITE_THREADSAFE", to: "1", .when(platforms: nonWASIPlatforms)),
    // For now, we use the single threaded sqlite variation for the WASI platform
    // since single-threaded operation is the least common denominator capability
    // for Wasm executables and it is considered unreliable to use canImport(wasi_pthread)
    // in a manifest file to distinguish between the two capabilities.
    .define("SQLITE_THREADSAFE", to: "0", .when(platforms: wasiPlatform)),
    .define("SQLITE_UNTESTABLE"),
    .define("SQLITE_USE_URI"),
] }
