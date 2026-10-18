//
//  SessionSecuritySection.swift
//  facekey
//

import SwiftUI

struct SessionSecuritySection: View {
    @Binding var autoLockInterval: AutoLockInterval
    @Binding var autoUnlockSession: Bool

    var body: some View {
        SettingsGroup {
            SettingsSteppedSliderRowContent(
                title: "Auto lock session",
                valueLabel: autoLockInterval.title,
                index: Binding(
                    get: { autoLockInterval.sliderIndex },
                    set: { autoLockInterval = .from(sliderIndex: $0) }
                ),
                stopCount: AutoLockInterval.allCases.count
            )

            SettingsGroupDivider()

            SettingsRowContent(title: "Unlock automatically at launch") {
                FacekeyToggle(isOn: $autoUnlockSession)
            }
        }
    }
}
