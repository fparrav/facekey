//
//  SudoSocketServer.swift
//  facekey
//
//  Unix socket server for the sudo approval channel. Only a process with an
//  effective uid of 0 (a real sudo) may raise a request: every accepted
//  connection is checked with LOCAL_PEERCRED before a single byte is read.
//

import Foundation
import Darwin
import os

private let log = Logger(subsystem: "com.fparrav.facekey", category: "sudo")

/// Serves sudo approval requests on a Unix socket; only a real sudo (uid 0) may connect.
/// `@unchecked Sendable`: all mutable state is touched only from the private serial queue.
final class SudoSocketServer: @unchecked Sendable {
    enum ServerError: Error, Equatable { case pathTooLong, directoryFailed, socketFailed, bindFailed, permissionsFailed, listenFailed }

    private let socketURL: URL
    private let handler: (SudoRequest) async -> SudoDecision
    private let queue = DispatchQueue(label: "facekey.sudo-socket-server")
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?

    init(socketURL: URL, handler: @escaping (SudoRequest) async -> SudoDecision) {
        self.socketURL = socketURL
        self.handler = handler
    }

    /// Creates the socket file, binds, listens, and serves accepted connections on its own queue.
    func start() throws {
        try queue.sync { try startOnQueue() }
    }

    private func startOnQueue() throws {
        stopOnQueue()
        let path = socketURL.path
        let maxPath = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        guard path.utf8.count + 1 <= maxPath else { throw ServerError.pathTooLong }

        let parent = socketURL.deletingLastPathComponent().path
        do {
            try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        } catch {
            throw ServerError.directoryFailed
        }
        guard parent.withCString({ chmod($0, 0o700) }) == 0 else { throw ServerError.directoryFailed }
        path.withCString { _ = unlink($0) }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.socketFailed }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        Data((path + "\0").utf8).withUnsafeBytes { raw in withUnsafeMutableBytes(of: &address.sun_path) { $0.copyMemory(from: raw) } }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.stride))
            }
        }
        guard bound == 0 else { close(fd); throw ServerError.bindFailed }

        guard path.withCString({ chmod($0, 0o600) }) == 0 else {
            close(fd)
            path.withCString { _ = unlink($0) }
            throw ServerError.permissionsFailed
        }
        guard listen(fd, 8) == 0 else { close(fd); throw ServerError.listenFailed }

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptConnection() }
        // The fd must outlive the async cancel, so the cancel handler closes it.
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
    }

    /// Cancels the listen source, closes the listen fd, and unlinks the socket file.
    /// Safe to call twice.
    func stop() {
        queue.sync { stopOnQueue() }
    }

    private func stopOnQueue() {
        source?.cancel()
        source = nil
        listenFD = -1
        socketURL.path.withCString { _ = unlink($0) }
    }

    private func acceptConnection() {
        var peer = sockaddr()
        var peerLength = socklen_t(MemoryLayout<sockaddr>.size)
        let clientFD = accept(listenFD, &peer, &peerLength)
        guard clientFD >= 0 else { return }

        var noSigPipe: Int32 = 1
        guard setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size)) == 0 else { close(clientFD); return }
        var sendTimeout = timeval(tv_sec: 5, tv_usec: 0)
        guard setsockopt(clientFD, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size)) == 0 else { close(clientFD); return }
        // Only a real sudo may raise a request; drop everything else unread.
        guard peerIsRoot(fd: clientFD) else {
            log.notice("sudo approval: connection refused, the peer is not root")
            close(clientFD)
            return
        }
        guard let request = readRequest(fd: clientFD) else {
            log.notice("sudo approval: connection dropped, no valid request frame")
            close(clientFD)
            return
        }

        Task {
            let decision = await self.handler(request)
            if let answer = try? SudoFrameCodec.encode(SudoAnswer(nonce: request.nonce, decision: decision)) {
                self.writeAll(fd: clientFD, data: answer)
            }
            close(clientFD)
        }
    }

    /// True only if the peer credentials are versioned and owned by uid 0.
    private func peerIsRoot(fd: Int32) -> Bool {
        var cred = xucred()
        var credLength = socklen_t(MemoryLayout<xucred>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERCRED, &cred, &credLength) == 0 else { return false }
        return cred.cr_version == XUCRED_VERSION && cred.cr_uid == 0
    }

    /// Reads until one full frame arrives; nil on EOF, timeout, oversize, or malformed data.
    private func readRequest(fd: Int32) -> SudoRequest? {
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        // Without the timeout a silent peer could hold the queue, so drop it.
        guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0 else { return nil }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            // Never read past one maximal frame.
            let room = 4 + SudoFrameCodec.maxFrameSize - buffer.count
            guard room > 0 else { return nil }
            let count = recv(fd, &chunk, min(chunk.count, room), 0)
            if count > 0 {
                buffer.append(contentsOf: chunk[0..<Int(count)])
            } else if count == 0 || errno != EINTR {
                return nil // EOF or read timeout/error
            }
            do {
                let (request, _) = try SudoFrameCodec.decode(SudoRequest.self, from: buffer)
                return request
            } catch SudoFrameError.truncated {
                guard buffer.count <= 4 + SudoFrameCodec.maxFrameSize else { return nil }
            } catch {
                return nil
            }
        }
    }

    /// Writes all bytes, retrying on partial writes and EINTR.
    private func writeAll(fd: Int32, data: Data) {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if written > 0 { offset += Int(written) }
                else if written < 0, errno == EINTR { continue }
                else { return }
            }
        }
    }
}
