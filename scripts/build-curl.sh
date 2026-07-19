#!/usr/bin/env bash
# Build static libcurl with the mbedTLS backend (HTTP only).
# Requires deps/<MSYSTEM> to already contain mbedTLS
# (scripts/build-mbedtls.sh). Installs to deps/<MSYSTEM>.
set -euo pipefail

VER=8.14.1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/deps/build-$MSYSTEM"
PREFIX="$ROOT/deps/$MSYSTEM"

mkdir -p "$WORK"
cd "$WORK"

if [ ! -d "curl-$VER" ]; then
    curl -sLO "https://curl.se/download/curl-$VER.tar.bz2"
    tar xjf "curl-$VER.tar.bz2"
fi

EXTRA_C_FLAGS=""
if [ "$MSYSTEM" = "MINGW32" ]; then
    EXTRA_C_FLAGS="-march=i686 -mno-sse -D_WIN32_WINNT=0x0501 \
-D__USE_MINGW_ANSI_STDIO=1"
fi

cmake -G Ninja -S "curl-$VER" -B build-curl \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DCMAKE_C_FLAGS="$EXTRA_C_FLAGS" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_CURL_EXE=OFF \
    -DBUILD_LIBCURL_DOCS=OFF -DBUILD_MISC_DOCS=OFF \
    -DCURL_USE_MBEDTLS=ON \
    -DCURL_USE_OPENSSL=OFF \
    -DCURL_USE_SCHANNEL=OFF \
    -DCURL_USE_LIBPSL=OFF \
    -DCURL_USE_LIBSSH2=OFF \
    -DCURL_ZLIB=OFF \
    -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF \
    -DUSE_NGHTTP2=OFF -DUSE_LIBIDN2=OFF \
    -DHTTP_ONLY=ON \
    -DENABLE_UNICODE=OFF \
    -DCURL_CA_BUNDLE=none -DCURL_CA_PATH=none

cmake --build build-curl
cmake --install build-curl
echo "libcurl installed to $PREFIX"
