# Production VoiceOver Audit — 2026-08-06

Worker: `chat-n4c7p`  
Lane: `production-voiceover-audit`  
Protocol: Nembra Swarm OS v7

## Purpose

Define a source-backed production VoiceOver acceptance contract for Nembra while preserving the app's strict measured / estimated / displayed / derived / unknown truth boundaries.

This is a **review/hardening document only**. It does not modify active Home, Dashboard, AppRoot, Vehicle Controls, route/map, battery, speed, or UI-test files. PR #75 retains ownership of its narrow Ride History row announcement fix.

## Evidence basis

This audit is based on the product tree at `main@f77e36c6e37b4f4001638fa7cd3b97a972805d43`, including:

- `NembraApp/Features/Home/HomeView.swift`;
- `NembraApp/Features/Home/VehicleControlsView.swift`;
- `NembraApp/Features/Dashboard/DashboardView.swift`;
- `NembraApp/Features/Dashboard/RollingSpeedValueView.swift`;
- `NembraApp/Features/Dashboard/SpeedInstrumentModel.swift`;
- `NembraApp/App/AppRootView.swift`;
- current merged Dynamic Type, Reduce Motion, color/contrast, and assistive-control audit findings;
- the narrow Ride History accessibility implementation currently owned by PR #75.

This packet reviews source semantics and current Apple guidance. It does **not** claim that VoiceOver has been exercised on a physical iPhone for the current exact app head.

## Current Apple VoiceOver contract checked 2026-08-06

Current Apple guidance establishes these relevant acceptance expectations:

- an app should not claim VoiceOver support unless users can complete all common tasks using VoiceOver without sighted assistance;
- visible/important information should be available through VoiceOver;
- controls need concise, accurate descriptions and correct state information;
- navigation should be complete, logical, and free of loops or traps in both forward and reverse order;
- groups should be structured so their information and actions make sense when traversed by VoiceOver;
- background refreshes should not unexpectedly reset the user's reading position;
- temporary important status information should be conveyed in a timely, non-disruptive way rather than depending only on a visual banner;
- Accessibility Inspector and automated accessibility audits are useful but do not replace testing the actual app with VoiceOver;
- Apple's current testing documentation says VoiceOver testing must be performed on a **physical device**, because VoiceOver is not available in Simulator.

References:

- https://developer.apple.com/documentation/accessibility/voiceover
- https://developer.apple.com/documentation/uikit/supporting-voiceover-in-your-app
- https://developer.apple.com/documentation/accessibility/performing-accessibility-testing-for-your-app
- https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app
- https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voiceover-evaluation-criteria/

These are acceptance criteria, not proof that current Nembra passes them.

## Strong current foundations

### 1. Dashboard speed preserves telemetry truth for VoiceOver

This is the strongest current VoiceOver-specific design in the reviewed source.

`RollingSpeedValueView` is presentation-only. In `DashboardSpeedInstrumentView`:

- the rolling numeric glyphs are `accessibilityHidden(true)`;
- the visual speed unit is also hidden from VoiceOver;
- the visual row is replaced by one combined accessibility element labeled `Speed`;
- its accessibility value comes from `accessibilitySpeed(frame:)`;
- that function prefers `latestMeasuredKilometersPerHour` and otherwise falls back to confirmed `VehicleState` speed;
- the visually interpolated midpoint is never the VoiceOver value.

That exactly matches Nembra's product truth rule: render interpolation may look smooth, but assistive output should describe current authoritative/confirmed information rather than narrating frames that no sensor measured.

This contract must survive all future speed-instrument redesigns.

### 2. Major metric groups expose semantic label/value pairs

Current Home metrics and Dashboard battery/trip/mode metrics use explicit accessibility grouping and label/value semantics instead of forcing VoiceOver to traverse decorative icons, digit fragments, or section chrome.

Examples include:

- `Battery` + current displayed battery value;
- `Scooter Trip` + trip value;
- `Ride mode` + current mode;
- Dashboard `Speed` + authoritative/confirmed speed.

This is preferable to reading each visual subcomponent separately.

