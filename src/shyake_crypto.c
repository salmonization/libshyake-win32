#include "shyake_crypto.h"
#include <stdlib.h>
#include <string.h>
#include <windows.h>
#include <mbedtls/chachapoly.h>
#include <mbedtls/sha256.h>
#include <mbedtls/sha1.h>
#include <mbedtls/pkcs5.h>

int chacha20_poly1305_encrypt(
    const uint8_t *key, const uint8_t *nonce,
    const uint8_t *plaintext, size_t plaintext_len,
    const uint8_t *aad, size_t aad_len,
    uint8_t *ciphertext, uint8_t *mac)
{
    mbedtls_chachapoly_context ctx;
    mbedtls_chachapoly_init(&ctx);

    int ret = -1;
    if (mbedtls_chachapoly_setkey(&ctx, key) != 0)
        goto out;
    if (mbedtls_chachapoly_encrypt_and_tag(&ctx, plaintext_len,
        nonce, aad, aad_len, plaintext, ciphertext, mac) != 0)
        goto out;
    ret = 0;
out:
    mbedtls_chachapoly_free(&ctx);
    return ret;
}

int chacha20_poly1305_decrypt(
    const uint8_t *key, const uint8_t *nonce,
    const uint8_t *ciphertext, size_t ciphertext_len,
    const uint8_t *aad, size_t aad_len,
    const uint8_t *mac,
    uint8_t *plaintext)
{
    mbedtls_chachapoly_context ctx;
    mbedtls_chachapoly_init(&ctx);

    int ret = -1;
    if (mbedtls_chachapoly_setkey(&ctx, key) != 0)
        goto out;
    if (mbedtls_chachapoly_auth_decrypt(&ctx, ciphertext_len,
        nonce, aad, aad_len, mac, ciphertext, plaintext) != 0)
        goto out;
    ret = 0;
out:
    mbedtls_chachapoly_free(&ctx);
    return ret;
}

unsigned char *
SHA256(const unsigned char *d, size_t n, unsigned char *md)
{
    if (mbedtls_sha256(d, n, md, 0) != 0)
        return NULL;
    return md;
}

unsigned char *
SHA1(const unsigned char *d, size_t n, unsigned char *md)
{
    if (mbedtls_sha1(d, n, md) != 0)
        return NULL;
    return md;
}

/* RtlGenRandom, available since XP */
BOOLEAN WINAPI SystemFunction036(PVOID buffer, ULONG length);

int
fill_random(uint8_t *buf, size_t len)
{
    return SystemFunction036(buf, (ULONG)len) ? 1 : 0;
}

/* ------------------------------------------------------------------ */
/* scrypt (RFC 7914)                                                  */
/* ------------------------------------------------------------------ */

static uint32_t
rotl32(uint32_t v, int c)
{
    return (v << c) | (v >> (32 - c));
}

/* Salsa20/8 core over 64 bytes, in-place */
static void
salsa20_8(uint32_t b[16])
{
    uint32_t x[16];
    memcpy(x, b, 64);
    for (int i = 0; i < 8; i += 2) {
        x[ 4] ^= rotl32(x[ 0] + x[12],  7);
        x[ 8] ^= rotl32(x[ 4] + x[ 0],  9);
        x[12] ^= rotl32(x[ 8] + x[ 4], 13);
        x[ 0] ^= rotl32(x[12] + x[ 8], 18);
        x[ 9] ^= rotl32(x[ 5] + x[ 1],  7);
        x[13] ^= rotl32(x[ 9] + x[ 5],  9);
        x[ 1] ^= rotl32(x[13] + x[ 9], 13);
        x[ 5] ^= rotl32(x[ 1] + x[13], 18);
        x[14] ^= rotl32(x[10] + x[ 6],  7);
        x[ 2] ^= rotl32(x[14] + x[10],  9);
        x[ 6] ^= rotl32(x[ 2] + x[14], 13);
        x[10] ^= rotl32(x[ 6] + x[ 2], 18);
        x[ 3] ^= rotl32(x[15] + x[11],  7);
        x[ 7] ^= rotl32(x[ 3] + x[15],  9);
        x[11] ^= rotl32(x[ 7] + x[ 3], 13);
        x[15] ^= rotl32(x[11] + x[ 7], 18);
        x[ 1] ^= rotl32(x[ 0] + x[ 3],  7);
        x[ 2] ^= rotl32(x[ 1] + x[ 0],  9);
        x[ 3] ^= rotl32(x[ 2] + x[ 1], 13);
        x[ 0] ^= rotl32(x[ 3] + x[ 2], 18);
        x[ 6] ^= rotl32(x[ 5] + x[ 4],  7);
        x[ 7] ^= rotl32(x[ 6] + x[ 5],  9);
        x[ 4] ^= rotl32(x[ 7] + x[ 6], 13);
        x[ 5] ^= rotl32(x[ 4] + x[ 7], 18);
        x[11] ^= rotl32(x[10] + x[ 9],  7);
        x[ 8] ^= rotl32(x[11] + x[10],  9);
        x[ 9] ^= rotl32(x[ 8] + x[11], 13);
        x[10] ^= rotl32(x[ 9] + x[ 8], 18);
        x[12] ^= rotl32(x[15] + x[14],  7);
        x[13] ^= rotl32(x[12] + x[15],  9);
        x[14] ^= rotl32(x[13] + x[12], 13);
        x[15] ^= rotl32(x[14] + x[13], 18);
    }
    for (int i = 0; i < 16; i++)
        b[i] += x[i];
}

