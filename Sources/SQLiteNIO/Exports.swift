@_documentation(visibility: internal) @_exported import struct NIOCore.ByteBuffer

// Prefer NIOPosix when available; only fall back to NIOAsyncRuntime when
// NIOPosix isn't (i.e. WASI). NIOAsyncRuntime's `AsyncEventLoopGroup` /
// `AsyncThreadPool` are macOS 15+ — gating purely on `canImport` would break
// any project whose deployment target is older but transitively pulls in
// NIOAsyncRuntime.
#if canImport(NIOPosix)
@_documentation(visibility: internal) @_exported import class NIOPosix.NIOThreadPool
#elseif canImport(NIOAsyncRuntime)
@_documentation(visibility: internal) @_exported import class NIOAsyncRuntime.AsyncThreadPool
#endif

@_documentation(visibility: internal) @_exported import protocol NIOCore.EventLoop
@_documentation(visibility: internal) @_exported import protocol NIOCore.EventLoopGroup

#if canImport(NIOPosix)
@_documentation(visibility: internal) @_exported import class NIOPosix.MultiThreadedEventLoopGroup
#elseif canImport(NIOAsyncRuntime)
@_documentation(visibility: internal) @_exported import class NIOAsyncRuntime.AsyncEventLoopGroup
#endif
