//
//  GeneralSettingsPage.swift
//  facekey
//

import OSLog
import SwiftUI

struct GeneralSettingsPage: View {
    @Bindable var coordinator: FaceUnlockCoordinator
    @Bindable var pocController: POCController
    @Bindable private var settings = FacekeySettings.shared

    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?
    /// Refreshed on `didChangeScreenParametersNotification` so the picker
    /// reflects displays connecting/disconnecting while Settings is open.
    @State private var screens: [NSScreen] = NSScreen.screens
    /// Refreshed when the app regains focus, so granting the permission in
    /// System Settings clears the prompt below without a relaunch.
    @State private var inputMonitoring = SpaceKeyMonitor.inputMonitoringAccess
    /// Re-read on focus regain and on a 1 s poll; feed the Permissions block
    /// in `unlockedState`.
    @State private var accessibilityGranted = SystemPermissions.accessibilityGranted
    @State private var cameraState = SystemPermissions.cameraState
    /// Flips once the system Accessibility prompt has been shown, so later
    /// taps deep-link into System Settings instead of re-prompting.
    @State private var hasPromptedAccessibility = false
    @State private var isUnlocking = false
    @State private var sessionError: String?

    /// Read from `POCController`, not a local copy — the session can be
    /// auto-locked while this page is visible.
    private var isSessionUnlocked: Bool { pocController.isSessionUnlocked }

    private var needsInputMonitoring: Bool {
        settings.unlockTriggers.contains(.onSpace) && inputMonitoring != .granted
    }

    /// Dev-only: under Xcode the reading above is Xcode's permission, not
    /// Facekey's, so it's meaningless. See `SpaceKeyMonitor.isLaunchedByXcode`.
    private var hasInheritedXcodePermission: Bool {
        settings.unlockTriggers.contains(.onSpace) && SpaceKeyMonitor.isLaunchedByXcode
    }