/* BlockMix_salsa8: B (2r * 64B) -> Y, using X as 64B scratch */
static void
blockmix_salsa8(const uint32_t *b, uint32_t *y, uint32_t *x, uint32_t r)
{
    memcpy(x, &b[(2 * r - 1) * 16], 64);
    for (uint32_t i = 0; i < 2 * r; i++) {
        for (int j = 0; j < 16; j++)
            x[j] ^= b[i * 16 + j];
        salsa20_8(x);
        /* even blocks first, then odd (RFC 7914 shuffle) */
        uint32_t dst = (i / 2) + (i & 1) * r;
        memcpy(&y[dst * 16], x, 64);
    }
}

static uint32_t
integerify(const uint32_t *b, uint32_t r, uint32_t N)
{
    /* first LE word of last 64B block; N is a power of two */
    return b[(2 * r - 1) * 16] & (N - 1);
}

static void
romix(uint32_t *b, uint32_t r, uint32_t N, uint32_t *v, uint32_t *xy)
{
    uint32_t words = 32 * r;   /* 128*r bytes as u32 */
    uint32_t *y = xy;
    uint32_t *x = xy + words;  /* 64B scratch */

    for (uint32_t i = 0; i < N; i += 2) {
        memcpy(&v[i * words], b, words * 4);
        blockmix_salsa8(b, y, x, r);
        memcpy(&v[(i + 1) * words], y, words * 4);
        blockmix_salsa8(y, b, x, r);
    }
    for (uint32_t i = 0; i < N; i += 2) {
        uint32_t j = integerify(b, r, N);
        for (uint32_t k = 0; k < words; k++)
            b[k] ^= v[j * words + k];
        blockmix_salsa8(b, y, x, r);
        j = integerify(y, r, N);
        for (uint32_t k = 0; k < words; k++)
            y[k] ^= v[j * words + k];
        blockmix_salsa8(y, b, x, r);
    }
}

static int
pbkdf2_sha256(const uint8_t *pass, size_t pass_len,
              const uint8_t *salt, size_t salt_len,
              uint8_t *out, size_t out_len)
{
    return mbedtls_pkcs5_pbkdf2_hmac_ext(MBEDTLS_MD_SHA256,
        pass, pass_len, salt, salt_len, 1,
        (uint32_t)out_len, out) == 0 ? 0 : -1;
}

int
scrypt_kdf(const uint8_t *pass, size_t pass_len,
           const uint8_t *salt, size_t salt_len,
           uint32_t N, uint32_t r, uint32_t p,
           uint8_t *out, size_t out_len)
{
    if (N < 2 || (N & (N - 1)) != 0 || r == 0 || p == 0)
        return -1;
    if ((uint64_t)128 * r * p > 0x40000000 ||
        (uint64_t)128 * r * N > 0x80000000ULL)
        return -1;

    size_t blen = (size_t)128 * r * p;
    uint8_t *bbuf = malloc(blen);
    uint32_t *v = malloc((size_t)32 * r * N * 4);
    uint32_t *xy = malloc((size_t)32 * r * 4 + 64);
    int ret = -1;

    if (!bbuf || !v || !xy)
        goto out;
    if (pbkdf2_sha256(pass, pass_len, salt, salt_len, bbuf, blen) != 0)
        goto out;

    /* romix works on LE u32; bbuf is byte-aligned, convert per block */
    uint32_t words = 32 * r;
    uint32_t *block = malloc(words * 4);
    if (!block)
        goto out;

    for (uint32_t i = 0; i < p; i++) {
        uint8_t *bp = bbuf + (size_t)i * 128 * r;
        for (uint32_t k = 0; k < words; k++)
            block[k] = (uint32_t)bp[k * 4]
                     | ((uint32_t)bp[k * 4 + 1] << 8)
                     | ((uint32_t)bp[k * 4 + 2] << 16)
                     | ((uint32_t)bp[k * 4 + 3] << 24);
        romix(block, r, N, v, xy);
        for (uint32_t k = 0; k < words; k++) {
            bp[k * 4]     = (uint8_t)(block[k]);
            bp[k * 4 + 1] = (uint8_t)(block[k] >> 8);
            bp[k * 4 + 2] = (uint8_t)(block[k] >> 16);
            bp[k * 4 + 3] = (uint8_t)(block[k] >> 24);
        }
    }
    free(block);

    ret = pbkdf2_sha256(pass, pass_len, bbuf, blen, out, out_len);
out:
    if (bbuf) SecureZeroMemory(bbuf, blen);
    free(bbuf);
    free(v);
    free(xy);
    return ret;
}
