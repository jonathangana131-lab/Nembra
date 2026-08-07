# Home Vehicle Status Field

Worker: `chat-m8q4v`
Lane: `home-vehicle-status-field`

## Purpose

This is the focused production-design contract for the next Home hierarchy slice. It narrows the merged production visual audit into one implementable surface without changing vehicle truth, battery/range behavior, ride evidence, Bluetooth semantics, or command safety.

The current Home composition presents vehicle identity in `vehicleHeader`, then conditionally inserts a separate rounded `connectionRecovery` strip before the status metrics. That is factually correct, but the merged production visual audit found that connection problem states remain too compositionally similar and that Home still reads as a stack of cards/sections instead of one vehicle-state-driven product surface.

This slice therefore defines one compact **vehicle status field** that owns:

- vehicle identity;
- connection state / connection issue;
- lock state when known;
- the one context-appropriate recovery action when one exists.

It does **not** absorb battery, trip, mode, ride statistics, or deeper controls. Those remain separate until their accepted product dependencies are ready.

## Source-backed current behavior to preserve

Current `HomeView` already preserves several important truth boundaries:

- connection issues are explicit (`Bluetooth Off`, `Permission Needed`, `Not Found`, `Unsupported Configuration`);
- reconnecting is not shown as connected;
- retained vehicle values can be labeled as last-known data;
- reconnect is an explicit user action where appropriate;
- Bluetooth permission recovery opens Settings rather than pretending the app can repair permission itself;
- lock state is shown only when known;
- vehicle commands remain disabled unless the vehicle state and command gate permit them.

The new visual hierarchy must preserve all of those facts.

## Product hierarchy

The status field is a single visual region with three layers.

### Layer 1 — identity

Always visible:

- model display name;
- compact connection indicator;
- concise connection/issue label;
- lock state only when known.

Identity remains readable even when the scooter is offline.

### Layer 2 — attention state

Only appears when attention is warranted.

It uses the existing `connectionIssue` / `connection` truth; it does not infer a new transport state.

Priority order:

1. unsupported configuration — highest attention because Nembra intentionally refuses unverified control semantics;
2. Bluetooth permission denied — user action required outside Nembra;
3. Bluetooth powered off — external radio state prevents connection;
4. scooter unavailable — retry may be useful;
5. connecting / reconnecting — progress state, not an error;
6. cold disconnected / offline — retry may be useful.

This priority is presentation hierarchy only. It must never rewrite or persist vehicle-domain truth.

### Layer 3 — contextual action

At most one recovery action belongs in the status field:

- permission denied → open Nembra Settings;
- scooter unavailable → reconnect;
- disconnected without a more specific issue → reconnect;
- connecting / reconnecting → progress affordance only;
- Bluetooth powered off → no fake in-app fix;
- unsupported configuration → no command/retry affordance that implies the hardware is supported.

No secondary action row should be added merely to fill space.

## Visual rules

The merged production audit explicitly warns against solving Home by making larger cards or adding decorative scooter art. The status field should instead create hierarchy with spacing, type, alignment, restrained material, and attention emphasis.

Requirements:

- identity + connection + lock read as one cluster rather than a header plus a second recovery card;
- normal connected state is quiet and consumes minimal vertical space;
- connecting/reconnecting is visually active but not alarming;
- permission / unsupported states have stronger glance-level priority than ordinary offline state;
- use semantic color sparingly; do not flood the entire surface red/orange;
- avoid another full-width rounded rectangle if the surrounding Home composition already provides sufficient grouping;
- preserve a minimum 44 pt interactive target for a recovery action;
- long messages must wrap under Accessibility Dynamic Type without forcing the action off-screen;
- no connection-state animation may imply transport progress that the domain did not confirm.

## Copy contract

Keep current factual intent. Exact final copy can be polished during implementation, but must not become more certain than the existing state.

| Domain state | Primary status | Supporting meaning | Action |
| --- | --- | --- | --- |
| connected | Connected | confirmed vehicle connection | none |
| connected + moving | Riding + authoritative formatted speed if already available | confirmed connected/moving presentation | none |
| connecting | Connecting | establishing confirmed connection | progress |
| reconnecting | Reconnecting | retained values remain read-only until confirmed | progress |
| disconnected | Scooter offline | controls remain read-only until confirmed | Reconnect |
| bluetoothPoweredOff | Bluetooth is off | Bluetooth must be enabled externally | none |
| bluetoothPermissionDenied | Bluetooth access is off | user must grant access in Settings | Settings |
| scooterUnavailable | Scooter not found | powered-on / nearby retry guidance | Reconnect |
| unsupportedConfiguration | Scooter software not recognized | controls intentionally unavailable until verified | none |

For connecting/reconnecting, the identity status is the single authoritative visible/accessible title. The recovery portion supplies supporting copy plus a decorative spinner; it must not repeat the same state title again.

If product copy changes, tests should assert semantics/identifiers rather than brittle punctuation unless wording itself is a safety contract.

## Retained-data relationship

