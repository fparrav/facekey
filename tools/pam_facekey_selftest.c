/*
 * pam_facekey_selftest.c
 * facekey (tools)
 *
 * Offline self-test for the PAM module's ask path against a fake Facekey server on a
 * Unix socket: only an approved answer from a verified peer with this request's nonce
 * returns PAM_SUCCESS; decline, no server, an impostor with the wrong signature, a wrong
 * nonce, a timeout and malformed answers all return PAM_IGNORE, and an unverified peer
 * is never sent the request.
 * The test binary plays Facekey, so it is ad-hoc signed with the identifier the
 * "genuine" requirement names. This project has no test target, so it compiles standalone:
 *
 *     clang -std=c11 -Wall -Wextra -o /private/tmp/pam_facekey_selftest tools/pam_facekey_selftest.c -framework Security -framework CoreFoundation -lpam && codesign -s - -f -i com.fparrav.facekey.pamtest /private/tmp/pam_facekey_selftest && /private/tmp/pam_facekey_selftest
 *
 * Prints PASS/FAIL per check; exits 0 when every check passes, 1 otherwise.
 */

#include "../sudo-pam/pam_facekey.c"

#include <pthread.h>
#include <signal.h>
#include <sys/stat.h>

#define GENUINE "identifier \"com.fparrav.facekey.pamtest\""
#define IMPOSTOR "identifier \"com.example.not.facekey\""

static int failures;

static void check(int cond, const char *name) {
    printf("%s: %s\n", cond ? "PASS" : "FAIL", name);
    if (!cond) failures++;
}

typedef enum {
    SERVE_APPROVE,
    SERVE_IGNORE,
    SERVE_WRONG_NONCE,
    SERVE_SILENT,
    SERVE_OVERSIZE,
    SERVE_GARBAGE,
    SERVE_SHORT,
    SERVE_EXTRA_KEY,
} serve_mode;

typedef struct {
    int listen_fd;
    serve_mode mode;
    int request_seen;
    char request_nonce[64];
} fake_server;

static void send_frame(int fd, const char *json) {
    uint8_t header[4];
    size_t len = strlen(json);
    header[0] = (uint8_t)(len >> 24);
    header[1] = (uint8_t)(len >> 16);
    header[2] = (uint8_t)(len >> 8);
    header[3] = (uint8_t)len;
    (void)write(fd, header, 4);
    (void)write(fd, json, len);
}

static void *serve(void *arg) {
    fake_server *server = arg;
    int fd = accept(server->listen_fd, NULL, NULL);
    if (fd < 0) return NULL;
    struct timeval timeout = { 1, 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof timeout);

    uint8_t header[4];
    if (read(fd, header, 4) == 4) {
        long len = fk_frame_length(header);
        static uint8_t body[FK_MAX_FRAME + 1];
        ssize_t got = 0;
        while (len > 0 && got < len) {
            ssize_t n = read(fd, body + got, (size_t)(len - got));
            if (n <= 0) break;
            got += n;
        }
        if (len > 0 && got == len) {
            body[len] = '\0';
            const char *at = strstr((const char *)body, "\"nonce\":\"");
            if (at != NULL) {
                at += 9;
                const char *end = strchr(at, '"');
                if (end != NULL && (size_t)(end - at) < sizeof server->request_nonce) {
                    memcpy(server->request_nonce, at, (size_t)(end - at));
                    server->request_nonce[end - at] = '\0';
                    server->request_seen = 1;
                }
            }
        }
    }

    char json[256];
    switch (server->mode) {
    case SERVE_APPROVE:
        snprintf(json, sizeof json, "{\"nonce\":\"%s\",\"decision\":\"approve\"}", server->request_nonce);
        send_frame(fd, json);
        break;
    case SERVE_IGNORE:
        snprintf(json, sizeof json, "{\"nonce\":\"%s\",\"decision\":\"ignore\"}", server->request_nonce);
        send_frame(fd, json);
        break;
    case SERVE_WRONG_NONCE:
        send_frame(fd, "{\"nonce\":\"00000000000000000000000000000000\",\"decision\":\"approve\"}");
        break;
    case SERVE_EXTRA_KEY:
        snprintf(json, sizeof json, "{\"nonce\":\"%s\",\"decision\":\"approve\",\"extra\":\"x\"}", server->request_nonce);
        send_frame(fd, json);
        break;
    case SERVE_OVERSIZE: {
        const uint8_t huge[4] = { 0x00, 0x01, 0x00, 0x01 };
        (void)write(fd, huge, 4);
        break;
    }
    case SERVE_GARBAGE:
        send_frame(fd, "not json at all");
        break;
    case SERVE_SHORT: {
        const uint8_t partial[2] = { 0x00, 0x00 };
        (void)write(fd, partial, 2);
        break;
    }
    case SERVE_SILENT:
        usleep(1500 * 1000); /* outlasts the module's wait without ever answering */
        break;
    }
    close(fd);
    return NULL;
}

static char scratch_dir[64];
/* How long the module itself took in the last case, without waiting for the server thread to wind down. */
static long last_ask_ms;

