# Production Haptics Audit — 2026-08-06

Worker: `chat-t5m9q`
Lane: `production-haptics-audit`
Base audited: `main@7466cd1a89988d9aeaa6f757519e264a245ec726`

## Purpose

Nembra's production visual/performance phase calls for deliberate haptics, not vibration for its own sake. This audit defines where tactile feedback can reinforce a real user action or a confirmed result without becoming fake telemetry, misleading command confirmation, or noisy background behavior.

This is a Class C source/research audit plus this document. It changes no Swift source, tests, Xcode project, persistence, ride logic, battery/range evidence, Bluetooth behavior, command semantics, map truth, or hardware state.

## Current Apple platform contract

### Use the documented meaning of each pattern

Apple's current Human Interface Guidelines say to use system-provided haptic patterns according to their documented meanings and to keep a clear causal relationship between the haptic and the action that causes it.

Apple specifically defines:

- **selection** for a UI element's value changing;
- **success / warning / error** for operation outcomes;
- **impact** for a physical UI metaphor such as objects colliding or snapping;
- **start / stop** for activities starting and stopping;
- additional threshold/level patterns for their documented meanings.

Sources:
https://developer.apple.com/design/human-interface-guidelines/playing-haptics
https://developer.apple.com/documentation/swiftui/sensoryfeedback

Nembra implication: pattern names are semantic contracts, not just different vibration textures.

### Haptics should complement, not replace, other feedback

Apple recommends combining tactile feedback with visual/auditory feedback where appropriate and making all feedback accessible.

Nembra must therefore remain fully understandable when haptics do not play. Connection truth, battery/range truth, command success/failure, ride state, and navigation cannot be communicated only through vibration.

Source:
https://developer.apple.com/design/human-interface-guidelines/feedback

### Avoid overuse and long-running haptics

Apple recommends short feedback for discrete events in most apps and warns that frequent/long-running haptics can become tiring or lose meaning.

Nembra should not produce tactile output for:

- every speed render frame;
- every interpolated rolling digit;
- every battery presentation-intermediate percentage;
- every incoming BLE packet;
- ordinary GPS samples;
- continuous ride motion;
- decorative animation frames.

Those events are either too frequent or are presentation/evidence plumbing rather than discrete user-relevant outcomes.

### Respect user/system ability to disable haptics

Apple's current SwiftUI haptic guidance says the feedback API informs the system of an event; the system decides whether to play it based on factors including hardware, foreground state, battery, and whether the system Haptics setting is on.

Apple's HIG also says haptics should be optional. iPhone additionally allows all vibration to be disabled under Accessibility > Touch > Vibration.

Sources:
https://developer.apple.com/documentation/applepencil/playing-haptic-feedback-in-your-app
https://developer.apple.com/design/human-interface-guidelines/playing-haptics
https://support.apple.com/guide/iphone/iphd722c9100/ios

For the current small set of standard SwiftUI haptics, Nembra should prefer the system feedback API and system user controls instead of immediately inventing a second Nembra-specific haptic preference. Reconsider an app-specific preference only if product testing or future custom/continuous haptics creates a clear need.

## SwiftUI trigger semantics matter

Current SwiftUI `sensoryFeedback` plays when its observed Equatable `trigger` changes. Apple also provides condition/closure variants so the app can decide whether a particular old/new transition deserves feedback.

Sources:
https://developer.apple.com/documentation/swiftui/view/sensoryfeedback(_:trigger:)
https://developer.apple.com/documentation/swiftui/view/sensoryfeedback(_:trigger:condition:)
https://developer.apple.com/documentation/swiftui/view/sensoryfeedback(trigger:_:)

This is especially important for Nembra because many visible values are not owned by the local button that displays them. They can change because of BLE updates, reconnect/recovery, simulation fixtures, persistence restoration, or a confirmed command.

A domain value changing is not automatically proof that the person just selected it.

## Source inventory — current main

