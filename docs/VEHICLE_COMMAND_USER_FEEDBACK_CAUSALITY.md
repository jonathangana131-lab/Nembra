# Vehicle Command User Feedback Causality

Worker: `chat-f6q3v`

## Product gap

Nembra must not present tactile success merely because a global confirmed vehicle field changed. A reconnect, restored state, Simulator fixture, or another accepted observation can legitimately change `VehicleState` without being caused by the user's current interaction.

The production haptics audit therefore requires both command truth and causal provenance: a user-initiated request must be correlated to its matching accepted outcome before a product surface may consider command-completion feedback.

## Scope

`VehicleCommandUserFeedbackCorrelation` is a narrow presentation-causality primitive. It owns no scooter command and establishes no physical authority.

It:
- mints an opaque identity for one app-local user request;
- permits only one unresolved local request, matching Nembra's current serialized vehicle-command policy;
- accepts only the exact current request identity when the command owner later supplies an already-accepted outcome;
- rejects foreign/recreated coordinator tokens even when their visible sequence number matches;
- rejects stale and duplicate resolution;
- permits lifecycle/cancellation abandonment without manufacturing a success or failure event;
- carries no haptic pattern so each product surface can choose whether a confirmed outcome merits selection/success feedback or no tactile feedback.

## Truth boundary

The caller remains the command-truth authority. Calling `resolve(..., as:)` is valid only after the existing command/service architecture has accepted the matching outcome.

This primitive never:
- observes `VehicleState`;
- compares requested and observed values;
- treats a CoreBluetooth write completion as scooter acknowledgement;
- treats subscription success as vehicle acknowledgement;
- verifies AOVOPRO ES80 commands or protocol semantics;
- invents a command success merely because transport remains connected;
- turns Simulator behavior into physical evidence.

A future app integration should begin the correlation only for an actual local control request and resolve it only at the accepted matching command-outcome boundary. Passive state restoration/reconnect must not call `resolve` and therefore cannot emit user-command completion feedback through this gate.

## Acceptance

The additive source/test slice is designed for NembraCore package validation. Supplemental Swift 6.2.1 warnings-as-errors testing covers exact confirmation, failure, duplicate begin, foreign-owner identity, stale-request rejection, exact abandonment, and mismatched abandonment preserving the real pending request.

Repository/Xcode exact-head validation remains the integration authority. This software primitive does not require or claim physical ES80 validation.
