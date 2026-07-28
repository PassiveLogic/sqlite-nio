// swift-tools-version:6.1
import class Foundation.ProcessInfo
import PackageDescription

/// `.when(platforms:)` can only include, never exclude, so excluding WASI means listing everything else.
/// This list matches the [supported platforms on the Swift 6.1 release of SPM](https://github.com/swiftlang/swift-package-manager/blob/release/6.1/Sources/PackageDescription/SupportedPlatforms.swift#L35-L71);
/// don't add new platforms here unless raising the swift-tools-version of this manifest.
let nonWASIPlatforms: [Platform] = [
    .macOS, .macCatalyst, .iOS, .tvOS, .watchOS, .visionOS, .driverKit, .linux, .windows, .android, .openbsd,
]

// ┌───────────────────────────────────────────────────────────────────────────────┐
// │ DOWNSTREAM-ONLY — `integration/khasm-embedded`. NOT FOR UPSTREAM.             │
// │ Must never be cherry-picked onto feat/wasi-nio-free or feat/embedded-support. │
// └───────────────────────────────────────────────────────────────────────────────┘
//
// Upstream (feat/wasi-nio-free) elides SwiftNIO for ALL of WASI, so the NIO-free
// backend is what every wasm consumer gets. khasm has TWO wasm flavors and only one
// of them can accept that:
//
//   - Embedded/Freestanding (KHASM_EMBEDDED=1): wants exactly the upstream behavior.
//   - Regular wasm (wasm32-unknown-wasip1, no Embedded): its storage stack
//     (QuantumStorageCore's QuantumMigrator, quantum-sqlite-driver) uses
//     `EventLoopConnectionPool<SQLiteConnectionSource>`, `NIOThreadPool`,
//     `database.eventLoop` and `EventLoopFuture` UNGATED. Dropping SwiftNIO on WASI
//     deletes all of that, and porting those two packages to the NIO-free surface is
//     an open work item (see quantum-sqlite-driver's own manifest note).
//
// So NIO is elided on WASI only for the Embedded flavor. Every other build — hosts,
// CI, and khasm's regular wasm — keeps the full SwiftNIO surface exactly as before,
// which makes `canImport(NIOCore)` true there and renders the upstream Track-A gates
// inert. On WASI the SwiftNIO products come from the PassiveLogic fork (below).
let allPlatforms: [Platform] = nonWASIPlatforms + [.wasi]
let wasiPlatform: [Platform] = [.wasi]
let khasmEmbedded = ProcessInfo.processInfo.environment["KHASM_EMBEDDED"] == "1"
let nioPlatforms: [Platform] = khasmEmbedded ? nonWASIPlatforms : allPlatforms

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
        // DOWNSTREAM-ONLY: the PassiveLogic fork, not apple/swift-nio. Two reasons, both
        // khasm-specific:
        //   1. NIOAsyncRuntime (used below on WASI) is fork-only — upstream SwiftNIO has
        //      no EventLoopGroup that compiles for wasm32-unknown-wasip1.
        //   2. Package identity: khasm's root manifest pins this identity to the fork on
        //      a branch. When this manifest named apple/swift-nio, SwiftPM canonicalized
        //      the `swift-nio` identity onto the upstream URL while keeping the root's
        //      branch requirement, then failed with `unable to read tree` on the
        //      fork-only revision. Agreeing with the root's location avoids that.
        // NOTE: the fork is based on upstream 2.94.0 — BELOW upstream sqlite-nio's declared
        // 2.101.3 floor. The branch requirement makes the floor moot for resolution, and the
        // APIs this package uses (`NIOThreadPool.singleton`/`.WorkItemState`/`runIfActive`,
        // `MultiThreadedEventLoopGroup.singleton`) all exist in 2.94. The one casualty is the
        // `NIOFoundationEssentialsCompat` product (introduced later) — see the target note.
        .package(url: "https://github.com/PassiveLogic/swift-nio.git", branch: "feat/khasmPAL-2026"),
        // swift-log stays on the upstream URL: khasm's ROOT manifest path-wires
        // `../swift-log` to the Embedded-patched clone, and a root path declaration wins
        // this identity graph-wide.
        .package(url: "https://github.com/apple/swift-log.git", from: "1.14.0"),
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
            name: "VaporCSQLite",
            cSettings: sqliteCSettings
        ),
        .target(
            name: "SQLiteNIO",
            dependencies: [
                .target(name: "VaporCSQLite"),
                .product(name: "Logging", package: "swift-log"),
                // Upstream drops these on WASI unconditionally; DOWNSTREAM-ONLY, khasm keeps
                // them for its regular wasm flavor (`nioPlatforms` == every platform unless
                // KHASM_EMBEDDED=1 — see the note at the top). On WASI, NIOPosix imports as a
                // partial module without `MultiThreadedEventLoopGroup`/`NIOThreadPool`, so
                // NIOAsyncRuntime supplies both; Sources/SQLiteNIO/{Exports,SQLiteConnection}.swift
                // pick between them with `#if os(WASI)`.
                .product(name: "NIOCore", package: "swift-nio", condition: .when(platforms: nioPlatforms)),
                .product(name: "NIOPosix", package: "swift-nio", condition: .when(platforms: nioPlatforms)),
                // DOWNSTREAM-ONLY: upstream conditions NIOFoundationCompat to Darwin and bridges
                // `FoundationEssentials.Data` through NIOFoundationEssentialsCompat everywhere
                // else. The PL fork (2.94.0-based) predates NIOFoundationEssentialsCompat, and
                // SwiftPM validates product existence regardless of platform conditions, so that
                // product reference is REMOVED here and NIOFoundationCompat covers all platforms
                // where NIO is present instead (on WASI/Linux, `Foundation.Data` IS
                // `FoundationEssentials.Data` re-exported, so the bridge API is the same one).
                // Sources/SQLiteNIO/SQLiteDataConvertible.swift carries the matching import gate.
                .product(name: "NIOFoundationCompat", package: "swift-nio", condition: .when(platforms: nioPlatforms)),
            ] + (khasmEmbedded ? [] : [
                .product(name: "NIOAsyncRuntime", package: "swift-nio", condition: .when(platforms: wasiPlatform)),
            ] as [Target.Dependency]),
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
    // .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    // .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
] }

var sqliteCSettings: [CSetting] { [
    // Derived from sqlite3 version 3.53.0
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
    .define("SQLITE_THREADSAFE", to: "1"),
    .define("SQLITE_UNTESTABLE"),
    .define("SQLITE_USE_URI"),
    .define("HAVE_GETHOSTUUID", to: "0", .when(platforms: [.iOS])) // silences compiler warning
] }
