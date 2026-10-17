/*
 * facekey_wire.h
 * facekey
 *
 * Wire format of the sudo approval channel between pam_facekey.so (client) and
 * the Facekey app (server): a 4-byte big-endian length, then a JSON body of at
 * most FK_MAX_FRAME bytes. Header-only, no malloc. Mirrors facekey/Sudo/SudoRequest.swift.
 */

#ifndef FACEKEY_WIRE_H
#define FACEKEY_WIRE_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define FK_MAX_FRAME 65536
/* Room kept for `],"uid":4294967295}` while argv entries are being added. */
#define FK_TAIL_RESERVE 20

/* Declared body length from a frame header, or -1 when it exceeds FK_MAX_FRAME. */
static inline long fk_frame_length(const uint8_t hdr[4]) {
    uint32_t length = ((uint32_t)hdr[0] << 24) | ((uint32_t)hdr[1] << 16) | ((uint32_t)hdr[2] << 8) | (uint32_t)hdr[3];
    return length > FK_MAX_FRAME ? -1 : (long)length;
}

/* Bounded writer; `overflow` latches once something no longer fits. */
typedef struct {
    uint8_t *p;
    size_t len;
    size_t limit;
    int overflow;
} fk_writer;

static inline void fk_put(fk_writer *w, const void *data, size_t n) {
    if (w->overflow || n > w->limit - w->len) {
        w->overflow = 1;
        return;
    }
    memcpy(w->p + w->len, data, n);
    w->len += n;
}

static inline void fk_putc(fk_writer *w, char c) {
    fk_put(w, &c, 1);
}

static inline void fk_put_uint(fk_writer *w, uint64_t v) {
    char digits[20];
    size_t n = 0;
    do {
        digits[n++] = (char)('0' + v % 10);
        v /= 10;
    } while (v != 0);
    while (n > 0) {
        fk_putc(w, digits[--n]);
    }
}

static inline void fk_put_int(fk_writer *w, int32_t v) {
    if (v < 0) {
        fk_putc(w, '-');
        fk_put_uint(w, (uint64_t)(-(int64_t)v));
    } else {
        fk_put_uint(w, (uint64_t)v);
    }
}

/* Length of the valid UTF-8 sequence at s (1 to 4), or 0 when invalid, truncated, overlong or a surrogate. */
static inline size_t fk_utf8_sequence(const uint8_t *s, size_t avail) {
    uint8_t c0 = s[0];
    size_t need;
    uint8_t lo = 0x80, hi = 0xBF;
    if (c0 < 0x80) {
        return 1;
    } else if (c0 >= 0xC2 && c0 <= 0xDF) {
        need = 1;
    } else if (c0 >= 0xE0 && c0 <= 0xEF) {
        need = 2;
        if (c0 == 0xE0) lo = 0xA0;
        if (c0 == 0xED) hi = 0x9F;
    } else if (c0 >= 0xF0 && c0 <= 0xF4) {
        need = 3;
        if (c0 == 0xF0) lo = 0x90;
        if (c0 == 0xF4) hi = 0x8F;
    } else {
        return 0;
    }
    if (avail < need + 1) return 0;
    if (s[1] < lo || s[1] > hi) return 0;
    for (size_t i = 2; i <= need; i++) {
        if (s[i] < 0x80 || s[i] > 0xBF) return 0;
    }
    return need + 1;
}

/* Writes `s` as a quoted JSON string; invalid UTF-8 bytes become U+FFFD. */
static inline void fk_put_string(fk_writer *w, const char *s) {
    static const char hex[] = "0123456789abcdef";
    const uint8_t *bytes = (const uint8_t *)s;
    size_t total = strlen(s);
    size_t i = 0;
    fk_putc(w, '"');
    while (i < total) {
        uint8_t c = bytes[i];
        if (c == '"' || c == '\\') {
            fk_putc(w, '\\');
            fk_putc(w, (char)c);
            i++;
        } else if (c == '\n') {
            fk_put(w, "\\n", 2);
            i++;
        } else if (c == '\r') {
            fk_put(w, "\\r", 2);
            i++;
        } else if (c == '\t') {
            fk_put(w, "\\t", 2);
            i++;
        } else if (c < 0x20) {
            fk_put(w, "\\u00", 4);
            fk_putc(w, hex[c >> 4]);
            fk_putc(w, hex[c & 0x0F]);
            i++;
        } else {
            size_t seq = fk_utf8_sequence(bytes + i, total - i);
            if (seq == 0) {
                fk_put(w, "\\ufffd", 6);
                i++;
            } else {
                fk_put(w, bytes + i, seq);
                i += seq;
            }
        }
    }
    fk_putc(w, '"');
}

/*
 * Builds the whole request frame (length prefix plus JSON) into buf and returns its
 * size, or 0 when it cannot fit. When the full argv does not fit, only the leading
 * entries that fit whole are sent; nonce, pids and uid are always kept.
 */