### 3. Decorative Dashboard mode personality is not mistaken for state evidence

The mode marker capsule is explicitly hidden from accessibility, while the semantic mode readout exposes the confirmed mode name. Visual opacity/scale/marker-width changes are therefore not promoted into separate VoiceOver facts.

### 4. Native system navigation and controls provide a solid baseline

Home/Rides tabs, NavigationLinks, Forms, Lists, Buttons, alerts, confirmation dialogs, and LabeledContent are heavily used throughout the current app. These system controls are a strong baseline for traits, actions, and navigation order compared with replacing them with custom gesture-only containers.

### 5. Important icon-only actions generally have explicit names

Current examples include:

- `Vehicle controls`;
- `Reconnect scooter`;
- `Open Nembra settings`;
- `Turn light on` / `Turn light off`;
- `Lock scooter` / `Unlock scooter`.

This should remain a hard requirement during the Production Visual Overhaul.

## Findings and risks

### P1 — physical-device VoiceOver acceptance is still missing

Source semantics, accessibility identifiers, Simulator screenshots, Accessibility Inspector, and XCTest audits are all useful evidence, but Apple explicitly documents physical-device testing for VoiceOver.

Therefore Nembra must not treat any of these as equivalent to completing the actual app workflow with VoiceOver and Screen Curtain on.

**Acceptance requirement:** run the physical-device common-task matrix below on the exact candidate build before claiming production VoiceOver support.

A physical iPhone VoiceOver pass validates app interaction for that build. It does not validate physical AOVOPRO ES80 BLE packets, motorized commands, battery telemetry, or ride-field behavior.

### P1 — ride-mode selection state is visually strong but not explicitly encoded on the individual mode buttons

Home and Dashboard both expose the current mode in a separate semantic readout. That is good.

However, the individual mode-selection Buttons rely primarily on visual selected styling:

- Home changes selected background, weight, and foreground;
- Dashboard changes selected background, text weight, and foreground;
- each button has an accessibility label equal to the mode name;
- the current source does not explicitly add a selected trait or selected accessibility value to each mode button.

A VoiceOver user navigating the choices should not need to leave the control group and find a separate readout merely to determine which choice is selected.

**Acceptance requirement:** on a physical device, verify whether SwiftUI/native button semantics already announce the selected state. If not, the owning Home/Dashboard lane should add a truthful selected-state semantic to the choice itself while preserving the existing confirmed-mode authority. Pending mode must not be announced as selected before acknowledgement.

### P1 — Vehicle Controls choice rows also need explicit selected-state acceptance

Vehicle Controls visually marks selected ride-mode, Cruise, and Start Behavior choices with a checkmark. The reusable `confirmedChoiceRow` also disables the currently selected choice.

Current source does not explicitly attach a selected accessibility trait/value to those rows.

**Acceptance requirement:** verify the physical VoiceOver phrase for selected and pending choices. A user should hear the choice name and its confirmed state without depending on seeing the checkmark. Pending state must remain distinct from confirmed selected state.

### P1 — command pending/failure state must be understandable without converting visual progress into false confirmation

Home and Dashboard sometimes replace an icon with `ProgressView` while a command is pending. The application correctly avoids changing confirmed scooter state until acknowledgement.

VoiceOver should preserve the same distinction:

- activating a control initiates a request;
- pending is not success;
- confirmed state is announced only when domain state changes;
- failure alert remains reachable and understandable;
- disabled controls do not expose an alternate accessibility path around the gate.

Do not announce optimistic success merely because a button was activated. This is a product-truth requirement, not just a wording preference.

### P1 — dynamic Ride Status changes need timely but non-disruptive announcement review

`RideStatusStrip` exposes a combined element:

- label: `Automatic ride tracking`;
- value: current ride status text.

That makes the status readable when focus reaches the strip. However, the source does not itself prove that an important state change is announced when VoiceOver focus is elsewhere.

Apple's current VoiceOver criteria explicitly call out temporary status banners and important in-app alerts as information that should reach VoiceOver users in a timely but non-disruptive way.

