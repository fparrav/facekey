//
//  sudo_socket_probe.swift
//  facekey (tools)
//
//  Standalone probe for the sudo approval socket: it starts a real SudoSocketServer
//  with a stub handler, connects as the current (non-root) user, and verifies the
//  server closes the connection before the handler can run — a non-root client must
//  never reach the approval handler.
//  This project has no test target, so this compiles as a standalone script against the real files:
//
//      /usr/bin/swiftc -O -parse-as-library -o /private/tmp/sudo_socket_probe facekey/Sudo/SudoRequest.swift facekey/Sudo/SudoSocketServer.swift tools/sudo_socket_probe.swift && /private/tmp/sudo_socket_probe
//
//  Run it as a normal user (it skips on purpose when root).
//  Prints PASS/FAIL per check; exits 0 when every check passes, 1 otherwise.
//

import Foundation
import Darwin

var failures = 0

func check(_ cond: Bool, _ name: String) {
    if cond {
        print("PASS: \(name)")
    } else {
        print("FAIL: \(name)")
        failures += 1
    }
}

/// Flipped by the stub handler so the probe can prove it never ran.
final class HandlerFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var set = false

    func mark() {
        lock.lock()
        defer { lock.unlock() }
        set = true
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return set
    }
}

/// File permission bits for a path, nil when the path is missing.
func modeBits(at path: String) -> Int16? {
    guard
        let attrs = try? FileManager.default.attributesOfItem(atPath: path),
        let raw = attrs[.posixPermissions] as? NSNumber
    else { return nil }
    return raw.int16Value
}

@main
enum SudoSocketProbe {
    static func main() {
        // 1. Root is exactly the client the server accepts; the probe needs the other side.
        if getuid() == 0 {
            print("SKIP: run as a normal user, the probe needs a non-root client")
            exit(0)
        }

        // 2. Short unique directory; sun_path is capped at 104 bytes.
        let directory = "/private/tmp/sudo_probe_\(UUID().uuidString.prefix(8))"
        let socketPath = directory + "/s.sock"
        defer { try? FileManager.default.removeItem(atPath: directory) }

        // 3. Stub handler that only flips the flag; the server must never reach it.
        let flag = HandlerFlag()
        let server = SudoSocketServer(socketURL: URL(fileURLWithPath: socketPath)) { _ in
            flag.mark()
            return .approve
        }
        do {
            try server.start()
        } catch {
            try? FileManager.default.removeItem(atPath: directory) // exit() skips the defer
            print("FAIL: server start threw: \(error)")
            exit(1)
        }

        // 4. Check A: the socket and its directory exist with the expected modes.
        let socketMode = modeBits(at: socketPath)
        let dirMode = modeBits(at: directory)
        check(
            FileManager.default.fileExists(atPath: socketPath)
                && socketMode != nil && (socketMode! & 0o777) == 0o600
                && dirMode != nil && (dirMode! & 0o777) == 0o700,
            "socket exists with mode 0600 and its directory with mode 0700"
        )

        // 5. Check B: a non-root client connects, sends a valid frame, and gets closed.
        let clientFD = socket(AF_UNIX, SOCK_STREAM, 0)
        var noSigPipe: Int32 = 1
        _ = setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        Data((socketPath + "\0").utf8).withUnsafeBytes { raw in
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyMemory(from: raw) }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(clientFD, $0, socklen_t(MemoryLayout<sockaddr_un>.stride))
            }
        }

        var closedWithoutAnswer = false
        var gotAnswer = false
        if connected == 0 {
            // Let the server check the peer credentials and close us first.
            Thread.sleep(forTimeInterval: 0.1)

            let frame = try? SudoFrameCodec.encode(
                SudoRequest(nonce: "probe-nonce", ancestorPIDs: [Int32(getpid())], argv: ["sudo", "true"], uid: UInt32(getuid()))
            )
            if let frame {
                frame.withUnsafeBytes { raw in
                    var offset = 0
                    while offset < raw.count {
                        // EPIPE/ECONNRESET mean the server already closed; not a probe failure.
                        let written = write(clientFD, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                        if written > 0 {
                            offset += written
                        } else if written < 0, errno == EINTR {
                            continue
                        } else {
                            break
                        }
                    }
                }
            }

            var recvTimeout = timeval(tv_sec: 3, tv_usec: 0)
            _ = setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &recvTimeout, socklen_t(MemoryLayout<timeval>.size))
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = recv(clientFD, &buffer, buffer.count, 0)
                if count == 0 || (count < 0 && (errno == ECONNRESET || errno == EPIPE)) {
                    closedWithoutAnswer = true // the server closed the connection and sent nothing
                    break
                } else if count < 0 && errno != EINTR {
                    break // timeout or another error: the server did not close us, so this is not a pass
                } else if count > 0 {
                    gotAnswer = true // response bytes mean the non-root client reached the handler
                    break
                }
            }
        }
        close(clientFD)
        check(connected == 0 && closedWithoutAnswer && !gotAnswer, "server closes a non-root client without sending an answer")

        // 6. Check C: the handler never ran.
        Thread.sleep(forTimeInterval: 0.3)
        check(!flag.isSet, "handler was never called for a non-root client")

        // 7. Check D: stop() unlinks the socket and is safe to call twice.
        server.stop()
        server.stop()
        check(!FileManager.default.fileExists(atPath: socketPath), "socket file is unlinked after stop() and a second stop() is a no-op")

        try? FileManager.default.removeItem(atPath: directory) // exit() skips the defer
        if failures == 0 {
            print("All sudo socket probe checks passed.")
        } else {
            print("\(failures) sudo socket probe check(s) FAILED.")
        }
        exit(failures == 0 ? 0 : 1)
    }
}
