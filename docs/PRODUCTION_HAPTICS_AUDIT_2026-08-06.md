# Production Haptics Audit — 2026-08-06

Worker: `chat-r3x8v`  
Lane: `production-haptics-audit`  
Base audited: current `main` through `62827af5c76585a8aa6fa7146549b51f86e7786e`

## Purpose

Nembra's Production Visual + Performance Overhaul explicitly includes interaction quality and haptics. This audit defines a restrained tactile-feedback contract before battery, controls, rides, and future navigation accumulate unrelated feedback patterns.

The goal is not to make every tap vibrate. The goal is to make a few important tactile events causal, semantically correct, truthful about scooter confirmation, accessible, optional, and physically validated on the iPhone 12 baseline.

This lane changes no Swift source, UI tests, Xcode project, simulation fixtures, persistence, battery/range model, ride logic, navigation logic, Bluetooth behavior, or motorized-hardware state.

## Apple platform contract checked 2026-08-06

Current Apple guidance establishes several useful constraints:

- use system-provided haptic patterns according to their documented meanings;
- create a clear causal relationship between the haptic and the action/event that caused it;
- prefer short haptics that complement discrete events in normal apps;
- avoid overuse because it dilutes meaning and can become distracting;
- make haptics optional and keep the experience usable without them;
- use multiple feedback channels rather than making haptics the only way to communicate success, failure, warning, or state;
- supported standard controls such as switches, sliders, and pickers can already provide system-designed feedback;
- SwiftUI `SensoryFeedback` provides semantic patterns such as `selection`, `success`, `warning`, `error`, `start`, `stop`, `increase`, and `decrease`;
- SwiftUI `sensoryFeedback` is trigger-driven, so implementation owners must choose a trigger that represents the intended semantic transition rather than an unrelated render update.

Relevant Apple references:

- Human Interface Guidelines — Playing haptics: https://developer.apple.com/design/human-interface-guidelines/playing-haptics
- Human Interface Guidelines — Feedback: https://developer.apple.com/design/human-interface-guidelines/feedback
- SwiftUI `SensoryFeedback`: https://developer.apple.com/documentation/swiftui/sensoryfeedback
- SwiftUI `sensoryFeedback(_:trigger:)`: https://developer.apple.com/documentation/swiftui/view/sensoryfeedback(_:trigger:)
- Core Haptics: https://developer.apple.com/documentation/corehaptics
- Core Haptics sample — Updating Continuous and Transient Haptic Parameters in Real Time: https://developer.apple.com/documentation/corehaptics/updating-continuous-and-transient-haptic-parameters-in-real-time

Apple's HIG explicitly describes notification haptics as task/action outcomes and gives unlocking a vehicle as an example. SwiftUI describes `.success` as completion and `.selection` as a UI element's value changing.

Apple's Core Haptics sample also states that Simulator does not provide a haptic interface. Therefore Xcode/iOS Simulator can prove trigger/state logic and visual/accessibility behavior, but it cannot prove the physical feel, strength, timing, comfort, or real Taptic Engine result of Nembra haptics.

## Current source inventory

### Current Home already has one explicit app-authored haptic

Current `HomeView.modeSection` ends with:

```swift
.sensoryFeedback(.selection, trigger: vehicle.state.rideMode)
```

This is better than firing a success haptic directly from the mode button tap because the trigger follows the confirmed/shared vehicle state rather than the initial request.

However, the trigger is **global state, not user-action provenance**. `VehicleStore.start()` independently replaces `state` from the service's update stream, so `vehicle.state.rideMode` can legitimately change because of reconnect/restoration, simulation, or another accepted state update rather than the current user's mode-button request.

That means the existing Home haptic has a causal ambiguity: it can play when a ride-mode value changes even though no current local interaction caused the change.

The production fix must preserve both halves of truth:

1. do not haptic success at button-tap/pending time; and
2. do not treat every global confirmed-mode change as a user-completed command.

