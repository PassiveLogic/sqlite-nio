#ifndef SQLITE_NIO_OPFS_H
#define SQLITE_NIO_OPFS_H

#ifdef __cplusplus
extern "C" {
#endif

/// Register the OPFS-backed SQLite VFS and make it the default.
///
/// On WASI, when the host environment provides a working OPFS implementation
/// (via the `opfs` WASM import module), this registers a durable VFS named
/// "opfs" and makes it the default, so subsequent `sqlite3_open*` calls that
/// pass a NULL VFS name use it. This is what makes `.file(path:)` storage
/// survive a browser reload.
///
/// The call is idempotent: registering more than once is a no-op that keeps
/// "opfs" as the default.
///
/// Returns `SQLITE_OK` when the OPFS VFS is registered (or was already
/// registered). Returns a non-`SQLITE_OK` code when OPFS is unavailable, in
/// which case the previously installed default VFS is left untouched and file
/// storage falls back to whatever that VFS provides (ephemeral, in the browser).
///
/// On non-WASI platforms this is a no-op that returns `SQLITE_OK` without
/// registering anything; the platform's normal default VFS continues to be used.
int sqlite_nio_opfs_register_vfs(void);

/// Reports whether a working OPFS host implementation is available.
///
/// Returns a non-zero value when the `opfs` host import module reports that the
/// Origin Private File System (with synchronous access handles) is usable.
/// On non-WASI platforms this always returns 0.
int sqlite_nio_opfs_is_available(void);

#ifdef __cplusplus
}
#endif

#endif /* SQLITE_NIO_OPFS_H */
