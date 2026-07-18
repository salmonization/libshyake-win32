# Upstream baseline

Win32 fork of upstream libshyake (`shyake` repository,
`client/src/lib/` + `client/include/shyake.h` +
`client/tests/test_crypto.c`).

- **Baseline commit**: `c6bf410da6783c3b29fce204894a85f8c8168c03`
  (2026-07-18, "documentation")
- **SPEC version**: as of the baseline commit (shyake/docs/SPEC.md)

## Sync policy

Sync on demand only: when upstream changes the protocol, crypto, or
wire format (SPEC.md changes, or `client/src/lib/` behavior changes
affecting interoperability), diff against the baseline, port the
delta, and update the baseline hash here. Pure POSIX-side fixes are
not tracked. `include/shyake.h` is kept byte-identical to upstream.

## Port deltas vs. upstream

Direct Win32 replacement, no `#ifdef _WIN32` (fork policy):

| Upstream | Port |
|---|---|
| OpenSSL EVP ChaCha20-Poly1305 | mbedTLS `mbedtls_chachapoly_*` |
| OpenSSL `SHA256`/`SHA1` | shims in `shyake_crypto.c` over mbedTLS |
| `EVP_PBE_scrypt` | `scrypt_kdf` (RFC 7914) in `shyake_crypto.c`, PBKDF2 via mbedTLS |
| `EVP_EncodeBlock`/`EVP_DecodeBlock` | `mbedtls_base64_*` (decode re-pads unpadded input) |
| `/dev/urandom` | `fill_random` → `RtlGenRandom` (`SystemFunction036`, XP+) |
| `opendir`/`readdir` (`shyake_list_saved`) | `FindFirstFileW`/`FindNextFileW` (CP_ACP names, so CRT `fopen` still matches) |
| `stat` / `mkdir(path, 0700)` | `_stat64` / `_mkdir` (0700 semantics via %APPDATA% per-user ACL) |
| volatile-loop zeroize | `SecureZeroMemory` |
| `"%ld", time_t` | `"%lld", (long long)` (time_t is 64-bit, long is 32-bit on Windows) |

liboqs is statically linked with its RNG patched to `RtlGenRandom`
(build-time patch, not part of this tree).

## Verification

- `tests/test_crypto.c` (from upstream) must pass on x64.
- Ciphertexts must interoperate with the upstream libcrypto client
  (scrypt verified against RFC 7914 test vectors; ChaCha20-Poly1305
  against RFC 8439).
- `tests/test_interop.c`: bidirectional artifact exchange between
  the upstream libcrypto backend and this fork's mbedTLS backend
  (encrypted key file at production scrypt parameters, sealed
  blobs, base64). Verified passing in both directions at baseline
  `c6bf410`; rerun after every upstream sync or crypto change.
