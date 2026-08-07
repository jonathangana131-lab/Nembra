# Production Assistive Control Audit — 2026-08-06

Worker: `chat-n4c7p`  
Lane: `production-assistive-control-audit`  
Protocol: Nembra Swarm OS v7

## Purpose

Define a source-backed production acceptance contract for Nembra's non-touch operation through **Voice Control** and **Switch Control**, with related checks for naming, focus/scanning, action discoverability, orientation changes, and safe motorized-command semantics.

This is a **review/hardening document only**. It changes no production code or tests and does not claim physical-device Voice Control or Switch Control acceptance that has not been performed.

## Evidence basis

This audit starts from `main@58cc7802bd1d56e316a30a3d8ccc5b8cb45d8157` and reviews the current interactive surfaces in:

- `NembraApp/Features/Home/HomeView.swift`;
- `NembraApp/Features/Dashboard/DashboardView.swift`;
- `NembraApp/Features/Home/VehicleControlsView.swift`;
- `NembraApp/App/AppRootView.swift`;
- current merged Dynamic Type, Reduce Motion, color/contrast, and Ride History accessibility findings;
- the current iPhone 12 / iOS 27 Simulator visual/test harness as evidence of what it can and cannot prove.

The source review intentionally stops short of modifying active Home, Dashboard, AppRoot, Vehicle Controls, route/map, battery, or UI-test lanes.

## Current Apple assistive-control contract checked 2026-08-06

Current Apple guidance establishes several relevant release expectations:

- Voice Control is intended to let a user navigate and interact using spoken commands.
- For an app to claim Voice Control support in App Store accessibility information, users should be able to complete the app's common tasks and actions using voice alone.
- Voice Control's `Show numbers` and `Show names` overlays should expose actionable controls; visible names and accessible spoken names should remain understandable and consistent.
- Apple explicitly calls out `accessibilityInputLabels(_:)` as a way to provide additional speech-recognition labels where useful.
- A long press, swipe, or other gesture-only action needs a speech-accessible alternative when that action is part of a common task.
- Switch Control should let users navigate to, select, and activate interface elements without depending on direct touch.
- Apple recommends sufficiently sized controls, simple/consistent interactions, and testing the mobility-related assistive technologies relevant to the app.
- Apple's current accessibility-testing guidance requires **physical-device testing** for Voice Control and Switch Control. Simulator UI labels and XCTest coverage cannot by themselves prove either assistive technology works end to end.

References:

- https://developer.apple.com/design/human-interface-guidelines/accessibility
- https://developer.apple.com/documentation/accessibility/voice-control
- https://developer.apple.com/documentation/accessibility/switch-control
- https://developer.apple.com/documentation/accessibility/performing-accessibility-testing-for-your-app
- https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voice-control-evaluation-criteria/

These are platform acceptance requirements, not proof that current Nembra passes them.

## Strong current foundations

### 1. Most primary interactions use native semantic controls

The current high-value paths are predominantly composed from SwiftUI `Button`, `NavigationLink`, `TabView`, `List`, `Form`, `Section`, `LabeledContent`, alerts, and confirmation dialogs rather than custom gesture recognizers.

That is a strong starting point for both Voice Control and Switch Control because the system receives explicit interactive elements instead of having to infer actions from arbitrary visual containers.

### 2. Icon-only controls generally have explicit accessibility names

Examples on current `main` include:

- Home toolbar: `Vehicle controls`;
- Home recovery icon: `Reconnect scooter`;
- Home Settings icon: `Open Nembra settings`;
- Dashboard light: `Turn light on` / `Turn light off`;
- Dashboard lock: `Lock scooter` / `Unlock scooter`.

Those labels are materially better than unlabeled glyph-only actions and should remain stable through the Production Visual Overhaul.

### 3. Visible full-text controls usually align with their accessibility names

Home ride-mode controls display the full mode name and use the same full name as their accessibility label. Vehicle Controls uses visible text such as `Reconnect`, full ride-mode names, `Off` / `On`, and full Start Behavior names inside native buttons.

This gives Voice Control a relatively low-ambiguity baseline on those surfaces.

### 4. Current audited primary actions are not hidden behind custom gestures

No custom tap-, swipe-, or long-press-only primary action was observed in the current Home, Dashboard, Vehicle Controls, or Ride History interaction paths reviewed for this packet. Primary actions are represented by buttons, links, tabs, or system dialogs.

This is a source-level observation for these audited surfaces, not a repository-wide guarantee and not runtime assistive-control proof.

### 5. Safety-critical scooter actions already have application-domain gating

Current UI controls already respect connection state, pending-command state, availability, stopped/moving gating where applicable, and confirmation for lock changes.

