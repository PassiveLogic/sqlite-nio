<div align="center">
<img src="https://design.vapor.codes/images/vapor-sqlitenio.svg" height="96" alt="SQLiteNIO">
<br>

[![Documentation](https://design.vapor.codes/images/readthedocs.svg)](https://docs.vapor.codes/4.0/)
[![Team Chat](https://design.vapor.codes/images/discordchat.svg)](https://discord.gg/vapor)
[![MIT License](https://design.vapor.codes/images/mitlicense.svg)](./LICENSE)
[![Continuous Integration](https://img.shields.io/github/actions/workflow/status/vapor/sqlite-nio/test.yml?event=push&style=plastic&logo=github&label=tests&logoColor=ccc)](https://github.com/vapor/sqlite-nio/actions/workflows/test.yml)
[![Code Coverage](https://img.shields.io/codecov/c/github/vapor/sqlite-nio?style=plastic&logo=codecov&label=codecov)](https://codecov.io/github/vapor/sqlite-nio)
[![Swift 6.1+](https://design.vapor.codes/images/swift61up.svg)](https://swift.org)

</div>

<br>

🪶 Non-blocking, event-driven Swift client for [SQLite](https://sqlite.org) built on [SwiftNIO](https://github.com/apple/swift-nio).

## Using SQLiteNIO

Use standard SwiftPM syntax to include SQLiteNIO as a dependency in your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/vapor/sqlite-nio.git", from: "1.0.0")
]
```

### Supported Platforms

SQLiteNIO supports all platforms on which NIO itself works. At the time of this writing, these include:

- Ubuntu 20.04+
- macOS 10.15+
- iOS 13+
- tvOS 13+ and watchOS 7+ (experimental)

## PassiveLogic fork

This fork incorporates upstream SQLiteNIO 1.13.0 while retaining WASI support
through `NIOAsyncRuntime` and the `executeScript` API. It requires Swift 6.1 or
newer. WASI uses single-threaded SQLite; native platforms retain threaded SQLite
and `NIOPosix`. Both query and script async overloads use the direct async
thread-pool path instead of bridging through `EventLoopFuture.get()`.

The upstream synchronization includes its guarded SQLite initialization and
its narrowly scoped `columnName()` Thread Sanitizer annotation. It does not
disable sanitizer coverage for the library or the test suite.

Upstream adds async `query` and `withConnection` protocol requirements with
default implementations. The API checker reports these additions, so the
dedicated API job explicitly allows those two diagnostics. A future-only legacy
conformer test exercises both async defaults.

On Linux, the upstream FoundationEssentials migration also changes the transitive
conformance surface. The allowlist records the exact external diagnostics:
`String: CVarArg` and `Date: CustomPlaygroundDisplayConvertible` belong to
Foundation; the scalar `AtomicRepresentable` conformances belong to
Synchronization. Consumers using those capabilities should explicitly import
their defining module rather than rely on SQLiteNIO to expose it. Import probes
exercise these capabilities; the `Date` playground conformance is tested only on
Linux, where it is available. These are accepted upstream exposure changes, not
a claim of universally unchanged source or binary ABI compatibility. The API
check still compares against this fork's target branch; only the listed
diagnostics are allowed, and unexpected API changes remain checked.

### Wasm and CI

With Swift 6.4.0 and its matching SDK installed:

```sh
swift build --swift-sdk swift-6.4.0-RELEASE_wasm --build-system native
```

Swift 6.4's default build system can include transitive native-only dependencies
in a Wasm build. CI uses the native build-system override only in the dedicated
Wasm job; native checks retain their defaults. The option is deprecated, so
verify the [SwiftPM 6.4.x platform-condition fix](https://github.com/swiftlang/swift-package-manager/pull/10556)
with a released toolchain before removing the override.

Android CI keeps its Swift 6.2/6.3 matrix and cold-boots emulators with
`-no-snapshot`, avoiding the snapshot-startup failure encountered before tests
could run. These CI settings match the separate Wasm-integration PR; the
upstream SQLite Wasm C helpers are not part of this synchronization.
