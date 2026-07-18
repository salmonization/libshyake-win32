/*
 * Protocol e2e against a running instance (e.g. wrangler dev
 * --local): generate keys, register, send to self, check inbox,
 * fetch, verify body, burn. Exercises the full client wire path
 * without a GUI.
 *
 * usage: test_e2e <instance_url> <config_dir> [username]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "shyake.h"

static const char *BODY = "e2e body \xe7\x96\x8e\xe9\x85\x92\n";
static const char *SUBJ = "e2e subject";

int main(int argc, char **argv)
{
    if (argc < 3) {
        fprintf(stderr,
                "usage: %s <instance_url> <config_dir> [username]\n",
                argv[0]);
        return 2;
    }
    char user[64];
    if (argc > 3)
        snprintf(user, sizeof(user), "%s", argv[3]);
    else
        snprintf(user, sizeof(user), "e2e%lld",
                 (long long)time(NULL) % 100000000);

    shyake_config cfg = {
        .instance_url = argv[1],
        .config_dir   = argv[2],
        .username     = user,
    };
    shyake_ctx *ctx = shyake_init_ctx(&cfg);
    if (!ctx) { puts("init FAIL"); return 1; }
    shyake_set_passphrase(ctx, "");

    if (shyake_generate_keys(ctx) != 0) {
        printf("keygen FAIL: %s\n", shyake_last_error(ctx));
        return 1;
    }
    puts("keygen ok");

    if (shyake_register(ctx, user) != SHYAKE_OK) {
        printf("register FAIL: %s\n", shyake_last_error(ctx));
        return 1;
    }
    printf("register ok (%s)\n", user);

    if (shyake_send(ctx, user, SUBJ, (const uint8_t *)BODY,
                    strlen(BODY)) != SHYAKE_OK) {
        printf("send FAIL: %s\n", shyake_last_error(ctx));
        return 1;
    }
    puts("send ok");

    shyake_mail_list *list = shyake_check(ctx, "inbox");
    if (!list || list->count < 1) {
        printf("check FAIL: %s\n", shyake_last_error(ctx));
        return 1;
    }
    if (!list->entries[0].subject ||
        strcmp(list->entries[0].subject, SUBJ) != 0) {
        printf("check subject FAIL: got '%s'\n",
               list->entries[0].subject ? list->entries[0].subject
                                        : "(null)");
        return 1;
    }
    char mail_id[256];
    snprintf(mail_id, sizeof(mail_id), "%s", list->entries[0].mail_id);
    shyake_free_mail_list(list);
    puts("check ok");

    shyake_mail_detail *d = shyake_fetch(ctx, mail_id);
    if (!d || !d->body || strcmp(d->body, BODY) != 0 ||
        !d->subject || strcmp(d->subject, SUBJ) != 0) {
        printf("fetch FAIL: %s\n", ctx ? shyake_last_error(ctx) : "");
        return 1;
    }
    shyake_free_mail_detail(d);
    puts("fetch ok (body matches)");

    if (shyake_burn(ctx, mail_id) != SHYAKE_OK) {
        printf("burn FAIL: %s\n", shyake_last_error(ctx));
        return 1;
    }
    list = shyake_check(ctx, "inbox");
    if (list && list->count != 0) {
        puts("burn verify FAIL: mail still listed");
        return 1;
    }
    shyake_free_mail_list(list);
    puts("burn ok");

    shyake_free_ctx(ctx);
    puts("E2E OK");
    return 0;
}
