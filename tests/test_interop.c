/*
 * Cross-backend interop test. Build this driver twice:
 *   - against upstream client/src/lib (OpenSSL libcrypto)
 *   - against this fork's src/ (mbedTLS)
 * then run `A gen <dir>` followed by `B check <dir>` in both
 * directions. Covers the swapped surface: scrypt key files
 * (production N=65536), ChaCha20-Poly1305 sealed blobs, base64.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "lib_internal.h"
#include "shyake_crypto.h"

static const char *PASS = "correct horse battery staple";

static void mk_sk(uint8_t *sk) { for (int i = 0; i < 64; i++) sk[i] = (uint8_t)(i * 7 + 3); }
static void mk_key(uint8_t *k) { for (int i = 0; i < 32; i++) k[i] = (uint8_t)(200 - i); }
static const char *PT = "Interop test \xe4\xba\x92\xe6\x8f\x9b\xe6\x80\xa7";

static int write_text(const char *p, const char *s)
{
    FILE *f = fopen(p, "w");
    if (!f) return -1;
    fputs(s, f); fclose(f); return 0;
}
static char *read_text(const char *p)
{
    FILE *f = fopen(p, "r");
    if (!f) return NULL;
    static char buf[65536];
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    buf[n] = 0;
    while (n && (buf[n-1] == '\n')) buf[--n] = 0;
    fclose(f);
    return buf;
}

int main(int argc, char **argv)
{
    if (argc != 3) { fprintf(stderr, "usage: %s gen|check dir\n", argv[0]); return 2; }
    const char *dir = argv[2];
    char p1[512], p2[512], p3[512];
    snprintf(p1, sizeof(p1), "%s/sk.enc", dir);
    snprintf(p2, sizeof(p2), "%s/sealed.b64", dir);
    snprintf(p3, sizeof(p3), "%s/blob.b64", dir);

    uint8_t sk[64], key[32];
    mk_sk(sk); mk_key(key);
    uint8_t blob[256];
    for (int i = 0; i < 256; i++) blob[i] = (uint8_t)i;

    if (strcmp(argv[1], "gen") == 0) {
        if (save_sk_encrypted(p1, PASS, sk, 64) != 0) { puts("gen sk FAIL"); return 1; }
        char *sealed = encrypt_to_b64(key, (const uint8_t*)PT, strlen(PT));
        if (!sealed || write_text(p2, sealed) != 0) { puts("gen sealed FAIL"); return 1; }
        char *b64 = base64_encode(blob, 256);
        if (!b64 || write_text(p3, b64) != 0) { puts("gen b64 FAIL"); return 1; }
        puts("gen ok");
        return 0;
    }

    int fail = 0;
    shyake_config cfg = { .config_dir = "." };
    shyake_ctx *ctx = shyake_init_ctx(&cfg);
    shyake_set_passphrase(ctx, PASS);
    size_t skl;
    uint8_t *sk2 = load_sk_decrypted(ctx, p1, &skl);
    if (!sk2 || skl != 64 || memcmp(sk, sk2, 64) != 0) {
        printf("check sk FAIL (%s)\n", shyake_last_error(ctx)); fail = 1;
    } else puts("check sk ok");
    free(sk2);

    char *sealed = read_text(p2);
    char *pt = sealed ? decrypt_from_b64(key, sealed) : NULL;
    if (!pt || strcmp(pt, PT) != 0) { puts("check sealed FAIL"); fail = 1; }
    else puts("check sealed ok");
    free(pt);

    char *b64 = read_text(p3);
    size_t bl; uint8_t *back = b64 ? base64_decode(b64, &bl) : NULL;
    if (!back || bl != 256 || memcmp(back, blob, 256) != 0) {
        puts("check b64 decode FAIL"); fail = 1;
    } else puts("check b64 decode ok");
    free(back);
    char *b64b = base64_encode(blob, 256);
    if (!b64 || !b64b || strcmp(b64, b64b) != 0) { puts("check b64 encode FAIL"); fail = 1; }
    else puts("check b64 encode ok");
    free(b64b);

    shyake_free_ctx(ctx);
    puts(fail ? "INTEROP FAIL" : "INTEROP OK");
    return fail;
}
