# Nembra 1.0 unified workstream ownership

Status: active integration contract for `release/nembra-1-0-unified`.

## Integration authority

The unified parent is the only writer that integrates lane commits, resolves conflicts, changes shared architecture, updates project/workflow wiring, synchronizes the canonical continuity record, and judges release acceptance.

Lane work returns as a bounded commit or patch with exact files, tests, evidence, and risks. No lane merges itself into the unified branch.

## Capture / BLE truth lane

Owned paths:

- `Packages/NembraBluetoothCapture/`
- Capture-only portions of `NembraApp/App/NembraCaptureEntrypoint.swift` and related Capture stores/build identity
- `NembraCaptureUITests/`
- `scripts/field/` and Capture-specific `scripts/ci/`
- Capture-specific workflows when explicitly assigned
- `docs/CAPTURE_BLUETOOTH_CONTINUITY.md`, `docs/ES80_PROTOCOL_MAP.md`, and canonical Capture procedure/provisioning docs

Boundaries:

- never edit Home/Cockpit presentation;
- never publish an unverified semantic decoder or write authority;
- never commit private Tuya inputs, credentials, identifiers, signed IPAs, raw sensitive evidence, or derived junk;
- publish stable typed contracts/fixtures to the unified parent before any UI lane consumes them.

## Portrait lane

Owned paths:

- `NembraApp/Features/Home/`
- portrait Rides, Vehicle, Settings, profile, and portrait-only secondary surfaces
- portrait-specific design system additions approved by the unified parent
- focused portrait tests and `docs/continuity/PORTRAIT_EXPERIENCE.md`

Boundaries:

- never edit `NembraApp/Features/Dashboard/` or cockpit orientation/session ownership;
- never parse raw Capture evidence or invent telemetry/range;
- request parent integration for `AppRootView.swift`, `NembraVisuals.swift`, shared app tests, shared UI tests, project files, or workflow changes.

## Cockpit lane

Owned paths:

- `NembraApp/Features/Dashboard/`
- Drive and later Navigation/Explore presentation/data seams explicitly assigned by the parent
- cockpit-only tests, performance evidence, and `docs/continuity/COCKPIT_*.md`

Boundaries:

- never edit portrait composition;
- never decode BLE or promote Simulator values to physical truth;
- request parent integration for `AppBootstrap.swift`, `AppRootView.swift`, shared app/UI tests, project files, or workflow changes;
- do not widen into Navigation or Explore before the current Drive gate is met.

## Parent-owned shared paths

The unified parent owns all overlapping integration surfaces, including:

- `DEVELOPMENT_CONTINUITY.md`
- `NembraApp/App/AppBootstrap.swift`
- `NembraApp/App/AppRootView.swift`
- `NembraApp/App/DashboardSessionStore.swift`
- `NembraApp/DesignSystem/NembraVisuals.swift`
- `NembraAppTests/NembraAppTests.swift`
- `NembraUITests/NembraUITests.swift`
- `Nembra.xcodeproj/`, schemes, and shared workflows/scripts
- cross-lane model/persistence contracts and PR descriptions/checklists

## Conflict and evidence rule

1. Preserve the newest truth/safety contract even when an older lane snapshot appears cleaner.
2. Resolve shared tests by keeping the union of substantive assertions; never delete a gate merely to make integration compile.
3. Keep simulation visibly synthetic and physically namespaced.
4. Local Xcode 26 is diagnostic only. GitHub-hosted Xcode 27/iPhone 12/iOS 27 is the build, UI, screenshot, accessibility, and performance authority.
5. Physical BLE, background lifecycle, and outdoor behavior require separate real-device evidence.