Any future accessibility custom action or alternate assistive path must call the **same existing gated application action**. Accessibility must never become an alternate write path that bypasses disabled state, confirmation, pessimistic acknowledgement, or other motorized-command safety/truth boundaries.

## Findings and risks

### P1 — current Simulator QA cannot close Voice Control or Switch Control acceptance

Nembra has valuable iPhone 12 / iOS 27 Simulator UI evidence, but Apple documents Voice Control and Switch Control testing as physical-device workflows.

Therefore:

- an accessibility label in source is not proof that Voice Control can activate the control;
- an XCTest tap is not proof that Switch Control can scan to and activate it;
- Simulator screenshot evidence is not a substitute for the physical assistive-control task matrix below.

**Acceptance requirement:** before Nembra claims production Voice Control or Switch Control support, execute the representative common-task matrix on a physical supported iPhone running the target iOS 27 build.

Physical iPhone assistive-control evidence remains **software/UI interaction evidence**. It does not become physical AOVOPRO ES80 protocol or command verification.

### P1 — Dashboard abbreviated visible mode names do not match their current accessible names

The stopped Dashboard visually shows mode controls as:

- `W`
- `E`
- `D`
- `S`

while each button's accessibility label is the full mode name (`Walk`, `Eco`, `Drive`, `Sport`).

The full name is better descriptive accessibility text, but current Apple Voice Control criteria emphasize keeping speech-facing names aligned with visible text so a user can say what they see.

A sighted Voice Control user may reasonably say `Tap W` while the accessibility tree exposes `Walk`.

**Acceptance requirement:** the Dashboard owner should preserve the descriptive full mode name while making the visible abbreviation a valid Voice Control utterance where needed. `accessibilityInputLabels(_:)` is the platform mechanism specifically worth evaluating for aliases such as the visible abbreviation plus the full name. Do not weaken VoiceOver semantics merely to mirror a one-letter visual abbreviation.

Runtime acceptance must verify both `Show names` and actual spoken activation on the physical device.

### P1 — small custom Dashboard controls need physical target/scan evidence

Current Dashboard mode labels use explicit 34×34 visual frames and light/lock glyph labels use 36×36 visual frames before glass styling. Home ride-mode controls use a 42 pt explicit visual height.

Those source values identify a **risk**, not a proven hit-target failure: SwiftUI styles and container behavior can affect the effective interactive region.

The merged Dynamic Type audit already flags Dashboard fixed geometry/touch-target pressure. Assistive-control acceptance should add:

- physical `Show numbers` / `Show names` verification that each individual control is targetable;
- Switch Control item-scan verification that each control is independently reachable;
- Accessibility Inspector or runtime hit-region evidence where target size is uncertain;
- no accidental merging of adjacent mode controls into one unusable target.

If runtime evidence fails, the owning Dashboard lane should expand the actual interaction target without changing the compact visual hierarchy more than necessary.

### P1 — route-map assistive interaction is unproven

Ride Details presents a native MapKit `Map` when validated route geometry is drawable, followed by textual coverage/point/gap evidence.

Current source does not prove:

- how Voice Control names or exposes the map interaction surface;
- whether Switch Control scanning enters or becomes trapped in map subcontrols;
- whether map pan/zoom is necessary to complete any current common Ride Details task;
- whether a non-touch user can obtain all meaningful route evidence without interacting with the map itself.

The app already displays truthful textual route coverage/count/gap evidence outside the map. That is a strong fallback foundation. Future route accessibility work must not invent place names, infer an unrecorded path, bridge a known gap, or convert map gestures into stronger route truth.

**Acceptance requirement:** physically test Ride Details with Voice Control and Switch Control. If interactive map manipulation is not required for the product task, ensure the map does not create a focus/scanning trap. If it is required, expose a legitimate assistive path without weakening route-evidence truth.

Route semantics remain owned by the route-evidence / Ride History integration lanes; this audit does not duplicate their implementation.

### P1 — disabled/pending motorized controls must not become alternate assistive actions

Voice Control and Switch Control should expose the same legitimate actions a direct-touch user can perform — not more.

For every future custom accessibility action, shortcut, input label, or alternate activation path:

- disconnected/unsupported commands remain unavailable;
- pending commands remain guarded;
- moving-state restrictions remain enforced;
- lock confirmation remains required when the touch UI requires it;
- a system assistive action must never directly mutate displayed state to imply scooter acknowledgement;
- command failure must remain truthful and recoverable.

This is both an accessibility and motorized-product safety requirement.

### P1 — both portrait and landscape control graphs need acceptance

`AppRootView` changes the primary app surface based on vertical size class:

