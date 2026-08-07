# Production Haptics Audit — 2026-08-06

Worker: `chat-r3x8v`  
Lane: `production-haptics-audit`  
Base audited: `main@7466cd1a89988d9aeaa6f757519e264a245ec726`

## Purpose

Nembra's Production Visual + Performance Overhaul explicitly includes interaction quality and haptics. This audit defines a restrained tactile-feedback contract before multiple UI owners independently add vibrations to battery, controls, rides, and future navigation.

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
- Preparing your app to play haptics: https://developer.apple.com/documentation/corehaptics/preparing-your-app-to-play-haptics

Apple's own Core Haptics samples also state that Simulator does not provide a haptic interface. Therefore Xcode/iOS Simulator can prove trigger/state logic and visual/accessibility behavior, but it cannot prove the physical feel, strength, timing, comfort, or real Taptic Engine result of Nembra haptics.

## Current source inventory

### Current `main` does not author an app haptic API on the audited key surfaces

A current-main source inventory found no app-authored `.sensoryFeedback`, `UIFeedbackGenerator`, or Core Haptics usage in the audited Home, Dashboard, AppRoot/Rides, Vehicle Controls, or VehicleStore paths.

That does **not** mean a user can never feel system feedback. Apple can supply its own behavior for supported native controls and system surfaces. The source conclusion is narrower: current main does not yet define a Nembra-wide custom haptic language.

This is a good time to define one before the Production Visual Overhaul adds more interaction polish.

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

### 1. Haptics must follow truth authority

Presentation-only events may haptic from presentation state because the app owns that state locally.

Hardware-affecting events may communicate completion only when the accepted command/state architecture says the result is confirmed. A pending command is not success. A button-down event is not success. A Simulator fixture is not physical hardware confirmation.

### 2. One event should not produce multiple competing haptics

Avoid chains like:

`tap impact -> pending selection -> success -> state-selection`

for one scooter command.

Pick the highest-value semantic moment. In most Nembra command flows, that should be the confirmed outcome, not decorative button press feedback.

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
| Ride-mode scooter command | subtle `.selection` **after confirmed mode changes** | confirmed `VehicleState.rideMode` tied to a user-initiated pending command | do not haptic success on initial tap; do not react to passive/restored mode updates |
| Headlight scooter command | optional subtle selection/on-off feedback **after confirmation** | confirmed light state tied to user command | avoid both press impact and completion haptic |
| Lock / unlock command | `.success` is reasonable for confirmed completion | confirmed lock state after explicit user action | Apple specifically treats task outcomes such as unlocking a vehicle as notification-haptic territory; never fire on confirmation-dialog presentation |
| Command rejected / cannot confirm | `.error` | explicit command failure surfaced by the command state | fire once per user-initiated failed operation, not once per error-view render |
| Out-of-range / dangerous-setting warning | `.warning` only when there is a real actionable warning | validated app/domain outcome | do not invent a warning around unsupported hardware facts |
| Connect / reconnect | normally none | connection domain | connection churn can be frequent/background; use visible state unless a deliberate user action has a meaningful completion UX |
| Low battery threshold | optional `.warning` once at a meaningful threshold crossing | authoritative/display policy that has already de-bounced the threshold | never per sample; do not let sag/estimated display movement repeatedly retrigger it |
| Automatic ride start/end | default **none** | RideEngine truth | automatic detection can occur without an explicit action; surprise haptics are undesirable unless field UX later proves clear value |
| Recovered ride continuity | default none | persisted recovery truth | communicate recovery visibly/VoiceOver; avoid implying a new user action completed |
| Manual navigation start/stop | `.start` / `.stop` can be evaluated | accepted navigation UI action | navigation UI does not yet exist; do not pre-wire against speculative routing behavior |
| Maneuver progression | normally no per-update haptic in first release | accepted navigation event model | future field test may justify sparse maneuver feedback; avoid competing with audio/system navigation patterns |
| Route GPS/MapKit updates | none | data stream | never haptic per coordinate, segment, map-camera frame, or known-gap update |
| Speed / rolling-number render | none | presentation stream | 60 Hz/render interpolation must never drive haptics |

