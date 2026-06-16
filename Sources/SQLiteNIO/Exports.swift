// These re-exports are all SwiftNIO types, which are elided on WASI (the NIO-free path uses
// Swift Concurrency + `[UInt8]` instead of EventLoop/ByteBuffer).
#if !os(WASI)
@_documentation(visibility: internal) @_exported import struct NIOCore.ByteBuffer

@_documentation(visibility: internal) @_exported import class NIOPosix.NIOThreadPool

@_documentation(visibility: internal) @_exported import protocol NIOCore.EventLoop
@_documentation(visibility: internal) @_exported import protocol NIOCore.EventLoopGroup

@_documentation(visibility: internal) @_exported import class NIOPosix.MultiThreadedEventLoopGroup
#endif
