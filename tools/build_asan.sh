#!/bin/bash
# Build a Mojo shared library with AddressSanitizer instrumentation.
#
# On macOS the Mojo pixi package does not bundle the LLVM ASAN dylib, so the
# linker cannot resolve ___asan_version_mismatch_check_v8.  We locate it from
# the conda env (unlikely) or from Homebrew LLVM and pass it directly to the
# linker together with --shared-libasan.
#
# Usage: build_asan.sh <mojo-source-file> <output.so> [extra mojo flags...]
# All remaining arguments after the output path are forwarded to mojo build.

set -e

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <source.mojo> <output.so> [extra-mojo-flags...]" >&2
    exit 1
fi

SOURCE="$1"
OUTPUT="$2"
shift 2

EXTRA_LINK_FLAGS=()

if [[ "$(uname)" == "Darwin" ]]; then
    ASAN_LIB=$(find "${CONDA_PREFIX:-/nonexistent}" -name "libclang_rt.asan_osx_dynamic.dylib" 2>/dev/null | head -1)
    if [[ -z "$ASAN_LIB" ]]; then
        ASAN_LIB=$(find /opt/homebrew -name "libclang_rt.asan_osx_dynamic.dylib" 2>/dev/null | head -1)
    fi
    if [[ -z "$ASAN_LIB" ]]; then
        echo "ERROR: libclang_rt.asan_osx_dynamic.dylib not found." >&2
        echo "       Install LLVM via Homebrew: brew install llvm" >&2
        exit 1
    fi
    EXTRA_LINK_FLAGS=(--shared-libasan -Xlinker "$ASAN_LIB")
fi

exec mojo build -sanitize address "${EXTRA_LINK_FLAGS[@]}" --emit shared-lib "$@" "$SOURCE" -o "$OUTPUT"
