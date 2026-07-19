#!/usr/bin/env bash
# Bisect which static lib/object introduces real SSE instructions
# in an i686 build. Run inside MSYS2 MINGW32 after building deps
# (build-liboqs.sh / build-mbedtls.sh / build-curl.sh) or the full
# project. Reports per-.a and, for the worst offender, per-object.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS="$ROOT/deps/MINGW32/lib"

is_sse() {
    objdump -d "$1" 2>/dev/null \
        | grep -E '\b(movsd|movaps|movapd|movups|addsd|mulsd|cvtsi2sd|cvttsd2si|movdqa|movdqu|pxor|paddd|pand)\b' \
        | grep -c '%xmm' || true
}

echo "== per-library scan (deps/MINGW32/lib) =="
for lib in "$DEPS"/*.a; do
    [ -f "$lib" ] || continue
    n=$(is_sse "$lib")
    printf '%6s  %s\n' "$n" "$(basename "$lib")"
done

echo
echo "== drilling into the worst offender's member objects =="
worst=""
worst_n=0
for lib in "$DEPS"/*.a; do
    [ -f "$lib" ] || continue
    n=$(is_sse "$lib")
    if [ "$n" -gt "$worst_n" ]; then
        worst_n=$n
        worst="$lib"
    fi
done

if [ -n "$worst" ]; then
    echo "worst: $worst ($worst_n hits)"
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && ar x "$worst")
    for obj in "$tmpdir"/*.o; do
        n=$(is_sse "$obj")
        [ "$n" != "0" ] && printf '%6s  %s\n' "$n" "$(basename "$obj")"
    done
    rm -rf "$tmpdir"
else
    echo "no library shows SSE hits — check the final linked exe" \
         "for crt/libgcc contributions instead"
fi
