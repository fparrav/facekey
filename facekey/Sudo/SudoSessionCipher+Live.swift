//
//  SudoSessionCipher+Live.swift
//  facekey
//
//  Live implementation of the session cipher seam, backed by SecureCredentialManager.
//

import Foundation

/// Live cipher: delegates to the Keychain-backed session key of SecureCredentialManager.
struct SudoLiveSessionCipher: SudoSessionCipher {
    var isSessionUnlocked: Bool { SecureCredentialManager.isSessionUnlocked }
    func encrypt(_ data: Data) throws -> Data { try SecureCredentialManager.encrypt(data) }
    func decrypt(_ data: Data) throws -> Data { try SecureCredentialManager.decrypt(data) }
}
