## Why

Face Unlock arms unconditionally whenever it's enabled, regardless of which displays are connected. Some users want it active only in specific display configurations — e.g. off when working directly on the built-in display (relying on Touch ID instead), on when docked to an external monitor with a dedicated external camera. Today the only display-related setting ("Display on") controls *where* the notch animation is drawn, not *whether* Face Unlock arms at all, so there's no way to express this.

## What Changes

- Add a new "Active when" section to General Settings with three independent Enabled/Disabled toggles, one per display context:
  - **Built-in only** — no external display connected.
  - **Built-in + external (dual)** — both the built-in display and an external display are active (lid open).
  - **External only (closed lid)** — the built-in display is off/absent and an external display is active (clamshell mode).
- All three default to **Enabled**, so existing installs see no behavior change until a user opts in.
- `FaceUnlockCoordinator.evaluateTrigger()` gates arming on the current context's setting: when the active context is Disabled, it disarms the overlay the same way the existing `isEnabled == false` path does. Touch ID and manual password entry are untouched — they don't run through this coordinator.
- Introduce a single, reusable screen-context resolver (built-in-only / dual / external-only) derived from `NSScreen.screens` + the existing `NSScreen.isBuiltIn`. This resolver is the source of truth for the new gate.
- **Optional cleanup, not required for this change to ship**: `CameraDeviceCatalog.isUsingBuiltInDisplay()` currently derives built-in/external from `NSScreen.main` (the focused screen), the same "follows focus, not the camera" bug fixed for the overlay's own screen selection in upstream PR #26. Migrating it to reuse the new resolver is tracked as an optional task.

## Capabilities

### New Capabilities
- `face-unlock`: When Face Unlock is allowed to arm and scan, given the coordinator is enabled, a lock/wake/space trigger fired, and a resolvable overlay screen exists. This proposal adds the display-context gate as a new requirement on top of that existing (undocumented) arming behavior.

### Modified Capabilities
(none — no existing specs predate this change)

## Impact

- **Code**: `FaceUnlockCoordinator.swift` (new guard in `evaluateTrigger()`), a new screen-context resolver (likely alongside `NotchGeometry.swift` or as its own file), `GlanceSettings.swift` (three new persisted toggles), `GeneralSettingsPage.swift` (new "Active when" section, styled like `CameraSettingsPage.swift`'s three-row picker pattern). Optionally `CameraDeviceCatalog.swift`.
- **Behavior**: Opt-in only — default state (`Enabled` everywhere) preserves current behavior exactly.
- **Risk**: The "External only" context relies on macOS excluding the built-in display from `NSScreen.screens` in true clamshell mode (lid closed + external attached). This needs empirical verification on real hardware; if it doesn't hold, "External only" and "Built-in + external" would be indistinguishable. Flagged in `design.md` as a spike to run before/during implementation.
