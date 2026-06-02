/*
** A SQLite VFS that stores database files in the browser's Origin Private File
** System (OPFS), making `.file(path:)` storage durable across page reloads when
** a SwiftWasm executable that links sqlite-nio runs in a browser.
**
** SQLite's VFS contract is synchronous, and OPFS exposes a synchronous API
** (FileSystemSyncAccessHandle) -- but only inside a dedicated Web Worker. This
** VFS therefore forwards each file operation to a small set of host-provided
** import functions (the "opfs" import module). The browser supplies those
** functions, backed by OPFS sync access handles, at WASM instantiate time.
** Because the imports are plain synchronous calls, no Asyncify transform is
** needed.
**
** This file is only active when compiling for WASI (the browser/wasm target).
** On every other platform the two public entry points are no-op stubs so the
** symbol table stays identical across platforms and the default VFS is left
** untouched.
**
** Build/vendoring notes:
**  - Uses only the `sqlite_nio_`-prefixed SQLite *functions* (the vendored
**    amalgamation renames API functions but NOT struct types or result-code
**    macros), so `sqlite3_vfs`/`sqlite3_file`/`SQLITE_OK` appear unprefixed.
**  - Lives in its own translation unit; the VendorSQLite plugin only rewrites
**    sqlite_nio_sqlite3.{c,h}, so this file survives re-vendoring.
*/

#include "sqlite_nio_sqlite3.h"
#include "sqlite_nio_opfs.h"

#if defined(__wasi__)

#include <string.h>

/*
** ---- Host import ABI (WASM import module "opfs") -------------------------
**
** This is the contract the JavaScript host must satisfy. Every function below
** is imported from module "opfs" and must be provided at instantiate time.
**
** Conventions:
**  - Pointers (`buf`, `outFd`, ...) are i32 byte offsets into wasm linear
**    memory; the host must build its typed-array views over the *same*
**    WebAssembly.Memory the instance exports.
**  - Paths are passed as (pointer, byteLength); they are NOT NUL-terminated on
**    the JS side -- use the explicit length.
**  - File offsets and sizes are `sqlite3_int64`; they arrive in JS as BigInt.
**  - Unless noted, the return value is a SQLite result code (SQLITE_OK == 0).
**
** Per-function contract:
**  available()        -> 1 if OPFS + sync access handles are usable, else 0.
**  open(p,n,flags,
**       outFd,outFlags)-> result code. On OK, *outFd receives a host handle id
**                         and *outFlags the flags actually granted (0 => echo
**                         the requested flags).
**  close(fd)          -> result code (flush + close).
**  read(fd,buf,amt,
**       ofst)         -> NUMBER OF BYTES READ (>= 0), or a negative value on
**                         I/O error. A short count is normal at end-of-file;
**                         this VFS zero-fills the remainder and reports
**                         SQLITE_IOERR_SHORT_READ.
**  write(fd,buf,amt,
**        ofst)        -> number of bytes written (>= 0), or negative on error.
**  sync(fd,flags)     -> result code (flush).
**  truncate(fd,size)  -> result code.
**  fileSize(fd,
**           outSize)  -> result code; on OK, *outSize receives the file size.
**  delete(p,n,syncDir)-> result code; deleting a missing file is OK.
**  access(p,n,flags,
**         outRes)     -> result code; *outRes set to 1 if the file exists else 0.
**  randomness(buf,n)  -> number of random bytes written into buf.
**  currentTimeMs()    -> milliseconds since the Unix epoch (i64). Converted to
**                         a Julian Day number here for xCurrentTime.
**  sleep(micros)      -> microseconds actually slept (no-op is fine).
*/