static int start_server(fake_server *server, pthread_t *thread, char *path, size_t path_cap, serve_mode mode) {
    snprintf(path, path_cap, "%s/s%d.sock", scratch_dir, rand() % 100000);
    unlink(path);
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof addr);
    addr.sun_family = AF_UNIX;
    strcpy(addr.sun_path, path);
    if (fd < 0 || bind(fd, (struct sockaddr *)&addr, sizeof addr) != 0 || listen(fd, 4) != 0) return -1;
    memset(server, 0, sizeof *server);
    server->listen_fd = fd;
    server->mode = mode;
    return pthread_create(thread, NULL, serve, server);
}

/* Runs one case: a fake server in `mode`, the module asking with `requirement`, `uid_offset` added to the peer's expected uid. */
static int run_case(serve_mode mode, const char *requirement, int uid_offset, int wait_ms, fake_server *out_server) {
    fake_server server;
    pthread_t thread;
    char path[128];
    if (start_server(&server, &thread, path, sizeof path, mode) != 0) return -99;

    const int32_t pids[] = { 100, 200 };
    const char *argv[] = { "sudo", "launchctl", "list" };
    fk_config cfg = { path, requirement, (uid_t)((int)getuid() + uid_offset), wait_ms };
    long asked_at = fk_now_ms();
    int result = fk_ask(&cfg, pids, 2, argv, 3);
    last_ask_ms = fk_now_ms() - asked_at;

    pthread_join(thread, NULL);
    close(server.listen_fd);
    unlink(path);
    if (out_server != NULL) *out_server = server;
    return result;
}

int main(void) {
    /* The fake server writes to clients that already hung up (an impostor is dropped). */
    signal(SIGPIPE, SIG_IGN);
    snprintf(scratch_dir, sizeof scratch_dir, "/private/tmp/pamtest_%d", (int)getpid());
    mkdir(scratch_dir, 0700);
    srand((unsigned)getpid());

    fake_server seen;
    int result = run_case(SERVE_APPROVE, GENUINE, 0, 3000, &seen);
    check(result == PAM_SUCCESS, "an approve with this request's nonce from a verified peer returns PAM_SUCCESS");
    check(seen.request_seen && strlen(seen.request_nonce) == FK_NONCE_BYTES * 2, "the verified peer received the request with a 32-character nonce");

    check(run_case(SERVE_IGNORE, GENUINE, 0, 3000, NULL) == PAM_IGNORE, "a decline returns PAM_IGNORE");

    check(run_case(SERVE_WRONG_NONCE, GENUINE, 0, 3000, NULL) == PAM_IGNORE, "an approve with another nonce returns PAM_IGNORE");

    result = run_case(SERVE_APPROVE, IMPOSTOR, 0, 3000, &seen);
    check(result == PAM_IGNORE, "an impostor with the wrong signature returns PAM_IGNORE even when it approves");
    check(!seen.request_seen, "an unverified peer is never sent the request");

    result = run_case(SERVE_APPROVE, GENUINE, 1, 3000, &seen);
    check(result == PAM_IGNORE && !seen.request_seen, "a peer running as another user is refused before the request is sent");

    /* Nothing to verify against means it never even connects, so there is no server to run. */
    fk_config unverifiable = { "/private/tmp/pamtest_no_such_socket", NULL, getuid(), 500 };
    check(fk_ask(&unverifiable, NULL, 0, NULL, 0) == PAM_IGNORE, "no requirement to verify against returns PAM_IGNORE");

    result = run_case(SERVE_SILENT, GENUINE, 0, 400, NULL);
    check(result == PAM_IGNORE && last_ask_ms >= 350 && last_ask_ms < 1200, "a server that never answers times out with PAM_IGNORE");

    check(run_case(SERVE_OVERSIZE, GENUINE, 0, 3000, NULL) == PAM_IGNORE, "an oversize frame header returns PAM_IGNORE");
    check(run_case(SERVE_GARBAGE, GENUINE, 0, 3000, NULL) == PAM_IGNORE, "a body that is not the answer JSON returns PAM_IGNORE");
    check(run_case(SERVE_SHORT, GENUINE, 0, 600, NULL) == PAM_IGNORE, "a short read returns PAM_IGNORE");
    check(run_case(SERVE_EXTRA_KEY, GENUINE, 0, 3000, NULL) == PAM_IGNORE, "an answer with an unexpected key returns PAM_IGNORE");

    fk_config nowhere = { "/private/tmp/pamtest_no_such_socket", GENUINE, getuid(), 500 };
    check(fk_ask(&nowhere, NULL, 0, NULL, 0) == PAM_IGNORE, "no server at the socket path returns PAM_IGNORE");
    fk_config no_path = { NULL, GENUINE, getuid(), 500 };
    check(fk_ask(&no_path, NULL, 0, NULL, 0) == PAM_IGNORE, "no socket path returns PAM_IGNORE");
    check(fk_ask(NULL, NULL, 0, NULL, 0) == PAM_IGNORE, "no configuration returns PAM_IGNORE");

    /* The entry point itself: no terminal on stdin, or no team id in this build, means ignore. */
    freopen("/dev/null", "r", stdin);
    check(pam_sm_authenticate(NULL, 0, 0, NULL) == PAM_IGNORE, "pam_sm_authenticate ignores when stdin is not a terminal");

    rmdir(scratch_dir);
    if (failures == 0) {
        printf("All pam_facekey self-tests passed.\n");
    } else {
        printf("%d pam_facekey check(s) FAILED.\n", failures);
    }
    return failures == 0 ? 0 : 1;
}
