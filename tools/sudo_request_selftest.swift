//
//  sudo_request_selftest.swift
//  facekey (tools)
//
//  Offline self-test for SudoRequest wire model and length-prefixed JSON framing codec.
//  This project has no test target, so this compiles as a standalone script against the real file:
//
//      swiftc -O -parse-as-library -o /tmp/sudo_request_selftest \
//        facekey/Sudo/SudoRequest.swift \
//        tools/sudo_request_selftest.swift \
//      && /tmp/sudo_request_selftest
//
//  Prints PASS/FAIL per check; exits 0 when every check passes, 1 otherwise.
//

import Foundation

var failures = 0

func check(_ cond: Bool, _ name: String) {
    if cond {
        print("PASS: \(name)")
    } else {
        print("FAIL: \(name)")
        failures += 1
    }
}

@main
enum SudoRequestSelfTest {
    static func main() {
        // MARK: - 1. Round trip SudoRequest

        let req = SudoRequest(
            nonce: "test-nonce-1234",
            ancestorPIDs: [100, 200, 300],
            argv: ["/usr/bin/sudo", "ls", "-la"],
            uid: 501
        )
        do {
            let frame = try SudoFrameCodec.encode(req)
            let (decoded, consumed) = try SudoFrameCodec.decode(SudoRequest.self, from: frame)
            check(decoded == req, "SudoRequest round trip preserves all fields")
            check(consumed == frame.count, "SudoRequest round trip consumed equals total frame byte count")
        } catch {
            check(false, "SudoRequest round trip threw error: \(error)")
        }

        // MARK: - 2. Round trip SudoAnswer (.approve and .ignore)

        let ansApprove = SudoAnswer(nonce: "nonce-approve", decision: .approve)
        let ansIgnore = SudoAnswer(nonce: "nonce-ignore", decision: .ignore)
        do {
            let frameApprove = try SudoFrameCodec.encode(ansApprove)
            let (decApprove, consApprove) = try SudoFrameCodec.decode(SudoAnswer.self, from: frameApprove)
            check(decApprove == ansApprove && consApprove == frameApprove.count, "SudoAnswer (.approve) round trip")

            let frameIgnore = try SudoFrameCodec.encode(ansIgnore)
            let (decIgnore, consIgnore) = try SudoFrameCodec.decode(SudoAnswer.self, from: frameIgnore)
            check(decIgnore == ansIgnore && consIgnore == frameIgnore.count, "SudoAnswer (.ignore) round trip")
        } catch {
            check(false, "SudoAnswer round trip threw error: \(error)")
        }

        // MARK: - 3. Declared length oversize (65,537 bytes)

        // 65,537 = 0x00010001
        let oversizeHeader = Data([0x00, 0x01, 0x00, 0x01])
        do {
            _ = try SudoFrameCodec.decode(SudoRequest.self, from: oversizeHeader)
            check(false, "Oversize header should throw .oversize")
        } catch let err as SudoFrameError {
            check(err == .oversize, "Oversize header without body throws .oversize (not .truncated)")
        } catch {
            check(false, "Unexpected error for oversize header: \(error)")
        }

        // MARK: - 4. Truncated frame

        do {
            let fullFrame = try SudoFrameCodec.encode(req)
            let halfFrame = fullFrame.prefix(fullFrame.count / 2)
            _ = try SudoFrameCodec.decode(SudoRequest.self, from: halfFrame)
            check(false, "Truncated frame body should throw .truncated")
        } catch let err as SudoFrameError {
            check(err == .truncated, "Truncated frame body throws .truncated")
        } catch {
            check(false, "Unexpected error for truncated frame body: \(error)")
        }

        let shortHeader = Data([0x00, 0x00])
        do {
            _ = try SudoFrameCodec.decode(SudoRequest.self, from: shortHeader)
            check(false, "2-byte frame should throw .truncated")
        } catch let err as SudoFrameError {
            check(err == .truncated, "2-byte frame throws .truncated")
        } catch {
            check(false, "Unexpected error for 2-byte header: \(error)")
        }

        // MARK: - 5. Malformed JSON

        let badJsonBytes = [UInt8]("not-a-valid-json-string".utf8)
        let length = UInt32(badJsonBytes.count)
        var malformedFrame = Data()
        malformedFrame.append(UInt8((length >> 24) & 0xFF))
        malformedFrame.append(UInt8((length >> 16) & 0xFF))
        malformedFrame.append(UInt8((length >> 8) & 0xFF))
        malformedFrame.append(UInt8(length & 0xFF))
        malformedFrame.append(contentsOf: badJsonBytes)
        do {
            _ = try SudoFrameCodec.decode(SudoRequest.self, from: malformedFrame)
            check(false, "Malformed JSON should throw .malformed")
        } catch let err as SudoFrameError {
            check(err == .malformed, "Malformed JSON throws .malformed")
        } catch {
            check(false, "Unexpected error for malformed JSON: \(error)")
        }

        // MARK: - 6. Encode oversize (JSON > 65,536 bytes)

        let hugeArg = String(repeating: "A", count: 70_000)
        let hugeReq = SudoRequest(nonce: "n", ancestorPIDs: [1], argv: [hugeArg], uid: 501)
        do {
            _ = try SudoFrameCodec.encode(hugeReq)
            check(false, "Encoding JSON > 65,536 bytes should throw .oversize")
        } catch let err as SudoFrameError {
            check(err == .oversize, "Encoding JSON > 65,536 bytes throws .oversize")
        } catch {
            check(false, "Unexpected error encoding huge request: \(error)")
        }

        // MARK: - 7. Two concatenated frames

        do {
            let frame1 = try SudoFrameCodec.encode(req)
            let frame2 = try SudoFrameCodec.encode(ansApprove)
            var combined = Data()
            combined.append(frame1)
            combined.append(frame2)

            let (dec1, consumed1) = try SudoFrameCodec.decode(SudoRequest.self, from: combined)
            check(dec1 == req, "First frame in concatenated buffer decodes correctly")
            check(consumed1 == frame1.count, "Consumed bytes equals first frame size in concatenated buffer")

            let remainder = combined.suffix(from: consumed1)
            let (dec2, consumed2) = try SudoFrameCodec.decode(SudoAnswer.self, from: remainder)
            check(dec2 == ansApprove, "Second frame in concatenated buffer decodes correctly")
            check(consumed2 == frame2.count, "Second frame consumed bytes equals second frame size")
        } catch {
            check(false, "Concatenated frames decode threw error: \(error)")
        }

        if failures == 0 {
            print("All sudo request self-tests passed.")
        } else {
            print("\(failures) sudo request check(s) FAILED.")
        }
        exit(failures == 0 ? 0 : 1)
    }
}
