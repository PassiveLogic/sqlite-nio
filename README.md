<p align="center">
<img src="https://design.vapor.codes/images/vapor-sqlitenio.svg" height="96" alt="SQLiteNIO">
<br>
<br>
<a href="https://docs.vapor.codes/4.0/"><img src="https://design.vapor.codes/images/readthedocs.svg" alt="Documentation"></a>
<a href="https://discord.gg/vapor"><img src="https://design.vapor.codes/images/discordchat.svg" alt="Team Chat"></a>
<a href="LICENSE"><img src="https://design.vapor.codes/images/mitlicense.svg" alt="MIT License"></a>
<a href="https://github.com/vapor/sqlite-nio/actions/workflows/test.yml"><img src="https://img.shields.io/github/actions/workflow/status/vapor/sqlite-nio/test.yml?event=push&style=plastic&logo=github&label=tests&logoColor=%23ccc" alt="Continuous Integration"></a>
<a href="https://codecov.io/github/vapor/sqlite-nio"><img src="https://img.shields.io/codecov/c/github/vapor/sqlite-nio?style=plastic&logo=codecov&label=codecov"></a>
<a href="https://swift.org"><img src="https://design.vapor.codes/images/swift510up.svg" alt="Swift 5.10+"></a>
</p>

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