**Acceptance requirement:** physically test transitions including restoring, saving, temporarily disconnected, persistence unavailable, and failed. Determine which transitions require an announcement and which should remain silent to avoid chatter. Never announce high-frequency ride/speed animation frames.

If an announcement mechanism is needed, it must use the truthful application status text and avoid repeatedly interrupting navigation.

### P1 — low-battery visual warning needs semantic acceptance

Dashboard and Home visually use red to emphasize low battery, while the battery accessibility element exposes the numeric battery value.

The numeric value itself is truthful and useful, so there is no need to manufacture an additional battery-health claim. But physical acceptance should determine whether the important warning meaning is sufficiently apparent from the percentage alone or whether a concise `Low` state should be announced at the product threshold.

Any such wording must remain derived from the app's explicit low-battery threshold and must not imply voltage, battery health, current draw, or reserve behavior that Nembra does not know.

### P1 — MapKit route traversal and route meaning are not yet proven with VoiceOver

Ride Details provides a native MapKit map when drawable real route geometry exists, followed by textual route coverage, recorded-point count, and known-gap count.

The current source does not establish:

- which MapKit sub-elements VoiceOver exposes;
- whether the map creates a navigation trap or excessive traversal burden;
- whether the user can understand the available route evidence without sight;
- whether any future route summary remains faithful to stored coordinates and known gaps.

PR #75 intentionally removed provisional route-map accessibility code from its narrow row-semantic slice, and route-summary work remains a separate owned/future lane.

**Acceptance requirement:** consume the eventual route-summary boundary rather than inventing geometry in this lane. On-device VoiceOver testing must verify the map is navigable or deliberately de-emphasized while truthful route evidence remains available in text.

### P1 — portrait ↔ landscape replacement needs focus-recovery proof

`AppRootView` swaps the portrait Home/Rides hierarchy for the Dashboard when vertical size class becomes compact.

This is a major accessibility-tree replacement. Source cannot prove what happens to VoiceOver focus during rotation.

**Acceptance requirement:** rotate with VoiceOver active in both directions and verify:

- focus lands on a useful stable element;
- it does not disappear into a removed hierarchy;
- the user can immediately identify the new screen/context;
- returning to portrait restores a logical navigation position rather than an arbitrary hidden element.

### P1 — visual-only `RIDING` / `READY` / `NO LIVE SPEED` / `LAST KNOWN` status must remain audible and non-ambiguous

The center Dashboard exposes a separate visible status under the speed instrument. This status is important because it distinguishes live/retained/offline presentation.

Current ordinary `Text`/`Label` content should be accessible by default, but physical VoiceOver order and wording must be verified together with the `Speed` element. A user must not hear a retained speed in a way that sounds live merely because the numeric value is still present.

The existing `LAST KNOWN` text is an important truth cue and should not be hidden or merged away during the visual overhaul.

### P2 — Home vehicle-header combination should be checked for useful spoken order

The Home header combines vehicle identity, connection status, and lock badge into one accessibility element. This can reduce swipe count, but combination quality depends on the actual spoken order and duplicate icon labels SwiftUI resolves.

**Acceptance requirement:** verify the phrase is concise and ordered as identity → connection → lock state. If the combined result is noisy or ambiguous, restructure the group rather than splitting every decorative child into a separate stop.

### P2 — Home action cards need explicit runtime state wording review

The Light and Lock cards are ordinary Buttons containing title + subtitle and a visual icon/progress state. VoiceOver may derive a usable name from the visible text, but source alone does not prove the final spoken phrase or whether the current On/Off / Locked/Unlocked state is conveyed cleanly.

Physical acceptance should verify:

- stable action name;
- current confirmed value/state;
- pending state when applicable;
- disabled/unavailable state;
- no duplicated icon names.

### P2 — Ride History row fix remains a separate incumbent implementation

Current `main` still contains the older completed-row announcement shape. PR #75 owns the narrow change that replaces the generic `Completed ride` label with the continuity label and removes duplicated continuity from its value.

This audit deliberately does not modify AppRootView. Final VoiceOver acceptance should be performed against whichever row semantics actually merge, not this document's description of a future branch.

