#ifndef SHYAKE_CRYPTO_H
#define SHYAKE_CRYPTO_H

#include <stddef.h>
#include <stdint.h>

#define CHACHA20_KEY_SIZE 32
#define CHACHA20_NONCE_SIZE 12
#define POLY1305_MAC_SIZE 16

#define SHA256_DIGEST_LENGTH 32
#define SHA_DIGEST_LENGTH 20

int chacha20_poly1305_encrypt(
    const uint8_t *key, const uint8_t *nonce,
    const uint8_t *plaintext, size_t plaintext_len,
    const uint8_t *aad, size_t aad_len,
    uint8_t *ciphertext, uint8_t *mac);

int chacha20_poly1305_decrypt(
    const uint8_t *key, const uint8_t *nonce,
    const uint8_t *ciphertext, size_t ciphertext_len,
    const uint8_t *aad, size_t aad_len,
    const uint8_t *mac,
    uint8_t *plaintext);

/* one-shot digests, OpenSSL-compatible signatures */
unsigned char *SHA256(const unsigned char *d, size_t n,
                      unsigned char *md);
unsigned char *SHA1(const unsigned char *d, size_t n,
                    unsigned char *md);

/* CSPRNG via RtlGenRandom; 1 on success, 0 on failure */
int fill_random(uint8_t *buf, size_t len);

/* scrypt (RFC 7914) over mbedTLS PBKDF2-HMAC-SHA256 */
int scrypt_kdf(const uint8_t *pass, size_t pass_len,
               const uint8_t *salt, size_t salt_len,
               uint32_t N, uint32_t r, uint32_t p,
               uint8_t *out, size_t out_len);

#endif // SHYAKE_CRYPTO_H