The eventual trigger needs confirmed state **plus current-user-request provenance**, reusing the accepted pending/confirmation architecture rather than inventing a second command system.

### Current Dashboard main has no equivalent app-owned haptic language

Current-main Dashboard does not add a custom haptic for speed, connection, trip, battery, mode, light, or lock. No app-owned `CHHapticEngine`, `UIFeedbackGenerator`, or custom haptic subsystem was found in the audited production paths.

This is a good time to define a small cross-surface contract instead of allowing each future control to choose an unrelated pattern.

### Active Dashboard battery PR #57 adds one coherent local selection haptic

The active `battery-primary-readout-ui` lane adds:

```swift
.sensoryFeedback(.selection, trigger: batteryReadoutModeRawValue)
```

The trigger changes only when the local primary readout preference toggles `% ↔ estimated range`. That is a strong semantic fit for `.selection`: the user selected a different representation of the same authoritative battery/range domain; no scooter command is implied.

This audit treats that in-flight implementation as a useful reference, not merged product truth and not a file dependency. PR #57 remains the owner of its Dashboard/project/UI-test paths.

### Vehicle command truth is deliberately pessimistic

Current `VehicleStore` maintains pending command state and calls the scooter service asynchronously for light, lock, cruise, ride mode, start mode, and speed-limit changes. Errors are mapped to explicit messages such as disconnected before confirmation, rejected command, unsupported capability/mode, out-of-range value, or generic failure to confirm.

This architecture creates an important haptic rule:

> a tactile **success** must never be tied merely to the user's initial tap on a motorized-hardware control.

The tap proves intent. It does not prove the scooter changed state.

## Core Nembra haptic principles

### 1. Haptics must follow truth authority **and causal provenance**

Presentation-only events may haptic from presentation state when the app owns that state locally and the user action itself caused the change.

Hardware-affecting events may communicate completion only when the accepted command/state architecture says the result is confirmed **and** the app can correlate that result to the current user's request.

A pending command is not success. A button-down event is not success. A passive/restored state update is not a user-command success. A Simulator fixture is not physical hardware confirmation.

### 2. One event should not produce multiple competing haptics

Avoid chains like:

`tap impact -> pending selection -> success -> state-selection`

for one scooter command.

Pick the highest-value semantic moment. In most Nembra command flows, that should be the confirmed, user-correlated outcome rather than decorative button-press feedback.

### 3. Haptics complement visible and accessible feedback

Every tactile event must have an equivalent meaningful visual/accessibility state. Haptics must never become the only indication that:

- a command succeeded or failed;
- low battery crossed a warning boundary;
- a mode changed;
- navigation started/stopped;
- a ride was recovered;
- data are stale/retained;
- a connection failed.

### 4. Automatic telemetry must not make the phone chatter

Battery percentages, speed samples, ODO updates, range estimates, GPS points, render interpolation frames, and normal connection-state refreshes are data streams. They must not each generate haptics.

Haptic triggers need event-level hysteresis/de-duplication just as visual range/battery logic needs stable presentation.

### 5. Presentation animation frames are never haptic truth

The battery transition lane explicitly classifies intermediate 1%-step frames as presentation-only. Do not play a haptic for every visual `84 -> 83 -> 82 -> 81 -> 80` frame.

If the user directly toggles the battery readout representation, one selection haptic can describe that local UI choice. Authoritative battery consumption itself should not buzz per percentage point.

## Recommended semantic matrix

