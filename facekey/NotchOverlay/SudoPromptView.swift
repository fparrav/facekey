//
//  SudoPromptView.swift
//  facekey
//
//  Content of the notch panel while a sudo request waits for an answer. The two
//  buttons are plain labels, not `Button`s: the click is resolved from the raw
//  mouse-down in `NotchWindow.sendEvent`, so an accessibility press or an
//  AppleScript click has nothing to trigger.
//

import SwiftUI

struct SudoPromptView: View {
    let prompt: SudoOverlayPrompt
    /// Space reserved above the text, so nothing sits under the physical notch cutout.
    let topInset: CGFloat

    @State private var glow = false
    @State private var remaining: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                badge
                switch prompt.kind {
                case .confirm: confirmText
                case .firstUse: firstUseText
                }
                if prompt.isUnsigned { unsignedNote }
            }
            .padding(.top, topInset)
            .padding(.horizontal, SudoOverlayMetrics.horizontalPadding)

            Spacer(minLength: 8)

            countdownBar
                .padding(.horizontal, SudoOverlayMetrics.horizontalPadding + 14)
                .padding(.bottom, 12)

            HStack(spacing: 12) {
                switch prompt.kind {
                case .confirm:
                    secondaryButton("Cancel", symbol: "xmark")
                    primaryButton("Accept", symbol: "checkmark")
                case .firstUse:
                    secondaryButton("Not now", symbol: "xmark")
                    primaryButton("Allow", symbol: "checkmark.shield.fill")
                }
            }
            .frame(height: SudoOverlayMetrics.buttonRowHeight)
            .padding(.horizontal, SudoOverlayMetrics.horizontalPadding)
            .padding(.bottom, SudoOverlayMetrics.bottomPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .top) { halo }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { glow = true }
        }
    }

    // MARK: - Header

    /// A soft accent glow behind the header, so the prompt reads as Facekey's and not as a plain black box.
    private var halo: some View {
        RadialGradient(
            colors: [FacekeyTheme.accent.opacity(glow ? 0.34 : 0.2), .clear],
            center: .top,
            startRadius: 4,
            endRadius: 190
        )
        .frame(height: 190)
        .allowsHitTesting(false)
    }

    private var badge: some View {
        ZStack {
            Circle()
                .fill(FacekeyTheme.accent.opacity(glow ? 0.28 : 0.14))
                .frame(width: 46, height: 46)
                .blur(radius: 7)
            Circle()
                .fill(LinearGradient(
                    colors: [FacekeyTheme.accentBright, FacekeyTheme.accentDeep],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                .frame(width: 34, height: 34)
            Image(systemName: prompt.kind == .confirm ? "terminal.fill" : "lock.shield.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FacekeyTheme.onAccent)
        }
        .frame(height: 36)
    }

    private var confirmText: some View {
        VStack(spacing: 8) {
            Text("Approve sudo from \(prompt.appName)?")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(FacekeyTheme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("$")
                    .foregroundStyle(FacekeyTheme.accentBright)
                Text(prompt.command)
                    .foregroundStyle(.white.opacity(0.78))
                    // The text is already clipped to 120 characters keeping head and tail, which fits three lines;
                    // a lower limit would hide the tail again.
                    .lineLimit(3)
                    .truncationMode(.middle)
            }
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.1), lineWidth: 1))
        }
    }

    private var firstUseText: some View {
        Text("Allow \(prompt.appName) to use Facekey for sudo?")
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(FacekeyTheme.textPrimary)
            .lineLimit(3)
            .multilineTextAlignment(.center)
    }

    private var unsignedNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("This app is not signed, so Facekey recognizes it by its code.")
                .multilineTextAlignment(.leading)
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.orange.opacity(0.14)))
    }

    // MARK: - Time left

    /// How long the prompt keeps waiting, drawn as a bar that drains; purely visual, the
    /// coordinator owns the real timeout.
    private var countdownBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(
                        colors: [FacekeyTheme.accentBright, remaining < 0.3 ? .orange : FacekeyTheme.accent],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: proxy.size.width * remaining)
            }
        }
        .frame(height: 3)
        .id(prompt)
        .onAppear { drain() }
        .onChange(of: prompt) { drain() }
    }

    private func drain() {
        remaining = 1
        let seconds = Double(SudoTimeouts.accept.components.seconds)
        withAnimation(.linear(duration: seconds)) { remaining = 0 }
    }

    // MARK: - Buttons

    private func primaryButton(_ title: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(FacekeyTheme.onAccent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Capsule().fill(LinearGradient(
                colors: [FacekeyTheme.accentBright, FacekeyTheme.accent, FacekeyTheme.accentDeep],
                startPoint: .top,
                endPoint: .bottom
            ))
        )
        .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
        .shadow(color: FacekeyTheme.accent.opacity(0.55), radius: 9, y: 2)
    }

    private func secondaryButton(_ title: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(FacekeyTheme.textPrimary.opacity(0.9))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Capsule().fill(.white.opacity(0.12)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
    }
}
