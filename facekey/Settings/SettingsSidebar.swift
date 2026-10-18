//
//  SettingsSidebar.swift
//  facekey
//
//  Left sidebar of the Settings window: one tile-and-title row per visible
//  page, a session lock button pinned at the bottom, all on a floating
//  220 pt glass panel. Liquid Glass where macOS 26 provides it, the
//  existing `.sidebar` material elsewhere.
//

import SwiftUI
import Foundation

struct SettingsSidebar: View {
    @Binding var selection: SettingsPage
    let pages: [SettingsPage]
    let pocController: POCController

    static let width: CGFloat = 220
    private static let cornerRadius: CGFloat = 22
    private static let rowHeight: CGFloat = 38
    private static let rowRadius: CGFloat = 10

    /// Which page is under the cursor — drives the hover wash on unselected
    /// rows. Tracked here (not per row) so exactly one row can be hovered.
    @State private var hoveredPage: SettingsPage?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                ForEach(pages) { page in
                    row(page)
                }
            }
            Spacer(minLength: 12)
            SessionLockButton(pocController: pocController)
        }
        .padding(12)
        .frame(width: Self.width)
        .background { floatingBackground }
    }

    // MARK: - Page rows

    private func row(_ page: SettingsPage) -> some View {
        let isSelected = selection == page
        return Button {
            withAnimation(SettingsMetrics.tabSelectionAnimation) {
                selection = page
            }
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(hex: page.tileHex))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: page.symbolName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                Text(page.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(SettingsMetrics.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: Self.rowHeight)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Self.rowRadius, style: .continuous)
                        .fill(FacekeyTheme.accent.opacity(0.18))
                } else if hoveredPage == page {
                    RoundedRectangle(cornerRadius: Self.rowRadius, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Self.rowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredPage = page
            } else if hoveredPage == page {
                hoveredPage = nil
            }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Floating background

    /// Debug-only escape hatch: `FACEKEY_FORCE_MATERIAL_SIDEBAR=1` forces
    /// the pre-26 `.sidebar` material so both renders can be compared.
    /// Always `false` in Release.
    private static var forceMaterialFallback: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["FACEKEY_FORCE_MATERIAL_SIDEBAR"] == "1"
        #else
        false
        #endif
    }

    /// Liquid Glass on macOS 26+, the `.sidebar` visual effect elsewhere —
    /// same 22 pt rounded shape on both paths, so the layout never shifts.
    @ViewBuilder
    private var floatingBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        if #available(macOS 26, *) {
            if Self.forceMaterialFallback {
                materialBackground(shape)
            } else {
                shape.glassEffect(.regular, in: shape)
            }
        } else {
            materialBackground(shape)
        }
    }

    /// The pre-26 look: the window's `.sidebar` material, clipped to the
    /// same rounded shape and outlined with the row's hairline border.
    private func materialBackground(_ shape: RoundedRectangle) -> some View {
        VisualEffectView()
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(SettingsMetrics.rowBorder, lineWidth: SettingsMetrics.rowBorderWidth)
            )
    }
}

// MARK: - Preview

#Preview("Settings sidebar") {
    SidebarPreview()
        .padding(20)
        .frame(width: 320, height: 520)
        .background(Color(red: 0.42, green: 0.26, blue: 0.58))
}

private struct SidebarPreview: View {
    @State private var selection: SettingsPage = .access

    var body: some View {
        SettingsSidebar(
            selection: $selection,
            pages: SettingsPage.visiblePages(includingLab: false),
            pocController: POCController()
        )
    }
}

// MARK: - Hex color

private extension Color {
    /// `#RRGGBB` string (the format `SettingsPage.tileHex` uses); a bare
    /// 6-hex-digit string is accepted too.
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.hasPrefix("#") ? String(hex.dropFirst()) : hex)
            .scanHexInt64(&value)
        let rgb = value & 0xFFFFFF
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
