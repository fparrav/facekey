/*
 * pam_facekey.c
 * facekey
 *
 * PAM module that asks the running Facekey app to approve a `sudo` request. It is
 * listed as `auth sufficient` ahead of pam_tid.so and fails open: PAM_SUCCESS only
 * for an approved answer from a verified Facekey carrying this request's nonce,
 * PAM_IGNORE for everything else, so `sudo` falls through to its normal methods.
 * It never prints, never logs the command and never touches the password.
 */

#include <security/pam_appl.h>
#include <security/pam_modules.h>

#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>

#include <crt_externs.h>
#include <errno.h>
#include <fcntl.h>
#include <libproc.h>
#include <poll.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>

#include "facekey_wire.h"

/* Diagnostic builds only (-DFACEKEY_PAM_TRACE): appends the stage reached to a world-readable file. Never in a shipped module. */
#ifdef FACEKEY_PAM_TRACE
static void fk_trace(const char *stage, long detail) {
    FILE *out = fopen("/private/tmp/facekey_pam_trace.log", "a");
    if (out == NULL) return;
    fprintf(out, "pid=%d uid=%d euid=%d %s %ld\n", (int)getpid(), (int)getuid(), (int)geteuid(), stage, detail);
    fclose(out);
}
#define FK_TRACE(stage, detail) fk_trace((stage), (long)(detail))
#else
#define FK_TRACE(stage, detail) ((void)0)
#endif

/* Facekey's signing identity, injected by sudo-pam/build.sh. With no team id the module cannot verify the app and ignores everything. */
#ifndef FACEKEY_BUNDLE_ID
#define FACEKEY_BUNDLE_ID "com.fparrav.facekey"
#endif
#ifndef FACEKEY_TEAM_ID
#define FACEKEY_TEAM_ID ""
#endif

/* Longer than the app's own request limit, so the app always answers (or times out) first. */
#define FK_WAIT_MS 60000
#define FK_CONNECT_MS 1000
#define FK_SEND_MS 5000
#define FK_MAX_ANCESTORS 32
#define FK_NONCE_BYTES 16

typedef struct {
    const char *socket_path;
    /* Code requirement the socket peer must satisfy. */
    const char *requirement;
    /* The user running sudo; the peer must belong to the same user. */
    uid_t uid;
    int wait_ms;
} fk_config;

static long fk_now_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (long)tv.tv_sec * 1000 + (long)(tv.tv_usec / 1000);
}

/* Waits for `events` until the deadline; returns 1 when ready, 0 on timeout or error. Interrupted waits resume. */
static int fk_wait(int fd, short events, long deadline_ms) {
    for (;;) {
        long remaining = deadline_ms - fk_now_ms();
        if (remaining <= 0) return 0;
        struct pollfd pfd = { fd, events, 0 };
        int rc = poll(&pfd, 1, (int)remaining);
        if (rc > 0) return (pfd.revents & (events | POLLHUP)) != 0;
        if (rc < 0 && errno == EINTR) continue;
        return 0;
    }
}

static int fk_write_all(int fd, const uint8_t *data, size_t len, long deadline_ms) {
    size_t done = 0;
    while (done < len) {
        if (!fk_wait(fd, POLLOUT, deadline_ms)) return -1;
        ssize_t n = write(fd, data + done, len - done);
        if (n > 0) {
            done += (size_t)n;
        } else if (n < 0 && (errno == EINTR || errno == EAGAIN)) {
            continue;
        } else {
            return -1;
        }
    }
    return 0;
}

/* Reads exactly len bytes; a closed or silent peer is a failure. */
static int fk_read_all(int fd, uint8_t *data, size_t len, long deadline_ms) {
    size_t done = 0;
    while (done < len) {
        if (!fk_wait(fd, POLLIN, deadline_ms)) return -1;
        ssize_t n = read(fd, data + done, len - done);
        if (n > 0) {
            done += (size_t)n;
        } else if (n < 0 && (errno == EINTR || errno == EAGAIN)) {
            continue;
        } else {
            return -1;
        }
    }
    return 0;
}

static int fk_connect(const char *path) {
    struct sockaddr_un addr;
    if (path == NULL || strlen(path) >= sizeof addr.sun_path) return -1;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    int on = 1;
    if (setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on) != 0 || fcntl(fd, F_SETFD, FD_CLOEXEC) != 0 ||
        fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != 0) {
        close(fd);
        return -1;
    }
    memset(&addr, 0, sizeof addr);
    addr.sun_family = AF_UNIX;
    strcpy(addr.sun_path, path);
    if (connect(fd, (struct sockaddr *)&addr, sizeof addr) != 0) {
        int connected = 0;
        if (errno == EINPROGRESS && fk_wait(fd, POLLOUT, fk_now_ms() + FK_CONNECT_MS)) {
            int err = 0;
            socklen_t err_len = sizeof err;
            connected = getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &err_len) == 0 && err == 0;
        }
        if (!connected) {
            close(fd);
            return -1;
        }
    }
    return fd;
}

