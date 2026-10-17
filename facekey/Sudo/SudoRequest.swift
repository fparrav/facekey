//
//  SudoRequest.swift
//  facekey
//
//  Wire model for the sudo approval channel: the request the PAM module sends over
//  Facekey's Unix socket and the answer the app writes back, plus a length-prefixed
//  JSON codec with explicit framing errors. Foundation only so it compiles standalone.
//

import Foundation

struct SudoRequest: Codable, Equatable {
    var nonce: String
    var ancestorPIDs: [Int32]
    var argv: [String]
    var uid: UInt32
}

enum SudoDecision: String, Codable {
    case approve
    case ignore
}

struct SudoAnswer: Codable, Equatable {
    var nonce: String
    var decision: SudoDecision
}

enum SudoFrameError: Error, Equatable {
    case oversize
    case truncated
    case malformed
}

enum SudoFrameCodec {
    static let maxFrameSize = 65_536

    /// Serializes to JSON, prefixes it with its length as 4 big-endian bytes.
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let json = try JSONEncoder().encode(value)
        guard json.count <= maxFrameSize else { throw SudoFrameError.oversize }
        var frame = Data(capacity: 4 + json.count)
        let length = UInt32(json.count)
        frame.append(UInt8((length >> 24) & 0xFF))
        frame.append(UInt8((length >> 16) & 0xFF))
        frame.append(UInt8((length >> 8) & 0xFF))
        frame.append(UInt8(length & 0xFF))
        frame.append(json)
        return frame
    }

    /// Reads one frame from the front of `data`, which may hold a partial buffer.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> (value: T, consumed: Int) {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { throw SudoFrameError.truncated }
        let declared =
            (UInt32(bytes[0]) << 24) |
            (UInt32(bytes[1]) << 16) |
            (UInt32(bytes[2]) << 8) |
            UInt32(bytes[3])
        // Reject a bogus length before touching the body.
        guard declared <= UInt32(maxFrameSize) else { throw SudoFrameError.oversize }
        let bodyStart = 4
        let bodyEnd = bodyStart + Int(declared)
        guard bytes.count >= bodyEnd else { throw SudoFrameError.truncated }
        let json = Data(bytes[bodyStart..<bodyEnd])
        let value: T
        do {
            value = try JSONDecoder().decode(T.self, from: json)
        } catch {
            throw SudoFrameError.malformed
        }
        return (value, bodyEnd)
    }
}
