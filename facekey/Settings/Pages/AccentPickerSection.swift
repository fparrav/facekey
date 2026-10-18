//
//  AccentPickerSection.swift
//  facekey
//
//  The accent-colour picker: five swatches that repaint the notch and pill,
//  green by default for its link to Face ID.
//

import SwiftUI

struct AccentPickerSection: View {
    @Bindable private var settings = FacekeySettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            SettingsGroup {
                SettingsRowContent(title: "Accent colour") {
                    HStack(spacing: 8) {
                        ForEach(AccentChoice.allCases) { choice in
                            swatch(for: choice)
                        }
                    }
                }
            }

            SettingsCaption(text: "Green by default, for its link to Face ID")
        }
    }

    /// One swatch: a 22 pt filled circle in the choice's accent; the current
    /// choice wears a white ring just outside it, matching the reference
    /// look of a haloed swatch rather than a border on the fill.
    private func swatch(for choice: AccentChoice) -> some View {
        let c = AccentPalette.accent(choice)
        let isSelected = settings.accentChoice == choice

        return Button {
            settings.accentChoice = choice
        } label: {
            Circle()
                .fill(Color(red: c.r, green: c.g, blue: c.b))
                .frame(width: 22, height: 22)
                .overlay {
                    if isSelected {
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .padding(-4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(choice.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