/* True only when the process on the other end is signed as Facekey and runs as the same user. */
static int fk_peer_is_facekey(int fd, const char *requirement, uid_t uid) {
    if (requirement == NULL) return 0;
    uid_t peer_uid;
    gid_t peer_gid;
    if (getpeereid(fd, &peer_uid, &peer_gid) != 0 || peer_uid != uid) return 0;

    audit_token_t token;
    socklen_t token_len = sizeof token;
    if (getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &token_len) != 0 || token_len != sizeof token) return 0;

    int trusted = 0;
    CFDataRef token_data = CFDataCreate(NULL, (const UInt8 *)&token, (CFIndex)sizeof token);
    CFStringRef requirement_text = CFStringCreateWithCString(NULL, requirement, kCFStringEncodingUTF8);
    CFDictionaryRef attributes = NULL;
    SecCodeRef code = NULL;
    SecRequirementRef parsed = NULL;
    if (token_data != NULL && requirement_text != NULL) {
        const void *keys[] = { kSecGuestAttributeAudit };
        const void *values[] = { token_data };
        attributes = CFDictionaryCreate(NULL, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    }
    if (attributes != NULL && SecCodeCopyGuestWithAttributes(NULL, attributes, kSecCSDefaultFlags, &code) == errSecSuccess &&
        SecRequirementCreateWithString(requirement_text, kSecCSDefaultFlags, &parsed) == errSecSuccess) {
        trusted = SecCodeCheckValidity(code, kSecCSDefaultFlags, parsed) == errSecSuccess;
    }
    if (parsed != NULL) CFRelease(parsed);
    if (code != NULL) CFRelease(code);
    if (attributes != NULL) CFRelease(attributes);
    if (requirement_text != NULL) CFRelease(requirement_text);
    if (token_data != NULL) CFRelease(token_data);
    return trusted;
}

static int fk_make_nonce(char out[FK_NONCE_BYTES * 2 + 1]) {
    static const char hex[] = "0123456789abcdef";
    uint8_t raw[FK_NONCE_BYTES];
    arc4random_buf(raw, sizeof raw);
    for (size_t i = 0; i < sizeof raw; i++) {
        out[i * 2] = hex[raw[i] >> 4];
        out[i * 2 + 1] = hex[raw[i] & 0x0F];
    }
    out[FK_NONCE_BYTES * 2] = '\0';
    return 0;
}

/* Compares in constant time; the nonce is not secret from the peer, but there is no reason to leak how much matched. */
static int fk_same_nonce(const char *a, const char *b) {
    size_t la = strlen(a), lb = strlen(b);
    if (la != lb) return 0;
    unsigned char diff = 0;
    for (size_t i = 0; i < la; i++) diff |= (unsigned char)(a[i] ^ b[i]);
    return diff == 0;
}

/*
 * Asks Facekey over the socket. PAM_SUCCESS only when the peer is verified and sends an
 * "approve" answer carrying the nonce of this request; PAM_IGNORE on every other outcome.
 */
static int fk_ask(const fk_config *cfg, const int32_t *pids, size_t npids, const char *const *argv, size_t argc) {
    if (cfg == NULL || cfg->socket_path == NULL || cfg->requirement == NULL) return PAM_IGNORE;

    int result = PAM_IGNORE;
    uint8_t *frame = malloc(FK_MAX_FRAME + 4);
    int fd = fk_connect(cfg->socket_path);
    FK_TRACE("connect", fd < 0 ? -errno : fd);
    if (frame == NULL || fd < 0) goto out;

    /* The peer must prove it is Facekey before it is told what is being run. */
    if (!fk_peer_is_facekey(fd, cfg->requirement, cfg->uid)) {
        FK_TRACE("peer-not-facekey", 0);
        goto out;
    }
    FK_TRACE("peer-verified", 0);

    char nonce[FK_NONCE_BYTES * 2 + 1];
    fk_make_nonce(nonce);
    size_t request_len = fk_build_request(frame, FK_MAX_FRAME + 4, nonce, pids, npids, argv, argc, (uint32_t)cfg->uid);
    if (request_len == 0 || fk_write_all(fd, frame, request_len, fk_now_ms() + FK_SEND_MS) != 0) {
        FK_TRACE("send-failed", request_len);
        goto out;
    }
    FK_TRACE("sent", request_len);

    long deadline = fk_now_ms() + cfg->wait_ms;
    uint8_t header[4];
    if (fk_read_all(fd, header, sizeof header, deadline) != 0) {
        FK_TRACE("no-answer", 0);
        goto out;
    }
    long body_len = fk_frame_length(header);
    if (body_len <= 0) goto out;
    if (fk_read_all(fd, frame, (size_t)body_len, deadline) != 0) goto out;

    char answered_nonce[FK_NONCE_BYTES * 2 + 1];
    int approve = 0;
    if (fk_parse_answer(frame, (size_t)body_len, answered_nonce, sizeof answered_nonce, &approve) != 0) goto out;
    if (approve == 1 && fk_same_nonce(nonce, answered_nonce)) result = PAM_SUCCESS;
    FK_TRACE("answer-approve", approve);

out:
    if (fd >= 0) close(fd);
    free(frame);
    return result;
}

