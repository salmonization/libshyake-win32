#!/usr/bin/env bash
# Locate which function in a linked exe/dll emits real SSE
# instructions (xmm operands), including code pulled in from
# system crt/libgcc/mingwex, not just our own static libs.
# Usage: ./scripts/find-sse-exe.sh build/test_crypto.exe
set -euo pipefail

BIN="${1:?usage: find-sse-exe.sh <path-to-exe-or-dll>}"

objdump -d "$BIN" \
    | awk '
        /^[0-9a-f]+ </ { fn = $0; next }
        /\b(movsd|movaps|movapd|movups|addsd|mulsd|cvtsi2sd|cvttsd2si|movdqa|movdqu|pxor|paddd|pand)\b/ && /%xmm/ {
            print fn
        }
    ' \
    | sort | uniq -c | sort -rn