#define OPFS_IMPORT(sym) \
    __attribute__((__import_module__("opfs"), __import_name__(#sym)))

OPFS_IMPORT(available)     int  opfs_available(void);
OPFS_IMPORT(open)          int  opfs_open(const char *zName, int nName, int flags, int *pOutFd, int *pOutFlags);
OPFS_IMPORT(close)         int  opfs_close(int fd);
OPFS_IMPORT(read)          int  opfs_read(int fd, void *buf, int amt, sqlite3_int64 ofst);
OPFS_IMPORT(write)         int  opfs_write(int fd, const void *buf, int amt, sqlite3_int64 ofst);
OPFS_IMPORT(sync)          int  opfs_sync(int fd, int flags);
OPFS_IMPORT(truncate)      int  opfs_truncate(int fd, sqlite3_int64 size);
OPFS_IMPORT(fileSize)      int  opfs_file_size(int fd, sqlite3_int64 *pOutSize);
OPFS_IMPORT(delete)        int  opfs_delete(const char *zName, int nName, int syncDir);
OPFS_IMPORT(access)        int  opfs_access(const char *zName, int nName, int flags, int *pOutRes);
OPFS_IMPORT(randomness)    int  opfs_randomness(void *buf, int n);
OPFS_IMPORT(currentTimeMs) sqlite3_int64 opfs_current_time_ms(void);
OPFS_IMPORT(sleep)         int  opfs_sleep(int micros);

/* Maximum path length advertised by the VFS. */
#define OPFS_MAX_PATHNAME 1024

/*
** Subclass of sqlite3_file. `base` MUST be the first member so a
** `sqlite3_file*` can be cast to an `OpfsFile*` and back.
*/
typedef struct OpfsFile OpfsFile;
struct OpfsFile {
    sqlite3_file base;                 /* Base class -- must be first. */
    int fd;                            /* Host handle id from opfs_open(). */
    int deleteOnClose;                 /* True => unlink zPath in xClose. */
    char zPath[OPFS_MAX_PATHNAME + 1]; /* Path, kept only for DELETEONCLOSE. */
};

/* ---- sqlite3_io_methods implementation ---------------------------------- */

static int opfsClose(sqlite3_file *pFile) {
    OpfsFile *p = (OpfsFile *)pFile;
    int rc = opfs_close(p->fd);
    if (p->deleteOnClose) {
        opfs_delete(p->zPath, (int)strlen(p->zPath), 0);
    }
    return rc;
}

static int opfsRead(sqlite3_file *pFile, void *zBuf, int iAmt, sqlite3_int64 iOfst) {
    OpfsFile *p = (OpfsFile *)pFile;
    int got = opfs_read(p->fd, zBuf, iAmt, iOfst);
    if (got == iAmt) {
        return SQLITE_OK;
    }
    if (got < 0) {
        return SQLITE_IOERR_READ;
    }
    /* Short read: SQLite requires the unread tail to be zeroed. */
    memset((unsigned char *)zBuf + got, 0, (size_t)(iAmt - got));
    return SQLITE_IOERR_SHORT_READ;
}

static int opfsWrite(sqlite3_file *pFile, const void *zBuf, int iAmt, sqlite3_int64 iOfst) {
    OpfsFile *p = (OpfsFile *)pFile;
    int wrote = opfs_write(p->fd, zBuf, iAmt, iOfst);
    if (wrote == iAmt) {
        return SQLITE_OK;
    }
    if (wrote < 0) {
        return SQLITE_IOERR_WRITE;
    }
    return SQLITE_FULL; /* A partial write means we ran out of space. */
}

static int opfsTruncate(sqlite3_file *pFile, sqlite3_int64 size) {
    OpfsFile *p = (OpfsFile *)pFile;
    return opfs_truncate(p->fd, size);
}

static int opfsSync(sqlite3_file *pFile, int flags) {
    OpfsFile *p = (OpfsFile *)pFile;
    return opfs_sync(p->fd, flags);
}

static int opfsFileSize(sqlite3_file *pFile, sqlite3_int64 *pSize) {
    OpfsFile *p = (OpfsFile *)pFile;
    return opfs_file_size(p->fd, pSize);
}

/*
** Locking is a no-op. The wasm build is single-threaded (SQLITE_THREADSAFE=0)
** and the OPFS sync-access-handle model already grants exclusive access to the
** one Worker that holds the handle, so there is no concurrent access to guard.
*/
static int opfsLock(sqlite3_file *pFile, int eLock) {
    (void)pFile; (void)eLock;
    return SQLITE_OK;
}

static int opfsUnlock(sqlite3_file *pFile, int eLock) {
    (void)pFile; (void)eLock;
    return SQLITE_OK;
}

static int opfsCheckReservedLock(sqlite3_file *pFile, int *pResOut) {
    (void)pFile;
    *pResOut = 0;
    return SQLITE_OK;
}

static int opfsFileControl(sqlite3_file *pFile, int op, void *pArg) {
    (void)pFile; (void)op; (void)pArg;
    return SQLITE_NOTFOUND;
}

static int opfsSectorSize(sqlite3_file *pFile) {
    (void)pFile;
    return 4096;
}

static int opfsDeviceCharacteristics(sqlite3_file *pFile) {
    (void)pFile;
    return 0;
}

/*
** iVersion 1: only the methods through xDeviceCharacteristics are populated.
** Staying at version 1 avoids the shared-memory (xShm*) and memory-mapping
** (xFetch/xUnfetch) methods, which a single-connection OPFS file does not need
** and which would add i64 surface at the JS boundary. Designated initializers
** are used so a future struct reordering fails to compile instead of silently
** wiring the wrong function to the wrong slot.
*/
static const sqlite3_io_methods opfsIoMethods = {
    .iVersion               = 1,
    .xClose                 = opfsClose,
    .xRead                  = opfsRead,
    .xWrite                 = opfsWrite,
    .xTruncate              = opfsTruncate,
    .xSync                  = opfsSync,
    .xFileSize              = opfsFileSize,
    .xLock                  = opfsLock,
    .xUnlock                = opfsUnlock,
    .xCheckReservedLock     = opfsCheckReservedLock,
    .xFileControl           = opfsFileControl,
    .xSectorSize            = opfsSectorSize,
    .xDeviceCharacteristics = opfsDeviceCharacteristics,
};

/* ---- sqlite3_vfs implementation ----------------------------------------- */

static int opfsOpen(
    sqlite3_vfs *pVfs,
    sqlite3_filename zName,
    sqlite3_file *pFile,
    int flags,
    int *pOutFlags
) {
    OpfsFile *p = (OpfsFile *)pFile;

    /* Leave pMethods clear until we fully succeed: SQLite only calls xClose
    ** when pMethods is non-NULL, so an early return here must not set it. */
    p->base.pMethods = 0;

    /* A NULL name requests an anonymous temporary file. We do not service those
    ** here; the browser POC sets PRAGMA temp_store=MEMORY (and journal_mode=
    ** MEMORY) so SQLite never asks the VFS for one. */
    if (zName == 0) {
        return SQLITE_CANTOPEN;
    }

    int n = (int)strlen(zName);
    if (n > pVfs->mxPathname) {
        return SQLITE_CANTOPEN;
    }

    int fd = -1;
    int outFlags = 0;
    int rc = opfs_open(zName, n, flags, &fd, &outFlags);
    if (rc != SQLITE_OK) {
        return rc;
    }

    p->fd = fd;
    p->deleteOnClose = (flags & SQLITE_OPEN_DELETEONCLOSE) ? 1 : 0;
    if (p->deleteOnClose) {
        memcpy(p->zPath, zName, (size_t)n);
        p->zPath[n] = '\0';
    }
    p->base.pMethods = &opfsIoMethods;
    if (pOutFlags) {
        *pOutFlags = outFlags ? outFlags : flags;
    }
    return SQLITE_OK;
}

static int opfsDelete(sqlite3_vfs *pVfs, const char *zName, int syncDir) {
    (void)pVfs;
    return opfs_delete(zName, (int)strlen(zName), syncDir);
}

static int opfsAccess(sqlite3_vfs *pVfs, const char *zName, int flags, int *pResOut) {
    (void)pVfs;
    return opfs_access(zName, (int)strlen(zName), flags, pResOut);
}

/*
** xFullPathname is a bounds-checked copy-through. The browser uses flat,
** absolute OPFS paths (e.g. "/poc.sqlite3"), so there is nothing to resolve;
** we only guarantee a NUL-terminated result that fits the caller's buffer.
*/
static int opfsFullPathname(sqlite3_vfs *pVfs, const char *zName, int nOut, char *zOut) {
    (void)pVfs;
    size_t n = strlen(zName);
    if (n >= (size_t)nOut) {
        return SQLITE_CANTOPEN;
    }
    memcpy(zOut, zName, n);
    zOut[n] = '\0';
    return SQLITE_OK;
}

static int opfsRandomness(sqlite3_vfs *pVfs, int nByte, char *zOut) {
    (void)pVfs;
    return opfs_randomness(zOut, nByte);
}

static int opfsSleep(sqlite3_vfs *pVfs, int microseconds) {
    (void)pVfs;
    return opfs_sleep(microseconds);
}

static int opfsCurrentTime(sqlite3_vfs *pVfs, double *pNow) {
    (void)pVfs;
    sqlite3_int64 ms = opfs_current_time_ms();
    /* 2440587.5 is the Julian Day number at the Unix epoch (1970-01-01T00:00Z). */
    *pNow = 2440587.5 + (double)ms / 86400000.0;
    return SQLITE_OK;
}

static int opfsGetLastError(sqlite3_vfs *pVfs, int nBuf, char *zBuf) {
    (void)pVfs; (void)nBuf; (void)zBuf;
    return 0;
}

/*
** iVersion 1 VFS: methods through xGetLastError. xCurrentTimeInt64 and the
** xSetSystemCall/xGetSystemCall/xNextSystemCall trio (v2/v3) are intentionally
** omitted. The dynamic-loading hooks are NULL because SQLITE_OMIT_LOAD_EXTENSION
** is defined for this build. Not const: vfs_register threads pNext through it.
*/
static sqlite3_vfs opfsVfs = {
    .iVersion      = 1,
    .szOsFile      = sizeof(OpfsFile),
    .mxPathname    = OPFS_MAX_PATHNAME,
    .pNext         = 0,
    .zName         = "opfs",
    .pAppData      = 0,
    .xOpen         = opfsOpen,
    .xDelete       = opfsDelete,
    .xAccess       = opfsAccess,
    .xFullPathname = opfsFullPathname,
    .xDlOpen       = 0,
    .xDlError      = 0,
    .xDlSym        = 0,
    .xDlClose      = 0,
    .xRandomness   = opfsRandomness,
    .xSleep        = opfsSleep,
    .xCurrentTime  = opfsCurrentTime,
    .xGetLastError = opfsGetLastError,
};

int sqlite_nio_opfs_register_vfs(void) {
    if (!opfs_available()) {
        return SQLITE_ERROR;
    }
    if (sqlite_nio_sqlite3_vfs_find("opfs") != 0) {
        return SQLITE_OK; /* Already registered; first registration made it default. */
    }
    return sqlite_nio_sqlite3_vfs_register(&opfsVfs, 1 /* makeDflt */);
}

int sqlite_nio_opfs_is_available(void) {
    return opfs_available();
}

#else /* !defined(__wasi__) */

/*
** Non-WASI platforms: no OPFS, no host imports. Registration is a successful
** no-op (the platform's normal default VFS keeps working) and availability is
** always false. Crucially, this path does NOT register a VFS named "opfs".
*/

int sqlite_nio_opfs_register_vfs(void) {
    return SQLITE_OK;
}

int sqlite_nio_opfs_is_available(void) {
    return 0;
}

#endif /* defined(__wasi__) */