The matrix defines a review target, not permission to add every listed haptic now.

## P0 truth risk — command haptics tied to button taps would lie

Home, Dashboard, and Vehicle Controls initiate scooter changes through async `VehicleStore` commands. Nembra intentionally waits for service confirmation and exposes pending/error state.

A generic `.sensoryFeedback(.success, trigger: tapCounter)` on those buttons would contradict that architecture by signaling completion before the transport/device confirms it.

### Required implementation shape

If a future owner adds hardware-command haptics, the feedback trigger should be derived from an explicit command outcome or a correlation between:

1. a user-initiated pending command; and
2. the accepted confirmed state/outcome.

It should not be derived from a raw button press, animation, optimistic binding, or Simulator-only local mutation that production hardware does not use.

If the current command API does not expose enough outcome identity to trigger that safely, leave the haptic out rather than inventing a success signal.

## P1 risk — command error haptics can accidentally repeat

`lastErrorMessage` is observable UI state. An error alert can be redrawn or re-presented as surrounding state changes.

If a future `.error` haptic simply watches `lastErrorMessage != nil`, ensure it fires only on a new failed operation / meaningful nil-to-error transition. It must not replay while the same error remains visible or during unrelated body recomputation.

The haptic cannot replace the visible alert/message because some users disable haptics or the hardware may not support them.

## P1 risk — low-battery warning loops

Low battery is a useful candidate for tactile warning only if the battery presentation policy defines a stable meaningful crossing.

Nembra already requires sag/recovery-aware, truthful battery behavior and distinguishes raw/measured/estimated/display states. A haptic trigger must sit **after** the accepted warning policy, not directly on noisy raw voltage or every displayed percent change.

A sensible contract is one warning when entering the accepted low-battery region during an active foreground experience, with no retrigger until the state clearly exits/re-arms according to the battery policy.

Physical ES80 low-SoC behavior remains hardware evidence-gated.

## P1 risk — automatic ride detection can surprise the rider

Nembra rides start automatically from accepted ride-domain evidence rather than a manual Start Ride button.

Apple's guidance emphasizes a clear causal relationship. Because automatic ride state can transition without an explicit tap, a `start` or `stop` haptic can feel uncaused or confusing, especially around recovery/reconnect transitions.

Default policy: no automatic ride start/stop haptic in the first production pass. Revisit only after physical-device/field UX demonstrates a clear benefit and confirms transitions are stable enough not to buzz during noisy lifecycle edges.

## P1 risk — navigation haptics need a system-aware policy

Future navigation is expected to integrate deeply into the cockpit, but production MapKit/navigation behavior is not yet accepted.

Do not pre-assign haptics to route recalculation, camera movement, GPS updates, every maneuver countdown, or unsupported scooter-routing claims.

When navigation UI exists, start/stop or a small number of high-value maneuver transitions can be evaluated on a physical iPhone. Nembra must avoid fighting any system-provided audio/haptic behavior and must not imply that a walking/cycling route is verified scooter-legal/safe.

## Haptic preference / optionality

Apple recommends making haptics optional.

If Nembra grows beyond one or two native/system-like selection events into a deliberate app-wide tactile language, the Production Visual Overhaul should provide a coherent mute/off path for **app-authored** haptics. That preference must affect presentation feedback only and must never disable visible command errors, VoiceOver semantics, actual scooter commands, or safety/truth state.

Do not add a Settings toggle merely as decoration before the app actually owns a meaningful set of haptics. But do not ship a dense custom haptic layer with no user control.

## Reduce Motion and haptics are related but not identical