- portrait presents Home/Rides tab navigation;
- compact/landscape presents the Dashboard cockpit.

That means one assistive-control test in portrait cannot certify the app. Physical-device acceptance must include rotation/orientation transitions and verify that focus/selection does not become stranded when the control graph changes.

### P2 — Home is a relatively strong source baseline, but common-task proof is still missing

Home uses native buttons/links, descriptive icon-only labels, and full visible ride-mode names. Its immediate light/lock actions are ordinary Buttons with visible text. Recovery actions have explicit labels.

Remaining acceptance work is runtime-focused:

- `Show names` / `Show numbers` exposes every actionable element;
- light/lock/mode actions activate by voice without ambiguous names;
- Switch Control scans the sections in a logical order;
- command progress/disabled states remain understandable;
- the lock confirmation dialog can be cancelled and confirmed without touch;
- scrolling reaches the final Vehicle Controls link without focus loss.

The active Home visual lane owns any resulting product changes.

### P2 — Vehicle Controls is lower risk because it is predominantly native Form UI

Vehicle Controls uses visible native buttons and full labels for reconnect, ride mode, cruise, and start behavior. This is the lowest custom assistive-control risk among the audited interactive surfaces.

It still requires physical task testing because native semantic structure is not itself an end-to-end certification, especially for disabled/pending states and navigation into/out of the pushed screen.

### P2 — Ride History row semantics are already under a separate incumbent fix

Current `main` still has a completed-row VoiceOver phrase that repeats continuity for ordinary completed rides. Dependent PR #75 owns the narrow de-duplication of that row announcement after its shell parent lands.

This assistive-control lane does not duplicate that edit. Voice Control/Switch Control acceptance should consume the final accepted row semantics and verify that each completed Ride History row is a single discoverable navigation action.

## Risk / ownership matrix

| Surface | Current assistive-control shape | Risk | Required evidence | Ownership boundary |
| --- | --- | --- | --- | --- |
| Home | Native buttons/links, explicit icon labels, full visible mode names | medium | physical Voice Control + Switch Control common-task matrix | active Home owner |
| Dashboard | Compact custom glass buttons; W/E/D/S visible vs full accessible names | high | physical names/numbers, alias activation, target/scan geometry, stopped/moving states | Dashboard/battery visual owner |
| Vehicle Controls | Native Form + visible buttons | low-medium | physical scan/voice regression across enabled/disabled/pending states | Vehicle Controls / shell owner |
| Portrait tabs | Native Home/Rides TabView | low | physical tab switching + focus preservation | shell/root owner |
| Ride History | Native List/NavigationLink; row semantic fix separately active | medium | row discovery/activation and scrolling after accepted row semantics | Ride History owner |
| Ride Details map | Native Map + truthful textual route evidence | high | physical focus/scan behavior; no map trap; no invented route semantics | route/map integration owner |
| Landscape transition | Entire control graph changes to Dashboard | high | rotate with Voice/Switch active; focus/selection remains usable | shell + Dashboard integration |
| Future battery/range | interactive signature readout/toggle still evolving | high | visible/spoken naming, toggle activation, truthful unavailable/learning states | battery/readout owner |
| Future navigation | map/guidance controls not production-integrated yet | high | full non-touch common-task path without unsafe route claims | navigation/Dashboard integration |

## Physical-device common-task matrix

The goal is not to exhaust every state permutation. It is to prove the common user workflows and the highest-risk custom controls.

### Portrait / Home

Using a safe software state or legitimate non-motorized test setup where possible:

1. switch to the Home tab;
2. open Vehicle Controls from the top toolbar;
3. return to Home;
4. activate reconnect or Settings recovery when that state is legitimately present;
5. activate the light control when available;
6. initiate the lock action, reach its confirmation dialog, cancel it, then verify the confirmation action path separately under a safe test condition;
7. select each supported ride mode;
8. scroll to and open `All Vehicle Controls`;
9. verify pending/disabled/unavailable states do not expose a bypass action.

### Vehicle Controls

1. navigate through the Form by assistive control;
2. activate reconnect/Settings when legitimately available;
3. select a ride mode;
4. select Cruise Off/On only in a safe verified software scenario;
5. select a Start Behavior option only in a safe verified software scenario;
6. verify selected/disabled/pending states remain understandable and cannot be bypassed.

### Rides / Ride Details

1. switch to the Rides tab;
2. scroll Ride History;
3. activate an individual completed row;
4. navigate all timeline/distance/route evidence;
5. verify the map does not trap assistive focus or scanning;
6. return to Ride History and Home without direct touch.

### Landscape Dashboard

