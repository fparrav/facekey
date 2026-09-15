## 1. Spike: verify the clamshell screen-list assumption

- [x] 1.1 On a real Mac laptop with an external display attached, close the lid (clamshell mode, machine still awake) and log `NSScreen.screens.map { ($0.localizedName, $0.isBuiltIn, $0.frame) }` from a debug build; verify the built-in display is absent from the list. Record the result in this task's checkbox (or in a follow-up note) before continuing to section 2 — if the built-in display is still present (asleep or otherwise), stop and re-open design.md's "Risks / Trade-offs" section to pick the two-context fallback instead of three. @needs-human

## 2. Display context resolver

- [x] 2.1 Add a `DisplayContext` enum (`.builtInOnly`, `.builtInAndExternal`, `.externalOnly`) with a `static func current() -> DisplayContext` computed from `NSScreen.screens` + the existing `NSScreen.isBuiltIn` (near `NotchGeometry.swift`, per design.md decision 1), and verify with a quick unit test or Face Lab-style manual check that unplugging/replugging an external display flips the reported context. @worker:local

## 3. Settings persistence

- [x] 3.1 Add three new `Bool` properties to `GlanceSettings` (`isFaceUnlockEnabledBuiltInOnly`, `isFaceUnlockEnabledBuiltInAndExternal`, `isFaceUnlockEnabledExternalOnly`), each with its own `Key.*` constant, `UserDefaults` persistence, and a `true` default, following the existing `isFaceUnlockEnabled` pattern; verify by reading the value back after a simulated relaunch (re-instantiating `GlanceSettings` against the same `UserDefaults` suite in a test, or manually via Settings + `defaults read`). @worker:free
- [x] 3.2 Add a convenience accessor on `GlanceSettings` (e.g. `func isFaceUnlockEnabled(for context: DisplayContext) -> Bool`) that maps a `DisplayContext` to the right one of the three properties above, and verify it returns the correct property for all three cases. @worker:free

## 4. Coordinator gating

- [x] 4.1 Add a guard in `FaceUnlockCoordinator.evaluateTrigger()` that calls `disarmOverlay()` and returns when `GlanceSettings.shared.isFaceUnlockEnabled(for: DisplayContext.current())` is `false`, placed alongside the existing `isEnabled`/`preferredScreen()` guards per design.md decision 3; verify by disabling one context's setting, forcing that context, and confirming a lock/wake trigger no longer opens the camera or shows the overlay (existing enrolled test face + Face Lab, or manual observation). @worker:local
- [x] 4.2 Verify Touch ID and manual password entry at the lock screen still work normally while a context is Disabled (manual check — these paths don't run through `FaceUnlockCoordinator`). @needs-human

## 5. Settings UI

- [x] 5.1 Add an "Active when" `SettingsGroup` to `GeneralSettingsPage.swift` with three rows (Built-in only / Built-in + external / External only), each a `SettingsRowContent` + `GlanceToggle` bound to the corresponding `GlanceSettings` property, placed below the existing "Display on" row per design.md decision 4; verify by toggling each row and confirming the setting persists across an app relaunch. @worker:free
- [x] 5.2 Manually verify the three rows read clearly next to the existing "Display on" row (no visual confusion between "where it shows" and "whether it's active") — screenshot or live check in the Settings window. @needs-human

## 6. Spec conformance check

- [x] 6.1 Walk through every scenario in `specs/face-unlock/spec.md` against the implemented behavior (default-enabled, per-context toggle independence, arming gated per context, Touch ID/password unaffected) and confirm each one holds. @worker:orchestrator

## 7. Optional cleanup (not required to ship this change)

- [x] 7.1 Migrate `CameraDeviceCatalog.isUsingBuiltInDisplay()` to use `DisplayContext.current()` instead of `NSScreen.main`, fixing the same "follows focus, not the camera" bug that upstream PR #26 fixed for the overlay's screen selection; verify camera selection still resolves correctly with only a built-in display, and with an external display attached regardless of window focus. @worker:free