### Home Ride Mode is the only current-main explicit Nembra haptic site found

Current `NembraApp/Features/Home/HomeView.swift` attaches:

```swift
.sensoryFeedback(.selection, trigger: vehicle.state.rideMode)
```

to the whole Ride Mode section.

The mode buttons send `vehicle.setMode(mode)`, while `VehicleStore` independently consumes the service's state stream and assigns every incoming `VehicleState` to `vehicle.state`.

This has one desirable property:

- the feedback is tied to the **confirmed visible ride-mode state changing**, not merely to a finger-down event before the scooter confirms anything.

But it also has an important causal ambiguity:

- `vehicle.state.rideMode` can change because of an incoming state update that was not caused by this person's current tap;
- reconnect/restoration/simulation or another legitimate hardware/app source can therefore satisfy the same trigger;
- the user can receive a `selection` haptic for a domain-state update even though no local UI selection just occurred.

That conflicts with Apple's preference for a clear causal relationship between haptic and action.

This is the strongest current source-level haptics finding.

PR #70 is the incumbent Home owner, so this audit does not patch `HomeView.swift` in parallel.

### No custom Core Haptics / UIFeedbackGenerator subsystem found

No current app-owned `CHHapticEngine`, custom Core Haptics pattern, `UIImpactFeedbackGenerator`, `UISelectionFeedbackGenerator`, or `UINotificationFeedbackGenerator` path was found in the audited current app source.

That is a good production baseline. Nembra currently does not carry a separate haptic engine, waveform lifecycle, or custom continuous vibration behavior that would need power/lifecycle/cancellation hardening.

### Current Dashboard main has no explicit app-owned haptic

Current `DashboardView.swift` does not attach sensory feedback to:

- speed changes;
- ride-mode state;
- headlight/lock controls;
- connection transitions;
- trip or battery values.

This avoids noisy tactile output from high-frequency telemetry and passive cockpit state.

### In-flight Dashboard battery readout adds a local selection haptic

PR #57 (`battery-primary-readout-ui`) currently adds:

```swift
.sensoryFeedback(.selection, trigger: batteryReadoutModeRawValue)
```

The trigger is an app-local `@AppStorage` presentation preference changed by the readout button itself (`percentage` ↔ `estimatedRange`).

This is substantially cleaner causality than the current Home ride-mode trigger:

- the haptic accompanies a local UI value selection;
- the action changes presentation only;
- it does not imply scooter hardware confirmation;
- range may still be unavailable and the haptic communicates the readout-mode selection, not a fabricated range result.

PR #57 owns that implementation. This audit neither accepts nor modifies the branch; it records that the current patch's trigger semantics align with Apple's selection pattern.

## Command-confirmation boundary

`VehicleStore` implements pessimistic vehicle commands:

- inserts the relevant pending command;
- asks `ScooterService` to perform/confirm the change;
- leaves state truth to service updates/confirmed behavior;
- exposes explicit failure messages when confirmation fails.

That architecture is important for haptics.

### Never play success merely because a motorized-control button was tapped

For light, lock, ride mode, cruise, start mode, and speed limits, the button tap is only a request. A success haptic at tap time would falsely communicate completion before the scooter confirms the command.

If a future product lane adds an outcome haptic, it must be causally tied to the accepted command result, not to speculative local UI state.

### Selection vs success must match the event

For a presentation-only local preference such as `% ↔ range`, `.selection` is appropriate because a local UI selection changed.

For a confirmed operation, Apple defines notification-style success/error/warning feedback for operation outcomes. If Nembra later uses them, it should reserve them for sufficiently meaningful outcomes instead of making every ordinary confirmed toggle feel like a major notification.

Apple's own iOS haptics guidance uses unlocking a vehicle as an example of an operation-outcome context, but this does not mean every Nembra vehicle command requires a success haptic.

### Failure haptics are optional complements, never the failure record

