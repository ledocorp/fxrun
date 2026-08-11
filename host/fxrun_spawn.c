/* fxrun_spawn.c — process edge: shell, mkdir, slice, manifest walk-up (FX-APP-RUN-2).
 *
 * Recipe storage is native Map<string,string> in fxrun_lib.fx — no host KV.
 * Cmds and relative paths run in the directory that owns Fxrun.toml.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include "zspec/core_allocator.h"
#include "zspec/core_error.h"
#include "zspec/core_string.h"

#ifdef _WIN32
#include <windows.h>
#include <direct.h>
#define fxrun_getcwd _getcwd
#define fxrun_chdir _chdir
#else
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#define fxrun_getcwd getcwd
#define fxrun_chdir chdir
#endif

static int fxrun_file_exists(const char *path) {
#ifdef _WIN32
    DWORD a;
    if (path == NULL || path[0] == '\0') {
        return 0;
    }
    a = GetFileAttributesA(path);
    return (a != INVALID_FILE_ATTRIBUTES) && ((a & FILE_ATTRIBUTE_DIRECTORY) == 0);
#else
    struct stat st;
    if (path == NULL || path[0] == '\0') {
        return 0;
    }
    if (stat(path, &st) != 0) {
        return 0;
    }
    return S_ISREG(st.st_mode);
#endif
}

/* Walk cwd → parents for Fxrun.toml / fxrun.toml; chdir there. 0 = ok, 1 = missing. */
int fxrun_host_chdir_to_manifest(void) {
    char cwd[4096];
    char probe[4224];
    size_t n;
    int depth;

    if (fxrun_getcwd(cwd, sizeof(cwd)) == NULL) {
        return 1;
    }
    for (depth = 0; depth < 64; depth++) {
        n = strlen(cwd);
        if (n + 16 >= sizeof(probe)) {
            return 1;
        }
        snprintf(probe, sizeof(probe), "%s/Fxrun.toml", cwd);
        if (fxrun_file_exists(probe)) {
            if (fxrun_chdir(cwd) != 0) {
                return 1;
            }
            return 0;
        }
        snprintf(probe, sizeof(probe), "%s/fxrun.toml", cwd);
        if (fxrun_file_exists(probe)) {
            if (fxrun_chdir(cwd) != 0) {
                return 1;
            }
            return 0;
        }
        /* strip last path component */
        while (n > 0 && (cwd[n - 1] == '/' || cwd[n - 1] == '\\')) {
            cwd[--n] = '\0';
        }
        while (n > 0 && cwd[n - 1] != '/' && cwd[n - 1] != '\\') {
            cwd[--n] = '\0';
        }
        while (n > 0 && (cwd[n - 1] == '/' || cwd[n - 1] == '\\')) {
            cwd[--n] = '\0';
        }
        if (n == 0) {
            break;
        }
#ifdef _WIN32
        /* "C:" root — one more probe then stop */
        if (n == 2 && cwd[1] == ':') {
            snprintf(probe, sizeof(probe), "%s\\Fxrun.toml", cwd);
            if (fxrun_file_exists(probe)) {
                if (fxrun_chdir(cwd) != 0) {
                    return 1;
                }
                return 0;
            }
            snprintf(probe, sizeof(probe), "%s\\fxrun.toml", cwd);
            if (fxrun_file_exists(probe)) {
                if (fxrun_chdir(cwd) != 0) {
                    return 1;
                }
                return 0;
            }
            break;
        }
#endif
    }
    return 1;
}

/* Run one shell command; return process exit code (127 = spawn fail). */
int fxrun_host_run_cmd(const char *cmd) {
    int st;
    if (cmd == NULL || cmd[0] == '\0') {
        return 1;
    }
#ifdef _WIN32
    st = system(cmd);
    if (st == -1) {
        return 127;
    }
    return st;
#else
    st = system(cmd);
    if (st == -1) {
        return 127;
    }
    if (WIFEXITED(st)) {
        return WEXITSTATUS(st);
    }
    return 1;
#endif
}

int fxrun_host_ensure_dir(const char *path) {
    if (path == NULL || path[0] == '\0') {
        return 1;
    }
#ifdef _WIN32
    if (CreateDirectoryA(path, NULL) || GetLastError() == ERROR_ALREADY_EXISTS) {
        return 0;
    }
    return 1;
#else
    (void)mkdir(path, 0755);
    return 0;
#endif
}

const char *fxrun_host_slice(const char *s, int32_t lo, int32_t hi) {
    size_t slen;
    char *out = NULL;
    core_str_view v;
    if (s == NULL || lo < 0 || hi < lo) {
        return "";
    }
    slen = strlen(s);
    if ((size_t)hi > slen) {
        hi = (int32_t)slen;
    }
    if ((size_t)lo > slen || lo == hi) {
        return "";
    }
    v = core_str_view_from_parts(s + (size_t)lo, (size_t)(hi - lo));
    if (core_str_dup(core_default_allocator(), v, &out) != CORE_OK || out == NULL) {
        return "";
    }
    return out;
}

/* Decimal string for stamp files (alloc). */
const char *fxrun_host_i32_dec(int32_t n) {
    char buf[16];
    char *out = NULL;
    int m;
    m = snprintf(buf, sizeof(buf), "%d", (int)n);
    if (m < 0) {
        return "0";
    }
    if (core_str_dup_cstr(core_default_allocator(), buf, &out) != CORE_OK || out == NULL) {
        return "0";
    }
    return out;
}