The merged Reduce Motion audit owns visual-motion acceptance. Haptics should not automatically be disabled simply because `accessibilityReduceMotion` is enabled: the preference is about motion, and tactile feedback can be an alternate nonvisual channel.

However, any haptic that is tightly coupled to an animation must still make semantic sense when the animation snaps/cross-fades under Reduce Motion. Trigger from the stable event/outcome, not an animation frame.

If user testing shows a particular pattern feels motion-like or uncomfortable, the app-level haptic preference is the appropriate independent control.

## Simulator versus physical iPhone acceptance

### What Simulator can prove

- trigger conditions change only for intended semantic events;
- disabled controls do not mutate the trigger;
- command pending/error/confirmed state logic does not optimistically report success;
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

A physical iPhone haptic test still does not prove the ES80 command succeeded unless the scooter-side state is independently verified by the accepted hardware protocol/confirmation path.

## Deterministic test recommendations

Haptic code should remain thin and event-driven enough that most correctness can be tested without trying to sense vibration in XCTest.

Useful deterministic assertions:

- readout mode changes once -> selection-feedback trigger changes once;
- tapping a disabled battery readout -> no trigger change;
- scooter command enters pending -> no success trigger;
- confirmed user-correlated command outcome -> one outcome token;
- rejected command -> one error token and no success token;
- passive state restoration/reconnect -> no user-command success token;
- repeated same low-battery state -> no repeated warning token;
- presentation-only battery intermediate frames -> no haptic token;
- speed render frames / GPS points -> no haptic token;
- app-haptics-off preference -> no app-authored haptic request while visible/accessibility state remains identical.

Test the event-selection logic separately from physical playback. Physical playback remains a device QA concern.

## Active-owner boundaries

At this checkpoint:

- PR #57 owns Dashboard battery readout integration and its existing selection haptic;
- PR #45 owns battery integer presentation transition semantics and intentionally leaves haptic pacing/integration outside NembraCore;
- PR #70 owns current Home hierarchy work;
- PR #67 owns pushed-detail shell tab clearance;
- PR #75 is a dependent Ride History accessibility semantics fix;
- navigation lanes remain domain/research work rather than final cockpit haptic integration.

This audit does not authorize edits to any of those paths. Haptic implementation should be folded into an incumbent owner when naturally coherent, or claimed later as one small integration lane after those paths clear.

## Recommended implementation order

1. Let #57's local battery-readout selection feedback complete its existing acceptance path.
2. Define a tiny command-outcome presentation event boundary only when an owner can prove it does not optimistically signal motorized-hardware success.
3. Add at most one confirmed-command outcome haptic and one de-duplicated error path; physically evaluate before spreading the pattern.
4. Evaluate low-battery warning after battery truth/warning thresholds are accepted.
5. Keep automatic rides quiet by default.
6. Add navigation haptics only with the future accepted navigation UI and real-device UX loop.
7. Revisit global consistency/mute preference during the major Production Visual Overhaul rather than accumulating unrelated one-off generators.

## Truth / hardware boundary

This audit does not:

- send a Bluetooth/Tuya write;
- change command confirmation semantics;
- claim any ES80 capability is physically verified;
- treat a pending command as success;
- convert battery presentation frames into telemetry;
- change battery/range learning;
- alter ride detection/recovery;
- infer scooter-safe route behavior;
- claim Simulator can reproduce iPhone haptics;
- claim physical iPhone feel from source review.

## Acceptance conclusion

Nembra currently has room to establish a clean haptic language rather than unwind a noisy one later. The strongest existing in-flight example is the battery `% ↔ range` local `.selection` trigger because the app fully owns that presentation-state change.

For scooter controls, the defining production rule is stricter: **tactile success belongs to confirmed outcome, never mere intent**. Keep automatic telemetry/ride streams quiet, reserve warning/error patterns for de-duplicated meaningful events, preserve visible/VoiceOver equivalents, make an expanded custom haptic layer optional, and require physical iPhone 12 evaluation before calling tactile polish complete.