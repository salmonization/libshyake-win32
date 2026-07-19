#!/usr/bin/env bash
# Build static liboqs 0.15.0 with the RtlGenRandom patch.
# Run inside an MSYS2 environment shell (MINGW32 / MINGW64 /
# CLANGARM64); output goes to deps/<MSYSTEM>/.
set -euo pipefail

VER=0.15.0
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/deps/build-$MSYSTEM"
PREFIX="$ROOT/deps/$MSYSTEM"

mkdir -p "$WORK"
cd "$WORK"

if [ ! -d "liboqs-$VER" ]; then
    curl -sLO "https://github.com/open-quantum-safe/liboqs/archive/refs/tags/$VER.tar.gz"
    tar xzf "$VER.tar.gz"
    (cd "liboqs-$VER" && patch -p1 \
        < "$ROOT/patches/liboqs-$VER-rtlgenrandom.patch")
fi

# XP/i686 line: no SSE, XP API level, generic C only
EXTRA_C_FLAGS=""
NO_CPU_EXT_FLAGS=()
if [ "$MSYSTEM" = "MINGW32" ]; then
    EXTRA_C_FLAGS="-march=i686 -mno-sse -D_WIN32_WINNT=0x0501"
    # liboqs' CMake probes the build HOST's cpuid, not the target
    # arch flags, and bolts per-file -msse2/-mavx2 onto the
    # optimized ML-KEM/ML-DSA code paths regardless of
    # OQS_OPT_TARGET=generic. Disable every feature switch so it
    # falls back to the portable reference implementation.
    NO_CPU_EXT_FLAGS=(
        -DOQS_USE_AVX2_INSTRUCTIONS=OFF
        -DOQS_USE_AVX512_INSTRUCTIONS=OFF
        -DOQS_USE_AVX512VBMI2_INSTRUCTIONS=OFF
        -DOQS_USE_SSE2_INSTRUCTIONS=OFF
        -DOQS_USE_SSE3_INSTRUCTIONS=OFF
        -DOQS_USE_SSSE3_INSTRUCTIONS=OFF
        -DOQS_USE_BMI1_INSTRUCTIONS=OFF
        -DOQS_USE_BMI2_INSTRUCTIONS=OFF
        -DOQS_USE_ADX_INSTRUCTIONS=OFF
        -DOQS_USE_AES_INSTRUCTIONS=OFF
        -DOQS_USE_PCLMULQDQ_INSTRUCTIONS=OFF
        -DOQS_USE_VPCLMULQDQ_INSTRUCTIONS=OFF
        -DOQS_USE_POPCNT_INSTRUCTIONS=OFF
    )
fi

cmake -G Ninja -S "liboqs-$VER" -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_FLAGS="$EXTRA_C_FLAGS" \
    -DBUILD_SHARED_LIBS=OFF \
    -DOQS_BUILD_ONLY_LIB=ON \
    -DOQS_USE_OPENSSL=OFF \
    -DOQS_DIST_BUILD=OFF \
    -DOQS_OPT_TARGET=generic \
    -DOQS_PERMIT_UNSUPPORTED_ARCHITECTURE=ON \
    -DOQS_MINIMAL_BUILD="KEM_ml_kem_768;SIG_ml_dsa_65" \
    "${NO_CPU_EXT_FLAGS[@]}"

cmake --build build
cmake --install build
echo "liboqs installed to $PREFIX"
