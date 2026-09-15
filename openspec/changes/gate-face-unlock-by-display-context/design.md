## Context

`GlanceSettings` (`glance/Settings/GlanceSettings.swift`) already follows a consistent pattern: an `@Observable` class backed by `UserDefaults`, one `Key.*` string constant plus one `didSet`-persisted property per setting (see `isFaceUnlockEnabled`, `preferredDisplayID`). `FaceUnlockCoordinator.evaluateTrigger()` (`FaceUnlockCoordinator.swift:90`) is the single choke point where every arming decision is made — it already has a `guard NotchGeometry.preferredScreen() != nil else { return }` that bails without arming. `GeneralSettingsPage.swift` already renders a "Display on" row using `SettingsMenuPickerPill`, and `CameraSettingsPage.swift` renders three parallel rows (Default/Built-in/External) using `SettingsRowContent` + a picker. `NSScreen` already carries an `isBuiltIn` extension (`NotchGeometry.swift:242`). See `proposal.md` for motivation.

## Goals / Non-Goals

**Goals:**
- Let a user independently enable/disable Face Unlock arming for each of the three display contexts (built-in only / dual / external only).
- Preserve exact current behavior for anyone who never touches the new setting.
- Reuse the existing settings/UI/screen-geometry patterns rather than introducing new ones.

**Non-Goals:**
- Changing *where* the notch animation renders (`preferredDisplayID` / "Display on" stays a separate, orthogonal setting).
- Gating Touch ID or manual password entry — both are outside `FaceUnlockCoordinator` and untouched.
- Per-trigger-type granularity (e.g. different context rules for "on wake" vs "on space"). One gate applies to all triggers.
- Fixing `CameraDeviceCatalog.isUsingBuiltInDisplay()`'s focus-follows bug as a hard requirement — tracked as an optional task only.

## Decisions

**1. New `DisplayContext` enum + resolver function, not three ad-hoc booleans read inline.**
A `DisplayContext { case builtInOnly, builtInAndExternal, externalOnly }` with a `static func current() -> DisplayContext` (or similar) derived from `NSScreen.screens.contains { $0.isBuiltIn }` and `NSScreen.screens.count(where: !isBuiltIn) > 0`. Central place for the classification logic in the new spec's "Display context classification" requirement, and the same function is what an eventual `CameraDeviceCatalog` migration would call. Placed as a `static` extension near `NotchGeometry.swift` (same file or a new small file next to it), since that's where `isBuiltIn` and screen-geometry concerns already live — not inside `GlanceSettings`, which has no `AppKit` screen-reading today.

Alternative considered: inline the three-way check directly in `evaluateTrigger()`. Rejected — it duplicates across the coordinator and (potentially) `CameraDeviceCatalog`, and the spec talks about "context classification" as its own testable concept.

**2. Three independent `Bool` settings, not one enum/bitmask setting.**
`isFaceUnlockEnabledBuiltInOnly`, `isFaceUnlockEnabledBuiltInAndExternal`, `isFaceUnlockEnabledExternalOnly` — mirrors the existing flat-bool style (`isFaceUnlockEnabled`, `retryOnHover`, etc.) instead of introducing a new `Set<DisplayContext>` persistence shape. Each defaults to `true` via the standard `UserDefaults.register`/property-initializer pattern already used elsewhere in the file, satisfying "opt-in only, no behavior change by default."

Alternative considered: a single `Set<DisplayContext>` of "disabled contexts" (parallel to `unlockTriggers: Set<UnlockTrigger>`). Rejected only for consistency — either works technically, but three named booleans read more directly in `evaluateTrigger()` and in the settings UI binding, and avoid the empty-set edge-case handling `unlockTriggers` needs.

**3. Gate lives in `evaluateTrigger()`, expressed as one more guard.**
```
guard settings.isFaceUnlockEnabled(for: DisplayContext.current()) else {
    disarmOverlay()
    return
}
```
placed alongside the existing `guard isEnabled, !hasArmedForCurrentLock` and `guard NotchGeometry.preferredScreen() != nil` guards. This is the only call site that needs to change in `FaceUnlockCoordinator`; `disarmOverlay()` already exists and already runs when `isEnabled` flips false, so the "cancel any in-flight scan" scenario in the spec is handled by code that's already exercised today.

**4. Settings UI: new "Active when" `SettingsGroup` with three rows, same building blocks as `CameraSettingsPage`'s three-row layout.**
Each row is a `SettingsRowContent` + `GlanceToggle` (the same toggle control used for "Enable Face Unlock" itself), not a menu picker like "Display on" — a binary Enabled/Disabled reads more directly as a toggle than a dropdown. Placed in `GeneralSettingsPage.swift`, below the existing "Display on" row, so the two display-related settings sit next to each other without being visually merged into one control.

## Risks / Trade-offs

- **[Risk] The "External only" classification assumes macOS drops the built-in display from `NSScreen.screens` in true clamshell mode (lid closed + external attached + still awake).** This is the load-bearing assumption for distinguishing "External only" from "Built-in + external" — if macOS instead keeps reporting a sleeping/zero-frame built-in entry, the two contexts collapse into one. → **Mitigation**: verify empirically on real clamshell hardware before or during implementation (a `tasks.md` item); if the assumption doesn't hold, fall back to treating "External only" and "Built-in + external" as one merged context (two rows instead of three) rather than shipping a row that never triggers.
- **[Risk] `NSApplication.didChangeScreenParametersNotification` firing mid-scan (e.g. user connects/disconnects a monitor while a scan is in flight) could leave the coordinator in an inconsistent state if the context flips between arm and evaluate.** → **Mitigation**: no new observation is needed — `evaluateTrigger()` already only runs on lock/wake/space events, and `NotchWindowController` already repositions on screen-parameter changes independently. The gate gets re-evaluated on the next trigger, not live mid-scan; this matches how `preferredScreen()` disconnection is already handled (next trigger, not instantly).
- **[Trade-off] Three booleans instead of a single richer settings object** means a future fourth context (e.g. per-trigger overrides) would need another migration. Accepted since the proposal explicitly scopes to exactly three contexts and the existing codebase favors flat booleans over compound settings objects.

## Migration Plan

No data migration needed — three new `UserDefaults` keys default to `true`, so an existing install behaves identically until the user visits Settings. No rollback concerns beyond a normal revert (removing the guard and the settings rows).
