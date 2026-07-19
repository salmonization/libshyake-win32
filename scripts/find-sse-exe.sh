#!/usr/bin/env bash
# Locate which function in a linked exe/dll emits real SSE
# instructions (xmm operands), including code pulled in from
# system crt/libgcc/mingwex, not just our own static libs.
# Usage: ./scripts/find-sse-exe.sh build/test_crypto.exe
set -euo pipefail

BIN="${1:?usage: find-sse-exe.sh <path-to-exe-or-dll>}"

# awk's \b is a literal backspace, not a word boundary (unlike
# GNU grep -E), so matching must happen in grep; awk only tags
# each line with the function it falls under.
objdump -d "$BIN" \
    | awk '
        /^[0-9a-f]+ </ { fn = $0 }
        { print fn "\t" $0 }
    ' \
    | grep -E '\b(movsd|movaps|movapd|movups|addsd|mulsd|cvtsi2sd|cvttsd2si|movdqa|movdqu|pxor|paddd|pand)\b' \
    | grep '%xmm' \
    | cut -f1 \
    | sort | uniq -c | sort -rn
