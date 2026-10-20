//
//  PasswordsUnlockOverlayPresenter.swift
//  facekey
//
//  Live `PasswordsUnlockOverlayPresenting`: shows the "Unlock Passwords" prompt in the
//  notch overlay and turns the click on one of its buttons into the coordinator's answer.
//  Only a hardware click accepts; a click posted by a program is answered as Cancel.
//  Each call resolves exactly once; `close()` resolves anything still waiting as cancelled.
//

import Foundation

@MainActor
final class PasswordsUnlockOverlayPresenter: PasswordsUnlockOverlayPresenting {
    private let overlay: NotchOverlayController
    private var pendingConfirm: CheckedContinuation<SudoOverlayResult, Never>?

    init(overlay: NotchOverlayController = .shared) {
        self.overlay = overlay
    }

    func confirm() async -> SudoOverlayResult {
        resolvePending()
        return await withCheckedContinuation { continuation in
            pendingConfirm = continuation
            let prompt = SudoOverlayPrompt(kind: .unlockPasswords, appName: "Passwords", command: "", isUnsigned: false)
            let shown = overlay.presentSudo(prompt) { [weak self] choice, clickSource in
                // Only a hardware click accepts: a click posted by a script counts as Cancel.
                let accepted = choice == .accept && SudoClickSource.isHardware(clickSource)
                if accepted { self?.overlay.showPasswordsUnlockScanning() }
                self?.resolveConfirm(accepted ? .accepted(clickSource: clickSource) : .cancelled)
            }
            if !shown { resolveConfirm(.cancelled) }
        }
    }

    func close() {
        resolvePending()
        overlay.dismissSudo()
    }

    // MARK: - Single resolution

    private func resolvePending() {
        resolveConfirm(.cancelled)
    }

    private func resolveConfirm(_ result: SudoOverlayResult) {
        guard let continuation = pendingConfirm else { return }
        pendingConfirm = nil
        continuation.resume(returning: result)
    }
}