## Risk / ownership matrix

| Surface | Current VoiceOver shape | Risk | Required evidence | Ownership boundary |
| --- | --- | --- | --- | --- |
| Home header/status | combined identity/connection/lock + explicit metric label/value | medium | physical spoken order, duplicate/noise check, retained-state clarity | Home owner |
| Home action cards | native Buttons with visible title/subtitle | medium | confirmed/pending/disabled phrase and activation behavior | Home owner |
| Home mode selector | named Buttons + separate current-mode metric | high | individual selected-state announcement | Home owner |
| Dashboard speed | one semantic `Speed` element anchored to authoritative/confirmed value | low but critical | preserve truth contract; physical phrase/update cadence | speed/Dashboard owner |
| Dashboard mode controls | named compact Buttons + separate mode readout | high | selected/pending state; grouping/order | Dashboard owner |
| Dashboard battery/trip/status | explicit metrics + visible live/retained/offline text | medium | low-battery warning meaning + last-known/live clarity | Dashboard/battery owner |
| Vehicle Controls | native Form/Buttons + visual checkmarks | medium | selected/pending state announcement | Vehicle Controls owner |
| Ride status strip | combined label/value, dynamically appearing | high | important transition announcement policy without chatter | ride/shell owner |
| Ride History | native List/NavigationLink; PR #75 owns row phrase fix | medium | physical traversal after final row semantics | Ride History owner |
| Ride Details map | native Map + truthful textual route evidence | high | no focus trap; useful nonvisual route evidence | route/map owner |
| Portrait/landscape swap | entire hierarchy replacement | high | physical rotation/focus recovery | shell + Dashboard owner |
| Future battery/range | signature toggle/readout evolving | high | measured/estimated/unknown provenance remains audible | battery/readout owner |
| Future navigation | map/maneuver cockpit evolving | high | focus order, timely maneuver info, no fabricated route safety | navigation/Dashboard owner |

## Physical-device VoiceOver task matrix

Run with the exact candidate build on the intended supported iPhone and target iOS 27 build.

### Setup

1. Install the app on the physical device.
2. Enable VoiceOver.
3. Set a usable speaking rate.
4. Turn on Speak Hints if Nembra relies on any hints.
5. Turn on Screen Curtain for at least one complete pass so visual inspection cannot mask missing semantics.
6. Record exact app SHA, physical device model, iOS build, orientation, scenario, and test result.

### Global navigation

- launch Nembra and identify initial context;
- traverse every visible element forward;
- traverse every visible element backward;
- verify there are no skipped elements, loops, or inaccessible dead ends;
- switch Home ↔ Rides;
- navigate into and back out of Vehicle Controls and Ride Details;
- refresh/scroll lists and verify reading position remains sensible;
- rotate portrait ↔ landscape and verify focus recovery.

### Home

- identify scooter/model, connection, lock state;
- hear Battery, Scooter Trip, and Mode without decorative duplication;
- activate Light when safe and verify pending vs confirmed state;
- open Lock/Unlock confirmation, cancel, then test the confirmed software path separately in a safe scenario;
- traverse ride-mode choices and identify the currently confirmed selection;
- exercise reconnect / permission Settings states where legitimate;
- reach `All Vehicle Controls` after scrolling;
- verify retained/stale data is described as last-known rather than live.

### Vehicle Controls

- identify connection status;
- traverse each available Ride Mode choice and hear selected/pending state;
- traverse Cruise Off/On and hear the confirmed selection;
- traverse Start Behavior choices and hear the confirmed selection;
- verify unavailable/disabled actions do not become misleadingly actionable;
- verify failure alert is reachable and dismissible.

### Rides

- hear automatic ride status when present;
- verify important dynamic status transitions are conveyed appropriately without repeatedly stealing focus;
- traverse Ride History in both directions;
- open a completed/recovered row and hear continuity/distance evidence without unnecessary duplication;
- traverse Ride Details timeline/distance/route evidence;
- verify MapKit does not trap navigation and truthful textual route evidence remains accessible.

### Landscape Dashboard