/* Parent pids of this process, nearest first, ending at launchd or after FK_MAX_ANCESTORS. */
static size_t fk_collect_ancestors(int32_t *out, size_t cap) {
    size_t count = 0;
    pid_t pid = getppid();
    while (pid > 1 && count < cap) {
        out[count++] = (int32_t)pid;
        struct proc_bsdinfo info;
        if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof info) != (int)sizeof info) break;
        pid = (pid_t)info.pbi_ppid;
    }
    return count;
}

/* A sudo reached over ssh belongs to a remote session, never to the person at this Mac. The sshd ancestor is
 * the reliable signal; the environment variables only catch the plain case, since a user can unset them. */
static int fk_is_remote_session(const int32_t *pids, size_t npids) {
    if (getenv("SSH_CONNECTION") != NULL || getenv("SSH_CLIENT") != NULL || getenv("SSH_TTY") != NULL) return 1;
    for (size_t i = 0; i < npids; i++) {
        char name[64];
        if (proc_name(pids[i], name, sizeof name) > 0 && strncmp(name, "sshd", 4) == 0) return 1;
    }
    return 0;
}

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc, const char **argv) {
    (void)pamh;
    (void)flags;
    (void)argc;
    (void)argv;

    FK_TRACE("enter", isatty(STDIN_FILENO));
    if (!isatty(STDIN_FILENO)) return PAM_IGNORE;
    int32_t pids[FK_MAX_ANCESTORS];
    size_t npids = fk_collect_ancestors(pids, FK_MAX_ANCESTORS);
    if (fk_is_remote_session(pids, npids)) {
        FK_TRACE("remote-session", npids);
        return PAM_IGNORE;
    }
    /* Real uid: sudo is setuid root, so this is the user who typed the command. */
    uid_t uid = getuid();
    if (uid == 0 || FACEKEY_TEAM_ID[0] == '\0') {
        FK_TRACE("uid0-or-no-team", uid);
        return PAM_IGNORE;
    }

    struct passwd pwd, *found = NULL;
    char pwbuf[1024];
    if (getpwuid_r(uid, &pwd, pwbuf, sizeof pwbuf, &found) != 0 || found == NULL || pwd.pw_dir == NULL) return PAM_IGNORE;

    char socket_path[sizeof(((struct sockaddr_un *)0)->sun_path)];
    int path_len = snprintf(socket_path, sizeof socket_path, "%s/Library/Application Support/facekey/sudo/approval.sock", pwd.pw_dir);
    if (path_len < 0 || (size_t)path_len >= sizeof socket_path) return PAM_IGNORE;

    char requirement[256];
    int req_len = snprintf(requirement, sizeof requirement,
                           "identifier \"%s\" and anchor apple generic and certificate leaf[subject.OU] = \"%s\"",
                           FACEKEY_BUNDLE_ID, FACEKEY_TEAM_ID);
    if (req_len < 0 || (size_t)req_len >= sizeof requirement) return PAM_IGNORE;

    /* sudo's own argv, as typed. */
    int host_argc = *_NSGetArgc();
    char **host_argv = *_NSGetArgv();
    size_t nargs = host_argv != NULL && host_argc > 0 ? (size_t)host_argc : 0;

    fk_config cfg = { socket_path, requirement, uid, FK_WAIT_MS };
    return fk_ask(&cfg, pids, npids, (const char *const *)host_argv, nargs);
}

PAM_EXTERN int pam_sm_setcred(pam_handle_t *pamh, int flags, int argc, const char **argv)
{ (void)pamh; (void)flags; (void)argc; (void)argv; return PAM_IGNORE; }

PAM_EXTERN int pam_sm_acct_mgmt(pam_handle_t *pamh, int flags, int argc, const char **argv)
{ (void)pamh; (void)flags; (void)argc; (void)argv; return PAM_IGNORE; }

PAM_EXTERN int pam_sm_chauthtok(pam_handle_t *pamh, int flags, int argc, const char **argv)
{ (void)pamh; (void)flags; (void)argc; (void)argv; return PAM_IGNORE; }

PAM_EXTERN int pam_sm_open_session(pam_handle_t *pamh, int flags, int argc, const char **argv)
{ (void)pamh; (void)flags; (void)argc; (void)argv; return PAM_IGNORE; }

PAM_EXTERN int pam_sm_close_session(pam_handle_t *pamh, int flags, int argc, const char **argv)
{ (void)pamh; (void)flags; (void)argc; (void)argv; return PAM_IGNORE; }