| Event | Recommended default | Trigger authority | Important constraint |
| --- | --- | --- | --- |
| Battery `% ↔ range` tap | `.selection` | local readout mode actually changes | one haptic per completed local toggle; no haptic when control is disabled/no-SoC |
| Ride-mode scooter command | subtle `.selection` after confirmed user-correlated mode change | confirmed `VehicleState.rideMode` + current request provenance | do not fire on initial tap or passive/restored mode changes |
| Headlight scooter command | optional subtle on/off or selection feedback after confirmation | confirmed light state + current request provenance | avoid both press impact and completion haptic |
| Lock / unlock command | `.success` is reasonable for confirmed completion | confirmed lock state + explicit current user action | Apple cites unlocking a vehicle as outcome-haptic territory; never fire on confirmation-dialog presentation |
| Command rejected / cannot confirm | `.error` | explicit current command failure | fire once per failed operation, not once per error-view render |
| Out-of-range / actionable warning | `.warning` only when there is a real validated warning | accepted app/domain outcome | do not invent a warning around unsupported hardware facts |
| Connect / reconnect | normally none | connection domain | churn can be frequent/background; visible state usually carries the truth better |
| Low battery threshold | optional `.warning` once at a meaningful threshold crossing | accepted stable warning policy | never per sample; sag/estimated display movement must not repeatedly retrigger it |
| Automatic ride start/end | default none | RideEngine truth | automatic detection can occur without explicit action; avoid surprise haptics unless field UX proves value |
| Recovered ride continuity | default none | persisted recovery truth | communicate recovery visibly/VoiceOver; do not imply a new user action completed |
| Manual navigation start/stop | `.start` / `.stop` can be evaluated | accepted navigation UI action | navigation UI does not yet exist; do not pre-wire speculative routing behavior |
| Maneuver progression | normally no per-update haptic in first release | accepted navigation event model | future field test may justify sparse high-value events |
| Route GPS/MapKit updates | none | data stream | never haptic per coordinate, segment, map-camera frame, or route gap |
| Speed / rolling-number render | none | presentation stream | 60 Hz/render interpolation must never drive haptics |

The matrix defines a review target, not permission to add every listed haptic now.

## P0 truth risk — existing Home ride-mode trigger lacks user provenance

Current Home's `.sensoryFeedback(.selection, trigger: vehicle.state.rideMode)` is tied to the accepted state value, which correctly avoids optimistic button-tap success. But state-stream updates are not necessarily caused by the current Home interaction.

A reconnect or restoration can therefore change the same trigger.

### Required production behavior

Do not move the haptic directly onto the mode button tap as a shortcut; that would make the truth problem worse.

Instead, future integration should generate one presentation outcome event only when it can correlate:

1. a current user-initiated mode request;
2. the matching accepted/confirmed outcome; and
3. the absence of a rejected/unconfirmed result.

Passive mode observations, launch restoration, reconnect state, Simulator fixture setup, and externally-originated state changes must not masquerade as a completed local command.

If the current command API does not expose enough outcome identity to do that safely, remove/defer the command-success haptic rather than inventing provenance.

## P0 truth risk — command haptics tied to button taps would also lie

Home, Dashboard, and Vehicle Controls initiate scooter changes through async `VehicleStore` commands. Nembra intentionally waits for service confirmation and exposes pending/error state.

A generic `.sensoryFeedback(.success, trigger: tapCounter)` on those buttons would contradict that architecture by signaling completion before the transport/device confirms it.

The correct boundary is not “tap vs state” alone; it is **user request + confirmed matching outcome**.

## P1 risk — command error haptics can accidentally repeat

`lastErrorMessage` is observable UI state. An error alert can be redrawn or re-presented as surrounding state changes.

If a future `.error` haptic watches error state, ensure it fires only on a new failed operation / meaningful nil-to-error transition. It must not replay while the same error remains visible or during unrelated body recomputation.

The haptic cannot replace the visible alert/message because users can disable haptics or the hardware/system can decline to play them.

## P1 risk — low-battery warning loops

Low battery is a useful candidate for tactile warning only if the battery presentation policy defines a stable meaningful crossing.

Nembra requires sag/recovery-aware, truthful battery behavior and distinguishes raw/measured/estimated/display states. A haptic trigger must sit **after** the accepted warning policy, not directly on noisy raw voltage or every displayed percent change.