`Last known vehicle data` remains attached to the data it qualifies, not to the status field alone.

The status field may explain reconnecting/offline state, but it must not visually make retained battery/trip/mode values look live. Existing `VehicleDataAvailability.retained` behavior remains authoritative.

## Accessibility contract

The status field must form a useful VoiceOver sequence without duplicating the same state several times.

Expected reading order:

1. vehicle model;
2. connection / issue status;
3. lock state when known;
4. concise recovery explanation when present;
5. recovery action when present.

Requirements:

- do not announce a colored dot as a separate unlabeled element;
- connecting/reconnecting use the identity status as the one authoritative progress-state title;
- the progress spinner is decorative / accessibility-hidden because the state is already expressed truthfully in text;
- the progress recovery row exposes supporting copy only, avoiding duplicate `Connecting` / `Reconnecting` semantics;
- reconnect/settings actions keep explicit labels;
- unknown lock state is omitted, not announced as unlocked;
- Dynamic Type must allow the supporting message to wrap naturally;
- Reduce Motion must not remove state information.

### Implemented accessibility-size recomposition

The independent production Dynamic Type audit identified two horizontal squeeze risks inside this slice: vehicle identity competing with the lock capsule, and recovery prose competing with the trailing action.

The status-field implementation therefore uses `dynamicTypeSize.isAccessibilitySize` only for those two owned compositions:

- identity + known lock state switch from a horizontal layout to a leading vertical layout at accessibility text sizes;
- recovery icon + copy + contextual action switch from a horizontal layout to a leading vertical layout at accessibility text sizes;
- default text sizes retain the original horizontal geometry;
- recovery controls remain explicit 44×44 pt targets.

A later independent correctness review also proved that the prior progress presentation repeated `Connecting` / `Reconnecting` in the header, recovery title, and spinner accessibility label. The implementation now keeps the header status authoritative, omits the duplicate progress recovery title, and hides the spinner from accessibility while preserving its visual progress affordance.

This is deliberately **not** a claim that all of Home is Dynamic Type-complete. The separate audit flags pre-existing Battery/Trip/Mode columns, fixed-height action controls, and ride-mode geometry outside this focused status-field slice. Those must be addressed by a later Home accessibility packet rather than silently expanding this PR.

## Motion / haptics

Motion is secondary to truth.

Permitted:

- restrained content transition when the textual status changes;
- progress indicator for actual connecting/reconnecting states;
- normal native button feedback for explicit reconnect/settings actions.

Not permitted:

- fake scanning pulses when no scan state is exposed;
- animated connection-strength bars without measured RSSI semantics;
- success haptic before the connection/command domain confirms success;
- repeating alert haptics for persistent offline states.

## Implementation boundary

Preferred first implementation keeps the change inside `NembraApp/Features/Home/HomeView.swift` so it does not contend with the active root-shell lane or battery/Dashboard lanes.

The implementation should:

1. replace the separate `vehicleHeader` + `connectionRecovery` composition with one status-field composition;
2. reuse the existing `connectionRecoveryPresentation` truth mapping or an equivalent local value model;
3. leave `statusPanel`, battery rendering, command calls, mode controls, retained-data logic, and vehicle detail rows semantically unchanged;
4. avoid `AppRootView.swift`, `VehicleControlsView.swift`, `Nembra.xcodeproj/project.pbxproj`, shared persistence, BLE packages, and global project-memory docs;
5. add or extend UI assertions only if a non-contending test surface is available at implementation time.

If the active shell or UI-test workers begin touching `HomeView.swift`, this lane must pause implementation and reconcile ownership rather than creating a competing Home architecture.

## Acceptance matrix

The exact implementation head must be exercised on iPhone 12 / iOS 27 Simulator in at least these states:

- connected, stopped, light appearance;
- connected, stopped, dark appearance;
- riding;
- reconnecting with retained data;
- cold disconnected;
- Bluetooth off;
- Bluetooth permission denied;
- scooter unavailable;
- unsupported configuration;
- Accessibility Dynamic Type for a long issue message;
- VoiceOver semantic inspection;
- Reduce Motion.

Visual acceptance questions:

- Does identity/connection/lock read as one vehicle-state cluster?
- Is the ordinary connected state quieter than attention states?
- Can permission/unsupported states be distinguished at a glance without reading every word?
- Is retained data still unmistakably last-known?
- Are recovery actions obvious and at least 44 pt without becoming dominant cards?
- Does the status field reduce repeated rounded-container hierarchy rather than adding another layer?
- Do connecting/reconnecting avoid repeating their status title while still communicating progress clearly?
- Does the screen remain truthful when battery/range is unavailable or unverified?

## Truth / hardware boundary

This lane is UI hierarchy only.

It does not verify or alter:

- physical AOVOPRO ES80 connection behavior;
- BLE identity, GATT, Tuya framing, or DP semantics;
- battery percentage source/resolution;
- adaptive range;
- vehicle command acknowledgements;
- ride/location evidence;
- physical iPhone performance.

Simulator acceptance proves software presentation only, never physical ES80 behavior.
