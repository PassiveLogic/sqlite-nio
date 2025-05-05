@_documentation(visibility: internal) @_exported import struct NIOCore.ByteBuffer
// SM: NOW: Uncomment once done with get() effort. And cleanup this up using appropriate canImports.
//#if !os(WASI)
//@_documentation(visibility: internal) @_exported import class NIOPosix.NIOThreadPool
//// TODO: SM: else NIOAsyncIO ??
//#endif
@_documentation(visibility: internal) @_exported import protocol NIOCore.EventLoop
@_documentation(visibility: internal) @_exported import protocol NIOCore.EventLoopGroup
// SM: NOW: Uncomment once done with get() effort
//#if !os(WASI)
//@_documentation(visibility: internal) @_exported import class NIOPosix.MultiThreadedEventLoopGroup
//// TODO: SM: else NIOAsyncIO ??
//#endif
