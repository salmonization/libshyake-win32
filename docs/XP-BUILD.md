# Building and verifying the XP/i686 line locally

CI only builds MINGW64 and CLANGARM64 (see `.github/workflows/
build.yml`). The i686/XP line is built and verified by hand. This
doc is the sole reference for that — read it fully before shipping
an XP build.

## Why CI doesn't do this

MSYS2's stock MINGW32 toolchain is configured
`--with-arch=pentium4 --with-tune=generic` (confirm with `gcc -v`).
That bakes an SSE2 baseline into `libgcc`, `mingw-w64-crt`, and
`mingwex` — the precompiled runtime objects every binary links
against for things as basic as `printf`, `gmtime`, and libm error
handling. Passing `-march=i686 -mno-sse` to our own sources (which
`CMakeLists.txt` already does) has no effect on those precompiled
objects; the instructions are baked in at the byte level and show
up in a linked binary regardless.

There is no config flag that fixes this — the only real fix is a
custom-built cross toolchain (binutils + gcc + mingw-w64 headers/
crt, all configured for a genuine i686 baseline), which is out of
scope for now. Until/unless that happens, an automated SSE gate in
CI would either be a permanent false failure (if it scans the whole
binary) or a false sense of safety (if it's scoped to only our own
object files, since it can't see the real risk in the CRT). Manual
build + hardware verification is the honest alternative.

## Prerequisites

- MSYS2 installed, with the **MINGW32** environment
  (`pacman -S --needed base-devel mingw-w64-i686-toolchain` if not
  already present).
- Run everything below from an "MSYS2 MINGW32" shell, not MSYS2 or
  MINGW64/UCRT64/CLANG64.

## Build

```bash
cd libshyake-win32
./scripts/build-liboqs.sh     # always from source, all arches
./scripts/build-mbedtls.sh    # i686: no pacman package; also
                               # carries the RtlGenRandom entropy
                               # patch and disables AES-NI (see
                               # patches/ and the script itself)
./scripts/build-curl.sh       # i686: no pacman package either;
                               # mbedTLS backend, HTTP only, static

cmake -G Ninja -B build
cmake --build build
./build/test_crypto.exe       # must pass

# if building natsuzake too, from its own directory:
cd ../natsuzake
cmake -G Ninja -B build
cmake --build build
```

Re-running `build-liboqs.sh` / `build-mbedtls.sh` / `build-curl.sh`
is idempotent — they skip work if the extracted source directory
under `deps/build-MINGW32/` already exists. If you change a patch
or a build script, delete the corresponding
`deps/build-MINGW32/<name>-<ver>/` directory first so it
re-extracts and re-patches.

## Verify: no post-XP DLL imports

```bash
objdump -p build/test_crypto.exe | grep "DLL Name"
```

Should be exactly `ADVAPI32.dll`, `KERNEL32.dll`, `msvcrt.dll` (plus
GUI-specific ones for Natsuzake.exe: `COMCTL32.dll`, `COMDLG32.dll`,
`GDI32.dll`, `SHELL32.dll`, `USER32.dll`, `WS2_32.dll`). None of
`api-ms-win-crt-*`, `ucrtbase.dll`, or `bcrypt.dll` should appear —
any of those means something pulled in a post-XP dependency
(usually a pacman-provided dependency that should have been built
from source instead, or a missing RtlGenRandom patch).

## Verify: no real SSE instructions in our own code and deps

```bash
./scripts/find-sse.sh                          # per static lib in deps/MINGW32/lib
./scripts/find-sse-exe.sh build/test_crypto.exe # per function in the linked exe
```

`find-sse.sh` should report `0` for every `.a` in `deps/MINGW32/
lib`. `find-sse-exe.sh` will still report a handful of hits in CRT-
internal functions (`__pformat_*`, `__matherr`, `__int_gmtime32_s`,
and similar) — **this is the pentium4-baseline toolchain issue
above, not a regression**. If you see hits in a function that is
*ours* (not a mingw-w64/libgcc-internal symbol) or in a *dependency*
object (mbedtls/curl/liboqs), that's a real regression — bisect
with `find-sse.sh` (which library) then re-extract that library's
`.a` with `ar x` to isolate the offending `.o`.

## The open risk (read before shipping)

The CRT-internal SSE instructions found above are real machine code
that ships in the binary. Whether they're ever *executed* on a true
non-SSE CPU depends on internal mingw-w64-crt code paths we don't
control and haven't audited function-by-function. Treat any XP
build as **unverified until it's been exercised on real non-SSE
hardware** (VAIO PCG-C1) — specifically exercise printf-heavy code
paths (logging, status text), date/time formatting, and anything
that can hit a libm error path (`matherr`), since those are exactly
the functions flagged above.

If a genuine crash is found on hardware, the only durable fix is
the custom cross toolchain mentioned above — building mingw-w64-crt
from source with a real i686 (no SSE) target — not another
dependency patch.
