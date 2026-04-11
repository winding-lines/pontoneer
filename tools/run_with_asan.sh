#!/bin/bash
# Wrapper for running Python tests against ASAN-instrumented shared libraries.
#
# On macOS the Mojo compiler embeds both an absolute Homebrew LLVM ASAN path and
# an @rpath/libclang_rt.asan_osx_dynamic.dylib entry, plus an rpath pointing at
# Xcode's clang runtime dir.  This causes two incompatible ASAN copies to load
# simultaneously (Homebrew LLVM "v8" + Apple clang "apple_clang_2100"), which makes
# ASAN abort with "Interceptors are not working."
#
# Fix applied to each .so before running tests:
#   Replace the Xcode clang rpath with the Homebrew LLVM ASAN lib directory so
#   that @rpath/libclang_rt.asan_osx_dynamic.dylib also resolves to the same
#   (Homebrew) file as the explicit absolute-path entry.  dyld deduplicates by
#   inode, so only one copy of ASAN loads.
#
# Then preload the ASAN dylib via DYLD_INSERT_LIBRARIES so interceptors are
# installed before Python's first allocation.
#
# On Linux the ASAN runtime is handled differently; no fixup is needed.

set -e

if [[ "$(uname)" == "Darwin" ]]; then
    # Find the LLVM ASAN dylib — prefer the conda env, then Homebrew.
    ASAN_LIB=$(find "${CONDA_PREFIX:-/nonexistent}" -name "libclang_rt.asan_osx_dynamic.dylib" 2>/dev/null | head -1)
    if [[ -z "$ASAN_LIB" ]]; then
        ASAN_LIB=$(find /opt/homebrew -name "libclang_rt.asan_osx_dynamic.dylib" 2>/dev/null | head -1)
    fi
    if [[ -z "$ASAN_LIB" ]]; then
        echo "ERROR: libclang_rt.asan_osx_dynamic.dylib not found." >&2
        echo "       Install LLVM via Homebrew: brew install llvm" >&2
        exit 1
    fi
    ASAN_LIB_DIR=$(dirname "$ASAN_LIB")

    # Patch every .so in the test directory.
    TEST_DIR=$(dirname "$1")
    for so in "$TEST_DIR"/*.so; do
        [[ -f "$so" ]] || continue
        XCODE_RPATH=$(otool -l "$so" 2>/dev/null \
            | awk '/LC_RPATH/{found=1} found && /path \/Applications\/Xcode/{print $2; found=0}')
        if [[ -n "$XCODE_RPATH" ]]; then
            install_name_tool -rpath "$XCODE_RPATH" "$ASAN_LIB_DIR" "$so"
        fi
    done

    export DYLD_INSERT_LIBRARIES="$ASAN_LIB"
fi

exec python3 "$@"