`VehicleStore.lastErrorMessage` and the visible alert remain the semantic failure path. A future `.error` haptic can complement that result, but must not replace the alert/accessibility explanation and must not fire for a merely pending command.

## Telemetry and presentation truth boundary

Haptics can accidentally turn visual smoothing into felt "evidence." Nembra must avoid that.

### Speed

The Dashboard intentionally separates authoritative speed samples from interpolated/rolling presentation. There must be no haptic per interpolated frame, integer digit roll, or predicted midpoint.

A tactile tick on every rendered MPH transition would imply more measurement granularity than the scooter actually supplied and would be extremely noisy while riding.

### Battery

PR #45's battery transition planner explicitly labels intermediate integers as `presentationIntermediate`. Therefore future `84 → 83 → 82 → 81 → 80` visual traversal must **not** produce four tactile ticks that imply four measured packets arrived.

If battery haptics are ever added, they should correspond to a meaningful real product event (for example a legitimate threshold/warning policy), not each presentation frame.

### Adaptive range

Estimated range is a derived product estimate. A range-value update should not generate tactile feedback merely because the number changed. That would be noisy and could overstate precision/confidence.

### Automatic RideEngine

Normal ride start/continuity/recovery is automatic domain behavior, not a manual Start Ride workflow. Automatically haptically announcing every internal candidate/active/recovery transition risks confusing domain inference with an explicit user command.

If a future ride milestone deserves haptic feedback, define the user-facing event and evidence threshold first. Never attach haptics to internal state-machine churn.

### BLE / reconnect

A reconnect, retained-state refresh, or externally changed scooter state can update many visible values at once. Do not generate a cascade of selection/success haptics from each changed field.

## Recommended production haptic event matrix

This matrix is a policy/acceptance target, not an instruction for this audit lane to implement product code.

| Event | Recommended tactile policy | Why |
| --- | --- | --- |
| Battery `% ↔ range` local readout toggle | short `.selection` | direct local UI value selection; no hardware claim |
| Home/Dashboard ride-mode button request | no success at tap | request is not confirmed vehicle truth |
| Ride-mode confirmed because of this user's pending command | optional restrained selection/confirmation, causally gated | confirmed state can legitimately complete the interaction |
| Ride-mode change from reconnect/external state/simulation | normally no selection haptic | no local selection caused it |
| Headlight/lock/cruise/start-mode/speed-limit request | no success at tap | pessimistic command must confirm first |
| Significant confirmed lock/unlock outcome | optional restrained outcome feedback | meaningful discrete operation; must be tied to confirmation |
| Vehicle command failure | optional `.error` complement | visible/accessibility error remains authoritative |
| Connection/reconnection | normally visual/state feedback only | passive network/hardware lifecycle can be frequent |
| Low battery threshold | optional warning only with a stable, evidence-backed threshold policy | must not repeat on sag/recovery/presentation noise |
| Every battery integer animation frame | none | presentation-only, not telemetry |
| Every speed integer/interpolation frame | none | presentation-only/high frequency |
| Adaptive range recalculation | none | derived estimate can move often |
| GPS/location sample | none | background evidence plumbing |
| automatic ride-state internal transition | none by default | domain lifecycle is not necessarily explicit user action |
| navigation maneuver milestone | future navigation owner should evaluate short, standard, nonexclusive feedback | must complement visual/VoiceOver instructions and not distract while riding |

## Fix direction for current Home causal ambiguity

Do **not** simply move the Home haptic to the mode button tap. That would solve provenance while creating a worse truth problem: it would vibrate before the scooter confirms the requested mode.

The correct future implementation should preserve both requirements:

1. haptic only for a relevant confirmed state change;
2. know that the change corresponds to the current user's pending/requested mode interaction.

Possible implementation shapes include a UI/store confirmation token or an old/new condition that is only armed by the current local request and cleared on success/failure/reconnect. The exact design belongs to the incumbent Home/vehicle-command integration owner and should reuse existing pending-command truth rather than creating a competing command architecture.

