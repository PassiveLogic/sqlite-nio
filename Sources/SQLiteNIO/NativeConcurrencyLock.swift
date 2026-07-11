#if NativeConcurrency
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

/// A minimal mutex-protected value box for the NativeConcurrency (NIO-free) build.
///
/// `NIOConcurrencyHelpers.NIOLock` is unavailable here (NIO is not linked), and
/// `Synchronization.Mutex` would force a platform-floor bump (macOS 15 et al.), so this uses
/// `os_unfair_lock` on Darwin and `pthread_mutex_t` elsewhere. On single-threaded targets with
/// no lock primitive (Embedded WASI) it degrades to direct access, which is sound because that
/// runtime has exactly one thread.
final class NativeConcurrencyLockedBox<Value>: @unchecked Sendable {
    #if hasFeature(Embedded) || os(WASI)
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        try body(&self.value)
    }
    #elseif canImport(Darwin)
    private let lockPointer: os_unfair_lock_t
    private var value: Value

    init(_ value: Value) {
        self.lockPointer = .allocate(capacity: 1)
        self.lockPointer.initialize(to: os_unfair_lock())
        self.value = value
    }

    deinit {
        self.lockPointer.deinitialize(count: 1)
        self.lockPointer.deallocate()
    }

    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        os_unfair_lock_lock(self.lockPointer)
        defer { os_unfair_lock_unlock(self.lockPointer) }
        return try body(&self.value)
    }
    #else
    private let mutexPointer: UnsafeMutablePointer<pthread_mutex_t>
    private var value: Value

    init(_ value: Value) {
        self.mutexPointer = .allocate(capacity: 1)
        self.mutexPointer.initialize(to: pthread_mutex_t())
        pthread_mutex_init(self.mutexPointer, nil)
        self.value = value
    }

    deinit {
        pthread_mutex_destroy(self.mutexPointer)
        self.mutexPointer.deinitialize(count: 1)
        self.mutexPointer.deallocate()
    }

    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        pthread_mutex_lock(self.mutexPointer)
        defer { pthread_mutex_unlock(self.mutexPointer) }
        return try body(&self.value)
    }
    #endif
}
#endif  // NativeConcurrency