static inline size_t fk_build_request(uint8_t *buf, size_t cap, const char *nonce, const int32_t *pids, size_t npids,
                                      const char *const *argv, size_t argc, uint32_t uid) {
    if (buf == NULL || nonce == NULL || cap < 4) return 0;
    size_t full = cap - 4 < FK_MAX_FRAME ? cap - 4 : FK_MAX_FRAME;
    if (full < FK_TAIL_RESERVE) return 0;

    fk_writer w = { buf + 4, 0, full, 0 };
    fk_put(&w, "{\"nonce\":", 9);
    fk_put_string(&w, nonce);
    fk_put(&w, ",\"ancestorPIDs\":[", 17);
    for (size_t i = 0; i < npids; i++) {
        if (i > 0) fk_putc(&w, ',');
        fk_put_int(&w, pids[i]);
    }
    fk_put(&w, "],\"argv\":[", 10);
    if (w.overflow) return 0;

    w.limit = full - FK_TAIL_RESERVE;
    for (size_t i = 0; i < argc; i++) {
        size_t checkpoint = w.len;
        if (i > 0) fk_putc(&w, ',');
        fk_put_string(&w, argv[i] != NULL ? argv[i] : "");
        if (w.overflow) {
            w.len = checkpoint;
            w.overflow = 0;
            break;
        }
    }

    w.limit = full;
    fk_put(&w, "],\"uid\":", 8);
    fk_put_uint(&w, uid);
    fk_putc(&w, '}');
    if (w.overflow) return 0;

    buf[0] = (uint8_t)((w.len >> 24) & 0xFF);
    buf[1] = (uint8_t)((w.len >> 16) & 0xFF);
    buf[2] = (uint8_t)((w.len >> 8) & 0xFF);
    buf[3] = (uint8_t)(w.len & 0xFF);
    return 4 + w.len;
}

static inline void fk_skip_space(const uint8_t *body, size_t len, size_t *i) {
    while (*i < len && (body[*i] == ' ' || body[*i] == '\t' || body[*i] == '\n' || body[*i] == '\r')) {
        (*i)++;
    }
}

/* Reads `"text"` with no backslash or control byte inside; leaves *i after the closing quote. */
static inline int fk_scan_string(const uint8_t *body, size_t len, size_t *i, const uint8_t **start, size_t *slen) {
    if (*i >= len || body[*i] != '"') return -1;
    size_t from = ++(*i);
    while (*i < len && body[*i] != '"') {
        if (body[*i] == '\\' || body[*i] < 0x20) return -1;
        (*i)++;
    }
    if (*i >= len) return -1;
    *start = body + from;
    *slen = *i - from;
    (*i)++;
    return 0;
}

/*
 * Parses an answer body (JSON only, no length prefix) into its nonce and decision.
 * Accepts a flat object with exactly the keys "nonce" and "decision" in any order.
 * Returns 0 on success (*approve is 1 for "approve", 0 for "ignore"), -1 for anything else.
 */
static inline int fk_parse_answer(const uint8_t *body, size_t len, char *nonce_out, size_t nonce_cap, int *approve) {
    if (body == NULL || nonce_out == NULL || approve == NULL || nonce_cap == 0) return -1;
    nonce_out[0] = '\0';
    if (len == 0 || len > FK_MAX_FRAME) return -1;

    size_t i = 0;
    int seen_nonce = 0, seen_decision = 0, decision = -1;
    fk_skip_space(body, len, &i);
    if (i >= len || body[i] != '{') return -1;
    i++;
    for (;;) {
        const uint8_t *key, *value;
        size_t key_len, value_len;
        fk_skip_space(body, len, &i);
        if (fk_scan_string(body, len, &i, &key, &key_len) != 0) return -1;
        fk_skip_space(body, len, &i);
        if (i >= len || body[i] != ':') return -1;
        i++;
        fk_skip_space(body, len, &i);
        if (fk_scan_string(body, len, &i, &value, &value_len) != 0) return -1;

        if (key_len == 5 && memcmp(key, "nonce", 5) == 0) {
            if (seen_nonce || value_len > nonce_cap - 1) return -1;
            memcpy(nonce_out, value, value_len);
            nonce_out[value_len] = '\0';
            seen_nonce = 1;
        } else if (key_len == 8 && memcmp(key, "decision", 8) == 0) {
            if (seen_decision) return -1;
            if (value_len == 7 && memcmp(value, "approve", 7) == 0) {
                decision = 1;
            } else if (value_len == 6 && memcmp(value, "ignore", 6) == 0) {
                decision = 0;
            } else {
                return -1;
            }
            seen_decision = 1;
        } else {
            return -1;
        }

        fk_skip_space(body, len, &i);
        if (i >= len) return -1;
        if (body[i] == ',') {
            i++;
            continue;
        }
        if (body[i] == '}') {
            i++;
            break;
        }
        return -1;
    }
    fk_skip_space(body, len, &i);
    if (i != len || !seen_nonce || !seen_decision) {
        nonce_out[0] = '\0';
        return -1;
    }
    *approve = decision;
    return 0;
}

#endif /* FACEKEY_WIRE_H */