A reconnect-discovered mode change should not consume a stale local haptic token.

## Accessibility and user-control acceptance

Haptics must never be the only way to know:

- whether a command succeeded or failed;
- whether the scooter is connected;
- whether battery is low;
- what ride mode is selected;
- whether range is available/estimated;
- what navigation maneuver is next.

Test with haptics unavailable/disabled and ensure common tasks remain complete through visible text/icons/state and VoiceOver.

The system can decline to play requested feedback depending on hardware/app/system conditions. Product logic must never wait for or infer success from whether a haptic played.

## Physical-device acceptance is different from Simulator acceptance

Nembra's normal visual baseline is iPhone 12 / iOS 27 Simulator, but tactile quality cannot be accepted from a screenshot or by assuming a Simulator run physically reproduces the Taptic Engine.

For a final haptics release checkpoint, use a supported physical iPhone and verify:

- intended events feel once, at the correct causal moment;
- external/passive state changes do not produce misleading tactile confirmations;
- rapid repeated UI actions cannot create a haptic storm;
- disabled/system-suppressed haptics do not break any task;
- VoiceOver and visible feedback remain semantically complete;
- feedback remains restrained during actual riding interaction.

This is physical **phone** UX evidence, not physical AOVOPRO ES80 telemetry/protocol proof. If a test also exercises a real ES80 command, record the command/hardware evidence separately.

## Acceptance / regression scenarios

At a coherent implementation checkpoint, cover at least:

1. local battery readout toggle produces exactly one selection event when feedback is available;
2. unavailable battery readout cannot cause a misleading range-selection haptic if the control is disabled;
3. user-requested ride-mode confirmation may produce the accepted haptic only after confirmation;
4. rejected/disconnected mode command never produces a success/selection confirmation for the requested result;
5. incoming mode change with no local request does not haptically impersonate a user selection;
6. reconnect/restoration with a different confirmed mode does not trigger stale local feedback;
7. battery presentation traversal does not haptic per intermediate frame;
8. speed interpolation/rolling digits never haptic per rendered value;
9. repeated connection/state packets do not emit haptic cascades;
10. haptics disabled/unavailable leaves all tasks understandable and operable.

Deterministic state-transition tests can prove causal gating logic, but the tactile character/timing itself still requires physical-device evaluation.

## Active-worker boundaries

Do not duplicate current owners:

- PR #70 owns Home hierarchy/`HomeView.swift`;
- PR #57 owns Dashboard battery readout + its local selection haptic;
- PR #45 owns battery presentation-transition semantics;
- PR #33 owns Dashboard high-frequency presentation performance;
- PR #41/#77 own navigation core/adapter work;
- current command semantics remain in `VehicleStore`/ScooterService architecture and are not changed by this audit.

Any product implementation should be assigned after the relevant incumbent owner/dependency settles, rather than patching their files from this lane.

## Truth / safety boundary

This audit does not:

- change or fabricate telemetry;
- treat a haptic as evidence;
- change measured/estimated/display battery classification;
- change speed or range evidence;
- alter ride lifecycle;
- send BLE/Tuya commands or motorized-hardware writes;
- claim a successful command because tactile feedback occurred;
- establish physical ES80 protocol behavior.

A haptic is presentation feedback only.

## Acceptance conclusion

Current Nembra has a deliberately small haptic footprint, which is good. The cleanest in-flight example is the local battery `% ↔ range` selection in PR #57. The one current-main risk is Home's ride-mode `.selection` trigger being attached to the global confirmed `rideMode` value without user-action provenance.

The production direction should therefore be **less but better**:

- preserve haptics for discrete, causal interactions/outcomes;
- gate motorized-command confirmation feedback to actual confirmed user-originated results;
- never haptic presentation intermediates or high-frequency telemetry;
- preserve complete visual/VoiceOver semantics when haptics are suppressed;
- physically evaluate tactile timing/quality on a supported iPhone before calling the final haptic experience production-ready.