- identify connection/model context;
- hear Speed as one coherent value with unit;
- confirm visually interpolated frames are never spoken as sensor measurements;
- hear retained `LAST KNOWN` vs live `READY`/`RIDING` vs `NO LIVE SPEED` semantics clearly;
- hear Battery and Trip;
- hear current Ride Mode;
- while safely stopped, traverse each mode Button and identify selected/pending state;
- activate Light and Lock only in a safe software scenario;
- verify confirmation/failure dialogs;
- verify moving-state control removal does not leave inaccessible/hidden actionable elements.

## Dynamic-content announcement policy

Nembra has high-frequency telemetry and low-frequency state transitions. VoiceOver must treat them differently.

### Do not announce continuously

Do not post announcements for:

- every speed render frame;
- every numeric rolling-digit animation frame;
- every GPS sample;
- every map update;
- intermediate battery presentation animation frames;
- speculative estimated frames masquerading as measurements.

### Consider announcing meaningful state transitions

Physical testing should determine whether concise announcements improve:

- command failure;
- critical persistence failure;
- transition into a meaningful disconnected/retained state;
- completion/recovery events where the user otherwise receives no feedback;
- future navigation maneuver changes when navigation is active.

Announcements must be rate-limited by product meaning, not animation frequency, and must use truthful authoritative/derived state appropriate to the feature.

## Battery/range VoiceOver contract for future integration

The upcoming signature battery/range readout must preserve the same evidence split as the visual product:

- measured SoC may be announced as the current battery percentage when authoritative;
- estimated display SoC must not be described as measured scooter telemetry;
- estimated range must be identified as an estimate where context requires it;
- `unknown` must remain unknown rather than becoming zero;
- retained data must remain last-known/stale where applicable;
- animated one-percentage-point visual transitions must not produce fake intermediate VoiceOver telemetry;
- tapping the primary battery indicator to toggle percentage ↔ estimated range must yield one stable semantic element rather than two noisy duplicate readouts.

## Accessibility Inspector / automated audit role

Apple's Accessibility Inspector and `performAccessibilityAudit` can catch important classes of defects such as:

- missing element descriptions;
- small hit regions;
- contrast failures;
- inaccessible element detection;
- clipped text;
- trait issues;
- Dynamic Type issues.

Nembra should use that automation where the active UI-test owner can add it safely.

However, a clean automated audit does **not** certify VoiceOver navigation, reading order, dynamic announcements, semantic truth, map traversal, or end-to-end common-task completion. Physical VoiceOver testing remains the acceptance gate for those behaviors.

## Current verdict

Current Nembra source has several unusually strong VoiceOver foundations for a systems-phase app:

- Dashboard speed deliberately hides render-only digits and announces authoritative/confirmed speed;
- major metrics use semantic label/value grouping;
- mode personality decoration is hidden instead of becoming false state;
- most user actions use native controls;
- icon-only actions are generally named;
- system dialogs and navigation primitives are retained.

Nembra should **not yet claim production VoiceOver support**, because physical-device common-task evidence is still missing and several state semantics remain unproven.

Highest-priority follow-ups are:

1. verify/add selected-state semantics on Home/Dashboard/Vehicle Controls choice controls without announcing pending state as confirmed;
2. define a restrained announcement policy for important Ride Status / command failure transitions;
3. prove live-vs-retained Dashboard speed context is clear in spoken order;
4. prove MapKit route traversal does not trap or obscure truthful route evidence;
5. prove portrait ↔ landscape focus recovery;
6. consume PR #75's final Ride History row semantics instead of duplicating them;
7. preserve the authoritative-speed VoiceOver anchor through every visual redesign.

## Truth / hardware boundary

This audit changes no production source, telemetry, battery/range logic, ride evidence, route geometry, persistence, Bluetooth/Tuya behavior, command path, or hardware capability.

A future physical-iPhone VoiceOver pass validates app accessibility behavior for that exact build. It does not, by itself, verify AOVOPRO ES80 BLE identity, packet semantics, command acknowledgements, battery source, speed cadence, reconnect behavior, or field ride performance.
