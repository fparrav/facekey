## Purpose

Defines when Face Unlock is allowed to arm and scan for a face, including the display-configuration conditions a user can set to enable or disable it independently of the global on/off switch.

## ADDED Requirements

### Requirement: Display context classification
The system SHALL classify the current display configuration into exactly one of three contexts at any moment:
- **Built-in only**: the built-in display is active and no external display is active.
- **Built-in + external**: the built-in display and at least one external display are both active.
- **External only**: no built-in display is active and at least one external display is active.

#### Scenario: Laptop lid open, no external display
- **WHEN** only the built-in display is active
- **THEN** the system classifies the current context as "Built-in only"

#### Scenario: Laptop lid open, external display connected
- **WHEN** the built-in display and an external display are both active
- **THEN** the system classifies the current context as "Built-in + external"

#### Scenario: Laptop lid closed, external display connected
- **WHEN** the built-in display is off/absent and an external display is active
- **THEN** the system classifies the current context as "External only"

### Requirement: Per-context Face Unlock activation setting
The system SHALL provide an independent Enabled/Disabled setting for each of the three display contexts, persisted across launches. Each setting SHALL default to Enabled.

#### Scenario: Fresh install has no behavior change
- **WHEN** a user who has never touched the new settings unlocks their Mac in any display context
- **THEN** Face Unlock arms exactly as it did before this capability existed, because all three contexts default to Enabled

#### Scenario: User disables a specific context
- **WHEN** a user sets "Built-in only" to Disabled and leaves the other two contexts Enabled
- **THEN** only the "Built-in only" context's setting changes; "Built-in + external" and "External only" remain Enabled

### Requirement: Face Unlock arming gated by display context
The system SHALL NOT arm Face Unlock scanning for a lock/wake/space trigger while the current display context's setting is Disabled. Other unlock paths (Touch ID, manual password entry) are unaffected by this gate.

#### Scenario: Trigger fires while current context is disabled
- **WHEN** a lock, wake, or "on space" trigger fires and the current display context's setting is Disabled
- **THEN** the system does not open the camera or show the scanning overlay, and any in-flight scan is cancelled

#### Scenario: Trigger fires while current context is enabled
- **WHEN** a lock, wake, or "on space" trigger fires and the current display context's setting is Enabled
- **THEN** Face Unlock arms and scans as it does today, unaffected by this capability

#### Scenario: Disabled context does not block other unlock methods
- **WHEN** the current display context's setting is Disabled and the user is at the lock screen
- **THEN** Touch ID and typing the Mac password continue to work normally