1. rotate into Dashboard while assistive control is active;
2. identify current battery/trip/mode/connection information;
3. while stopped, identify and activate each mode control;
4. identify and activate light/lock actions when safe;
5. traverse and dismiss/confirm the lock dialog safely;
6. verify the moving state removes or disables motorized controls consistently rather than leaving a hidden assistive bypass;
7. rotate back to portrait and verify usable focus/selection recovery.

## Voice Control acceptance procedure

Run on a physical supported iPhone with the exact release-candidate build:

1. Enable Voice Control.
2. Use `Show numbers` and verify every actionable item on the current screen can be individually targeted.
3. Use `Show names` and verify meaningful names are exposed without duplicate/ambiguous collisions.
4. Where visible text exists, speak the visible text and confirm it activates the expected item.
5. For Dashboard `W/E/D/S`, verify the visible abbreviation and full descriptive mode name both work if aliases are intentionally supported.
6. Complete the common-task matrix without touching the display.
7. Exercise alerts/confirmation dialogs, disabled states, progress states, tabs, lists, scrolling, and orientation changes.
8. Verify no voice path bypasses command gating, confirmation, or acknowledgement semantics.

Record:

- exact app SHA;
- physical device model;
- iOS 27 build;
- Voice Control language;
- screen/orientation;
- scenario state;
- failures/ambiguous labels;
- whether `Show names` and `Show numbers` both exposed every actionable element.

## Switch Control acceptance procedure

Run on a physical supported iPhone with a configured switch input:

1. Enable Switch Control using a safe test switch configuration.
2. Scan through each high-value screen in the common-task matrix.
3. Verify each actionable item is reached exactly as an independent usable action where intended.
4. Verify scan order follows a comprehensible visual/task order.
5. Verify ScrollView/List content can be advanced without losing the ability to return to earlier navigation.
6. Verify dialogs, tabs, navigation links, Home controls, Dashboard stopped controls, and Ride History rows activate correctly.
7. Verify MapKit content does not trap item scanning.
8. Rotate portrait ↔ landscape and verify the selection system recovers to a usable state.
9. Verify disabled/pending motorized controls cannot be activated through the assistive path.

Record the same exact SHA/device/iOS/scenario metadata as Voice Control acceptance.

## Naming policy for future visual work

The Production Visual Overhaul should preserve these rules:

- visible text is the default Voice Control phrase when it already describes the action well;
- icon-only controls receive concise action-oriented accessible names;
- do not rename a visible control in accessibility metadata merely for style;
- when the best VoiceOver description differs from compact visible text, evaluate `accessibilityInputLabels(_:)` so speech can accept both the visible phrase and a useful descriptive alias;
- avoid multiple nearby controls with indistinguishable names;
- pending-state copy may change, but the stable task/action name should remain recognizable;
- never encode unverified scooter telemetry or physical state into a speech label.

## Assistive action safety policy

Accessibility is an input modality, not a second command architecture.

Any future VoiceOver custom action, Voice Control input label, Switch Control path, App Shortcut, or other accessibility interaction that reaches scooter commands must delegate to the same application/domain operation used by direct touch.

It must not:

- call a lower-level BLE/Tuya write directly;
- bypass stopped/moving restrictions;
- bypass capability checks;
- bypass connection/pending state;
- bypass confirmation;
- optimistically mutate confirmed state;
- promote Simulator evidence into physical ES80 support.

## Current verdict

Current Nembra source has a **good semantic foundation** for assistive control: primary actions are mostly native controls, icon-only actions are generally labeled, Home/Vehicle Controls use visible descriptive names, and the audited primary flows do not currently depend on custom gesture-only interaction.

Nembra should **not yet claim production Voice Control or Switch Control support**, because the required physical-device common-task evidence does not exist in the current acceptance record.

The highest-priority source-level follow-ups are:

1. resolve/verify Dashboard `W/E/D/S` visible-name versus full accessible-name behavior using physical Voice Control and input-label aliases where needed;
2. prove actual Dashboard mode/light/lock target and Switch Control scan geometry;
3. prove Ride Details MapKit does not trap or block non-touch navigation;
4. test portrait ↔ landscape control-graph changes with the assistive technology active;
5. keep every assistive motorized action on the same truthful gated command path as direct touch.

## Truth / hardware boundary

This audit changes no app UI, telemetry, battery/range model, ride evidence, route geometry, persistence, Bluetooth/Tuya behavior, or motorized command path.

A future physical-iPhone Voice Control/Switch Control pass would validate the **app's assistive interaction behavior** for that build. It would not, by itself, verify physical AOVOPRO ES80 BLE semantics, command acknowledgements, battery telemetry, ride behavior, or hardware safety.
