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

### Swift 6.4 Wasm builds

Use SwiftPM's native build system when cross-compiling with Swift 6.4 and its
matching Wasm SDK:

```sh
swift build --swift-sdk swift-6.4.0-RELEASE_wasm --build-system native
```

With SwiftNIO 2.103.0, Swift 6.4's default build system includes `NIOPosix` in the
Wasm build despite the platform-conditional dependencies, then fails on missing
socket types. The same dependency resolution builds with `--build-system native`.
CI applies this override only in a dedicated Wasm job with a matching compiler
and checksum-verified SDK. Native jobs keep the shared workflow's default build
system, and the Wasm job retains the explicit import and Sendable checks.

This is a temporary build-system workaround, not a SQLite runtime change. Swift
6.4 deprecates the `native` option, so remove the override once the default build
system correctly handles this dependency graph. The Wasm check remains enabled.

SwiftPM's [transitive platform-condition fix](https://github.com/swiftlang/swift-package-manager/pull/10541)
has a [6.4.x backport](https://github.com/swiftlang/swift-package-manager/pull/10556).
Before removing the override, verify a toolchain containing that fix builds this
package with the default system without compiling `NIOPosix` for WASI.

### Android CI emulator startup

Android jobs keep the Swift 6.2/6.3 test matrix and use `-no-snapshot` to cold-boot
the emulator. Snapshot-restored runs repeatedly failed at `adb shell input
keyevent 82` with exit 137 before executing the test suite. The dedicated jobs
expose the emulator option that the shared workflow does not forward. This
disables snapshot loading/saving, not the action's dependency or AVD caches.
