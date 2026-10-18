//
//  SudoOverlayPresenter.swift
//  facekey
//
//  Live `SudoOverlayPresenting`: shows the sudo prompt in the notch overlay and turns
//  the click on one of its buttons into the coordinator's answer. Only a hardware click
//  accepts or allows; a click posted by a program is answered as Cancel / Not now. Each call resolves
//  exactly once; `close()` resolves anything still waiting as cancelled.
//

import Foundation

@MainActor
final class SudoOverlayPresenter: SudoOverlayPresenting {
    private let overlay: NotchOverlayController
    private var pendingFirstUse: CheckedContinuation<SudoFirstUseChoice, Never>?
    private var pendingConfirm: CheckedContinuation<SudoOverlayResult, Never>?

    init(overlay: NotchOverlayController = .shared) {
        self.overlay = overlay
    }

    func askFirstUse(appName: String, isUnsigned: Bool) async -> SudoFirstUseChoice {
        resolvePending()
        return await withCheckedContinuation { continuation in
            pendingFirstUse = continuation
            let prompt = SudoOverlayPrompt(kind: .firstUse, appName: appName, command: "", isUnsigned: isUnsigned)
            let shown = overlay.presentSudo(prompt) { [weak self] choice, clickSource in
                // "Not now" stores nothing, so the question comes back on the next request.
                // Allow is remembered for good, so only a hardware click grants it: a posted click is treated as "Not now".
                let granted = choice == .allow && SudoClickSource.isHardware(clickSource)
                self?.resolveFirstUse(granted ? .allow : .dismissed)
            }
            if !shown { resolveFirstUse(.dismissed) }
        }
    }

    func confirm(_ request: SudoOverlayRequest) async -> SudoOverlayResult {
        resolvePending()
        return await withCheckedContinuation { continuation in
            pendingConfirm = continuation
            let prompt = SudoOverlayPrompt(kind: .confirm, appName: request.appName, command: request.command, isUnsigned: request.isUnsigned)
            let shown = overlay.presentSudo(prompt) { [weak self] choice, clickSource in
                // Only a hardware click accepts: a click posted by a script counts as Cancel.
                let accepted = choice == .accept && SudoClickSource.isHardware(clickSource)
                if accepted { self?.overlay.showSudoScanning() }
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
        resolveFirstUse(.dismissed)
        resolveConfirm(.cancelled)
    }

    private func resolveFirstUse(_ choice: SudoFirstUseChoice) {
        guard let continuation = pendingFirstUse else { return }
        pendingFirstUse = nil
        continuation.resume(returning: choice)
    }

    private func resolveConfirm(_ result: SudoOverlayResult) {
        guard let continuation = pendingConfirm else { return }
        pendingConfirm = nil
        continuation.resume(returning: result)
    }
}
