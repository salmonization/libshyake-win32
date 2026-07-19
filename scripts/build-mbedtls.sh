#!/usr/bin/env bash
# Build static mbedTLS 3.6 LTS with the RtlGenRandom entropy patch.
# Run inside an MSYS2 environment shell; installs to deps/<MSYSTEM>.
# Needed where pacman has no mbedtls (MINGW32) or for the XP line.
set -euo pipefail

VER=3.6.4
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/deps/build-$MSYSTEM"
PREFIX="$ROOT/deps/$MSYSTEM"

mkdir -p "$WORK"
cd "$WORK"

if [ ! -d "mbedtls-$VER" ]; then
    curl -sLO "https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$VER/mbedtls-$VER.tar.bz2"
    tar xjf "mbedtls-$VER.tar.bz2"
    (cd "mbedtls-$VER" && patch -p1 \
        < "$ROOT/patches/mbedtls-3.6-rtlgenrandom.patch")
fi

EXTRA_C_FLAGS=""
if [ "$MSYSTEM" = "MINGW32" ]; then
    EXTRA_C_FLAGS="-march=i686 -mno-sse -D_WIN32_WINNT=0x0501"
fi

cmake -G Ninja -S "mbedtls-$VER" -B build-mbedtls \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_FLAGS="$EXTRA_C_FLAGS" \
    -DENABLE_TESTING=OFF \
    -DENABLE_PROGRAMS=OFF \
    -DGEN_FILES=OFF

cmake --build build-mbedtls
cmake --install build-mbedtls
echo "mbedTLS installed to $PREFIX"
