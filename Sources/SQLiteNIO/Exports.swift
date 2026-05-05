@_documentation(visibility: internal) @_exported import struct NIOCore.ByteBuffer

// See SQLiteConnection.swift for why we gate on `os(WASI)` rather than
// `canImport(...)`: NIOAsyncRuntime is too greedy on macOS/Linux (its types
// require macOS 15+ and break older deployment targets), and NIOPosix is too
// greedy on WASI (the module imports as a partial stub but doesn't expose
// `MultiThreadedEventLoopGroup` / `NIOThreadPool` there).
#if os(WASI)
@_documentation(visibility: internal) @_exported import class NIOAsyncRuntime.AsyncThreadPool
#else
@_documentation(visibility: internal) @_exported import class NIOPosix.NIOThreadPool
#endif

@_documentation(visibility: internal) @_exported import protocol NIOCore.EventLoop
@_documentation(visibility: internal) @_exported import protocol NIOCore.EventLoopGroup

#if os(WASI)
@_documentation(visibility: internal) @_exported import class NIOAsyncRuntime.AsyncEventLoopGroup
#else
@_documentation(visibility: internal) @_exported import class NIOPosix.MultiThreadedEventLoopGroup
#endif