A sensible contract is one warning when entering the accepted low-battery region during an active foreground experience, with no retrigger until the state clearly exits/re-arms according to the battery policy.

Physical ES80 low-SoC behavior remains hardware evidence-gated.

## P1 risk — automatic ride detection can surprise the rider

Nembra rides start automatically from accepted ride-domain evidence rather than a manual Start Ride button.

Because automatic ride state can transition without an explicit tap, a `start` or `stop` haptic can feel uncaused or confusing, especially around recovery/reconnect transitions.

Default policy: no automatic ride start/stop haptic in the first production pass. Revisit only after physical-device/field UX demonstrates a clear benefit and confirms transitions are stable enough not to buzz during noisy lifecycle edges.

## P1 risk — navigation haptics need a system-aware policy

Future navigation is expected to integrate deeply into the cockpit, but production MapKit/navigation behavior is not yet accepted.

Do not pre-assign haptics to route recalculation, camera movement, GPS updates, every maneuver countdown, or unsupported scooter-routing claims.

When navigation UI exists, start/stop or a small number of high-value maneuver transitions can be evaluated on a physical iPhone. Nembra must avoid fighting system-provided feedback and must not imply that a walking/cycling route is verified scooter-legal/safe.

## Haptic preference / optionality

Apple recommends making haptics optional.

If Nembra grows beyond one or two native/system-like selection events into a deliberate app-wide tactile language, the Production Visual Overhaul should provide a coherent mute/off path for **app-authored** haptics. That preference must affect presentation feedback only and must never disable visible command errors, VoiceOver semantics, actual scooter commands, or safety/truth state.

Do not add a Settings toggle merely as decoration before the app actually owns a meaningful set of haptics. But do not ship a dense custom haptic layer with no user control.

The product must also remain correct if iOS or device settings suppress requested feedback. Product logic must never infer command success from whether a haptic played.

## Reduce Motion and haptics are related but not identical

The merged Reduce Motion audit owns visual-motion acceptance. Haptics should not automatically be disabled simply because `accessibilityReduceMotion` is enabled: the preference is about motion, and tactile feedback can be an alternate channel.

However, any haptic tightly coupled to an animation must still make semantic sense when the animation snaps/cross-fades under Reduce Motion. Trigger from the stable event/outcome, not an animation frame.

If user testing shows a particular pattern feels uncomfortable, the app-level haptic preference is the appropriate independent control.

## Simulator versus physical iPhone acceptance

### What Simulator can prove

- trigger conditions change only for intended semantic events;
- disabled controls do not mutate local haptic triggers;
- command pending/error/confirmed state logic does not optimistically report success;
- passive/reconnected/restored mode changes do not emit a user-command outcome event after provenance hardening;
- UI and VoiceOver provide equivalent feedback without relying on touch sensation;
- no telemetry/render loop is wired to a haptic trigger;
- haptic code compiles on the exact iOS 27 target.

### What Simulator cannot prove

Apple's Core Haptics sample documentation says Simulator does not support a haptic interface. Therefore Simulator screenshots/tests cannot prove:

- physical Taptic Engine playback;
- perceived strength/sharpness/comfort;
- whether two nearby haptics feel like an accidental double pulse;
- real timing relative to finger release / scooter confirmation;
- distraction while physically riding;
- physical-device support/behavior;
- whether the rider can meaningfully associate the haptic with the real ES80 outcome.

### Required physical acceptance

Before declaring the production haptic language polished, use a physical iPhone 12 and evaluate at minimum:

1. battery `% ↔ range` local selection;
2. one confirmed non-destructive scooter control when real ES80 command semantics are verified;
3. confirmed lock/unlock if that capability is physically verified;
4. command failure/error path using a safe controlled test condition;
5. low-battery warning only after the battery-warning policy is accepted;
6. navigation start/stop only after navigation UI exists;
7. app-authored haptics disabled/muted, verifying all visual/VoiceOver truth still works.