    var body: some View {
        ZStack(alignment: .top) {
            lockedState
                .opacity(isSessionUnlocked ? 0 : 1)
                .allowsHitTesting(!isSessionUnlocked)
                .accessibilityHidden(isSessionUnlocked)

            unlockedState
                .opacity(isSessionUnlocked ? 1 : 0)
                .allowsHitTesting(isSessionUnlocked)
                .accessibilityHidden(!isSessionUnlocked)
        }
        .animation(SettingsMetrics.stateTransitionAnimation, value: isSessionUnlocked)
        .onAppear { pocController.refreshCredentialStatus() }
        // The password prompt runs in the notch, outside this view's hierarchy,
        // so refresh the session state when that flow finishes.
        .onChange(of: NotchOverlayController.shared.phase) { _, newPhase in
            guard newPhase == .closed else { return }
            pocController.refreshCredentialStatus()
        }
        // The tccd database flips without an observable notification, so poll
        // while the page is visible; the task cancels itself on disappear.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                refreshPermissions()
            }
        }
    }

    // MARK: - Locked

    private var lockedState: some View {
        SettingsEmptyStateView(
            icon: "lock.fill",
            message: "Session locked",
            buttonTitle: isUnlocking ? "Authenticating…" : "Unlock session",
            isButtonEnabled: !isUnlocking,
            caption: sessionError,
            action: unlock
        )
    }

    // MARK: - Unlocked

    private var unlockedState: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            SettingsGroup {
                SettingsRowContent(title: "Launch at login") {
                    FacekeyToggle(isOn: Binding(
                        get: { launchAtLoginEnabled },
                        set: { newValue in
                            launchAtLoginEnabled = newValue
                            do {
                                try LaunchAtLogin.setEnabled(newValue)
                                launchAtLoginError = nil
                            } catch {
                                launchAtLoginEnabled = !newValue
                                launchAtLoginError = error.localizedDescription
                            }
                        }
                    ))
                }
                SettingsGroupDivider()
                SettingsRowContent(title: "Show in menu bar") {
                    FacekeyToggle(isOn: $settings.showsInMenuBar)
                }
                SettingsGroupDivider()
                SettingsRowContent(title: "Enable Face Unlock") {
                    FacekeyToggle(isOn: $coordinator.isEnabled)
                }
                SettingsGroupDivider()
                UnlockTriggerPicker(selection: $settings.unlockTriggers, isEnabled: coordinator.isEnabled)
                SettingsGroupDivider()
                displayPicker()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                screens = NSScreen.screens
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                inputMonitoring = SpaceKeyMonitor.inputMonitoringAccess
                refreshPermissions()
            }
            .onChange(of: settings.unlockTriggers) { oldValue, newValue in
                // Only prompt on the transition into selecting "On space".
                SpaceKeyMonitor.log.info("unlockTriggers changed: old=\(String(describing: oldValue), privacy: .public) new=\(String(describing: newValue), privacy: .public) state=\(String(describing: inputMonitoring), privacy: .public)")
                if newValue.contains(.onSpace), !oldValue.contains(.onSpace), inputMonitoring != .granted {
                    SpaceKeyMonitor.requestInputMonitoringAccess()
                    // tccd flips notDetermined -> denied just after the call
                    // returns, so re-read on the next beat rather than inline.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        inputMonitoring = SpaceKeyMonitor.inputMonitoringAccess
                    }
                }
            }
            if let launchAtLoginError {
                SettingsCaption(text: launchAtLoginError)
            }
            if hasInheritedXcodePermission {
                SettingsCaption(text: "Running from Xcode — permission checks resolve against Xcode’s grants, not Facekey’s, so this reading is meaningless. Launch facekey.app on its own to see the real state.")
            } else if needsInputMonitoring {
                inputMonitoringNotice()
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionTitle(text: "Active when")
                SettingsGroup {
                    SettingsRowContent(title: "Built-in only") {
                        FacekeyToggle(isOn: $settings.isFaceUnlockEnabledBuiltInOnly)
                    }
                    SettingsGroupDivider()
                    SettingsRowContent(title: "Built-in + external") {
                        FacekeyToggle(isOn: $settings.isFaceUnlockEnabledBuiltInAndExternal)
                    }
                    SettingsGroupDivider()
                    SettingsRowContent(title: "External only") {
                        FacekeyToggle(isOn: $settings.isFaceUnlockEnabledExternalOnly)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionTitle(text: "Behaviour")
                SettingsGroup {
                    SettingsRowContent(title: "Retry on notch hover") {
                        FacekeyToggle(isOn: $settings.retryOnHover)
                    }
                    SettingsGroupDivider()
                    SettingsRowContent(title: "Auto retry once after failure") {
                        FacekeyToggle(isOn: $settings.autoRetryOnce)
                    }
                    SettingsGroupDivider()
                    SettingsRowContent(title: "Haptic feedback") {
                        FacekeyToggle(isOn: $settings.hapticFeedbackEnabled)
                    }
                    SettingsGroupDivider()
                    SettingsSteppedSliderRowContent(
                        title: "Face detection duration",
                        valueLabel: "\(settings.faceDetectionSeconds)s",
                        index: Binding(
                            get: { Double(settings.faceDetectionSeconds - FacekeySettings.faceDetectionRange.lowerBound) },
                            set: { settings.faceDetectionSeconds = FacekeySettings.faceDetectionRange.lowerBound + Int($0.rounded()) }
                        ),
                        stopCount: FacekeySettings.faceDetectionRange.count
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionTitle(text: "Animation")
                SettingsGroup {
                    SettingsRowContent(title: "Show animation") {
                        FacekeyToggle(isOn: $settings.showUnlockAnimation)
                    }
                    SettingsGroupDivider()
                    UnlockAnimationPicker(
                        selection: $settings.unlockAnimationStyle,
                        isEnabled: settings.showUnlockAnimation
                    )
                }
            }

            // System permissions the unlock flow depends on: Accessibility
            // lets Facekey type the password, Camera lets it see your face.
            VStack(alignment: .leading, spacing: 8) {
                SettingsSectionTitle(text: "Permissions")
                SettingsGroup {
                    SettingsActionRowContent(
                        title: "Accessibility",
                        subtitle: accessibilityGranted
                            ? "Granted"
                            : "Not granted — Facekey recognizes you but cannot type your password. If it was granted before, remove and re-add Facekey in System Settings.",
                        buttonTitle: hasPromptedAccessibility ? "Open Settings" : "Grant",
                        isEnabled: !accessibilityGranted
                    ) {
                        if !hasPromptedAccessibility {
                            hasPromptedAccessibility = true
                            KeystrokeInjector.promptForAccessibility()
                        } else {
                            SystemPermissions.openPane("Privacy_Accessibility")
                        }
                        refreshPermissions()
                    }
                    SettingsGroupDivider()
                    SettingsActionRowContent(
                        title: "Camera",
                        subtitle: cameraSubtitle,
                        buttonTitle: cameraState == .notDetermined ? "Grant" : "Open Settings",
                        isEnabled: cameraState != .granted
                    ) {
                        Task {
                            await SystemPermissions.requestCamera()
                            refreshPermissions()
                        }
                    }
                }
            }
        }
    }

    private func unlock() {
        isUnlocking = true
        sessionError = nil
        Task {
            await pocController.unlockSession()
            sessionError = pocController.sessionError
            isUnlocking = false
        }
    }

    /// Re-reads the system permission states; the Permissions block renders
    /// from these two values.
    private func refreshPermissions() {
        accessibilityGranted = SystemPermissions.accessibilityGranted
        cameraState = SystemPermissions.cameraState
    }

    /// Row subtitle for the Camera permission per its current state.
    private var cameraSubtitle: String {
        switch cameraState {
        case .granted: return "Granted"
        case .notDetermined: return "Not requested yet"
        case .denied: return "Denied — enable it in System Settings"
        }
    }

    /// Shown while "On space" is selected but Input Monitoring isn't granted.
    private func inputMonitoringNotice() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsCaption(text: "“On space” reads the keyboard directly to see the space key on the lock screen, which needs Accessibility — the same permission Facekey uses to type your password. Switch Facekey on under Privacy & Security → Accessibility, then quit and reopen Facekey.")
            Button("Open Accessibility settings") {
                // Covers the rare install with no Accessibility grant at all.
                SpaceKeyMonitor.requestInputMonitoringAccess()
                openSystemSettings(pane: "Privacy_Accessibility")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    inputMonitoring = SpaceKeyMonitor.inputMonitoringAccess
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(FacekeyTheme.accent)
        }
    }

    private func openSystemSettings(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func displayPicker() -> some View {
        SettingsRowContent(title: "Display on") {
            SettingsMenuPickerPill(label: displayLabel) {
                Button("Main display") {
                    settings.preferredDisplayID = nil
                    settings.preferredDisplayName = nil
                }
                ForEach(screens.compactMap(NamedScreen.init), id: \.id) { screen in
                    Button(screen.name) {
                        settings.preferredDisplayID = screen.id
                        settings.preferredDisplayName = screen.name
                    }
                }
            }
        }
    }

    /// A connected screen with its stable ID already unwrapped, so the
    /// picker's `ForEach` doesn't need to filter/force-unwrap inline.
    private struct NamedScreen {
        let id: String
        let name: String

        init?(_ screen: NSScreen) {
            guard let id = screen.stableDisplayID else { return nil }
            self.id = id
            self.name = screen.localizedName
        }
    }

    private var displayLabel: String {
        guard let targetID = settings.preferredDisplayID else { return "Main display" }
        if let connected = screens.first(where: { $0.stableDisplayID == targetID }) {
            return connected.localizedName
        }
        // Picked, but not currently connected — say so rather than showing
        // a bare ID or falling back to another display's name.
        guard let name = settings.preferredDisplayName else { return "Selected display (disconnected)" }
        return "\(name) (disconnected)"
    }
}