A physical iPhone haptic test still does not prove the ES80 command succeeded unless scooter-side state is independently verified by the accepted hardware protocol/confirmation path.

## Deterministic test recommendations

Haptic code should remain thin and event-driven enough that most correctness can be tested without trying to sense vibration in XCTest.

Useful deterministic assertions:

- local readout mode changes once -> selection-feedback trigger changes once;
- tapping a disabled battery readout -> no trigger change;
- scooter command enters pending -> no success token;
- matching confirmed user-correlated command outcome -> one outcome token;
- rejected/unconfirmed command -> one error token and no success token;
- passive mode restoration/reconnect -> no user-command success token;
- repeated same low-battery state -> no repeated warning token;
- presentation-only battery intermediate frames -> no haptic token;
- speed render frames / GPS points -> no haptic token;
- app-haptics-off preference -> no app-authored haptic request while visible/accessibility state remains identical.

Test event-selection/provenance logic separately from physical playback. Physical playback remains a device QA concern.

## Active-owner boundaries

At this checkpoint:

- PR #70 owns Home hierarchy work and currently leaves the existing ride-mode haptic trigger in place;
- PR #57 owns Dashboard battery readout integration and its local selection haptic;
- PR #45 owns battery integer presentation transition semantics and intentionally leaves haptic pacing/integration outside NembraCore;
- PR #67 owns pushed-detail shell tab clearance;
- PR #75 is a dependent Ride History accessibility semantics fix;
- navigation lanes remain domain/research work rather than final cockpit haptic integration.

A same-lane duplicate audit PR #87 was closed unmerged after the v7 control-plane race was detected. This document incorporates the important current-Home provenance finding surfaced during that duplicate review.

This audit does not authorize edits to any of those product paths. Haptic implementation should be folded into an incumbent owner when naturally coherent, or claimed later as one small integration lane after those paths clear.

## Recommended implementation order

1. Treat current Home mode feedback as a provenance-hardening issue: keep confirmation timing, but gate it to the current user request or defer/remove the haptic until that correlation exists.
2. Let #57's local battery-readout selection feedback complete its existing acceptance path.
3. Define a tiny command-outcome presentation event boundary only when an owner can prove it does not optimistically signal motorized-hardware success or passive state restoration.
4. Add at most one confirmed-command outcome haptic and one de-duplicated error path; physically evaluate before spreading the pattern.
5. Evaluate low-battery warning after battery truth/warning thresholds are accepted.
6. Keep automatic rides quiet by default.
7. Add navigation haptics only with the future accepted navigation UI and real-device UX loop.
8. Revisit global consistency/mute preference during the major Production Visual Overhaul rather than accumulating unrelated one-off generators.

## Truth / hardware boundary

This audit does not:

- send a Bluetooth/Tuya write;
- change command confirmation semantics;
- claim any ES80 capability is physically verified;
- treat a pending command or a passive state update as user-command success;
- convert battery presentation frames into telemetry;
- change battery/range learning;
- alter ride detection/recovery;
- infer scooter-safe route behavior;
- claim Simulator can reproduce iPhone haptics;
- claim physical iPhone feel from source review.

## Acceptance conclusion

Nembra already has one important haptic lesson in current Home: triggering from confirmed global mode state is safer than triggering from the tap, but it is still not sufficient because confirmed state lacks current-user provenance. The production contract therefore needs both **confirmation** and **causality**.

The strongest in-flight example is the battery `% ↔ range` local `.selection` trigger because the app fully owns that presentation-state change and the user action directly causes it.

For scooter controls, the defining rule is stricter: **tactile success belongs to a confirmed, user-correlated outcome — never mere intent and never an unrelated passive state update**. Keep telemetry/ride streams quiet, reserve warning/error patterns for de-duplicated meaningful events, preserve visible/VoiceOver equivalents, make an expanded custom haptic layer optional, and require physical iPhone 12 evaluation before calling tactile polish complete.