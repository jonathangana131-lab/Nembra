# ES80 Authenticated Stationary Gate — V14

Status: **NO-GO — DO NOT RUN THE NEXT PHYSICAL SESSION YET.**

Protocol: V14  
Feature: Nembra Capture / ES80 physical truth  
Physical predecessor: `docs/ES80_PHYSICAL_TRUTH_C7D09A22.md`  
Canonical procedure: `docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md`  
Baseline device: intended iPhone 12 / iOS 27  
Physical motion requirement: stationary for the entire experiment

## Purpose

This document pins the next physical gate after accepted capture `C7D09A22-96DA-4E46-9BEF-E36F670ADB0E`.

C7D09A22 physically verified the modern Tuya FD50 transport, but it received zero application characteristic payloads and repeatedly disconnected at about 29.930 seconds. Therefore the next useful physical experiment is **not** another 17-step ride/fingerprint replay. It is the smallest stationary experiment that can demonstrate a legitimate authenticated Tuya application session, preserve genuine application evidence, and prove that the authenticated application path itself survives beyond the old rejection region.

This document is a coordination/acceptance checkpoint only. It cannot authorize Bluetooth activity by itself. Only the final composed exact app build, with all required software/private-device gates accepted, may flip this gate to `GO`.

## Canonical executable acceptance authority

The executable gate in `TuyaAuthenticatedReadOnlyPreflight` is authoritative for the software contract. The stationary physical PASS must preserve the same minimums on one current SmartLife-authenticated generation:

- at least **two genuine non-empty same-generation application payloads**;
- the latest accepted application payload must occur at least 30 seconds after authentication; and
- at least **45 seconds of canonical authenticated continuity measured from authentication**.

A weaker prose rule such as “one payload + >30 seconds connected” is not an alternate acceptance path and must never authorize field execution or stationary DP mapping. One callback plus 45 seconds of generic connection liveness is **not** a physical PASS.

## Accepted predecessor truth

From `docs/ES80_PHYSICAL_TRUTH_C7D09A22.md`:

- physical transport family: Tuya FD50;
- service: `FD50`;
- app-to-device characteristic: `00000001-0000-1001-8001-00805F9B07D0` (`write`, `writeWithoutResponse`);
- device-to-app characteristic: `00000002-0000-1001-8001-00805F9B07D0` (`notify`);
- CCCD: `2902`;
- power-on advertisement manufacturer data begins with Tuya company identifier `0x07D0`;
- application payload count: `0`;
- peripheral-initiated disconnects: `15`;
- mean connected interval before rejection: approximately `29.930 s`.

The C7D09A22 CoreBluetooth peripheral UUID `6815A5F5-4D1E-E004-BAE8-6DF924123907` is **historical capture-local evidence only**. It is not a durable physical scooter identity and must not be used as positive target authority for a later attempt.

No DP ID, field meaning, scale, signedness, cadence, command acknowledgement, battery, voltage, current, power, speed, mode, light, lock, cruise, trip, or odometer semantics are physically established yet.

## Superseded field-path warning

Historical private field runbooks and retained artifacts from the first fingerprint flow do not authorize this post-C7D09A22 authenticated-session experiment. Do not reuse an old Final GO subject, signed IPA, retained-artifact identity, or historical target UUID as authorization for this gate.

The current canonical operational procedure is `docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md`. Supporting documents may explain predecessor truth, but they may not weaken the compiled `TuyaAuthenticatedReadOnlyPreflight` contract.

## Remaining software blockers before GO

The final composed candidate must close all applicable items on one exact head:

1. **Fresh target correlation.** Do not promote the historical C7D09A22 CoreBluetooth UUID to durable target authority. Run the accepted deterministic `OFF1 -> ON1 -> OFF2 -> ON2` correlation using full CoreBluetooth peripheral identity, accepted bounded observation windows, and fail-closed ambiguity handling.
2. **Explicit target confirmation.** A unique correlated candidate is not automatically operator-confirmed. Present the exact package result as a correlated Bluetooth target and require a distinct explicit confirmation action before authentication may begin. Do not expose arbitrary candidate selection or hint-based override.
3. **Non-authoritative hints stay non-authoritative.** Name, RSSI, local-name similarity, FD50 presence, Tuya company/product hints, one-cycle appearance, and service-name vibes may be descriptive only; they cannot break ties or mint target identity.
4. **Preserve correlation provenance.** Do not collapse the four-window result to only a winning UUID. The accepted artifact must preserve enough non-secret deterministic evidence to audit why the target earned current-attempt authority: accepted procedure/recipe identity, four sealed window receipt/snapshot metadata, complete full-UUID/connectability catalogs or an equivalent canonical package representation, final correlation disposition, and the explicit operator-confirmation fact.
5. **Exact build + one-time field authorization.** Complete build metadata is required provenance but is not sufficient OFF1 authority. The package-owned one-time signed authorization session must freshly reach `.armed` for the live app attempt, and exact same-account scooter authority must still be current before OFF1 can be admitted.
6. **Exact private Tuya source authority.** The final app must use the intended private Tuya account/session authority, freshly verify exact same-account UID/device membership required by the accepted contract, bind the lease to that identity, and fail closed on source drift without logging/exporting credentials or account identity.
7. **Truthful local-BLE acquisition terminal.** A normal bounded local-BLE acquisition timeout must resolve as authentication/acquisition failure. It must not masquerade as Tuya account/source-authority invalidation.
8. **No-resample chronology terminal.** A regressed/invalid monotonic clock or authentication-promotion chronology rejection must be able to retire the exact current generation without taking another authorizing clock sample. Genuine account/membership drift remains source-authority invalidation; real transport loss remains transport loss.
9. **Transport-success lifecycle closure.** Current-generation phase/source/driver drift may not silently strand an authenticating ledger generation. Duplicate/stale transport-success callbacks must be idempotently classified, rejection must retire the exact generation, and settlement ownership must clear on every terminal/reset path.
10. **One BLE owner.** Fresh CoreBluetooth correlation must retire before supported Tuya authenticated BLE ownership begins. Do not create a second competing CoreBluetooth connection merely to observe bytes while the official Tuya/SmartLife session owns the scooter.
11. **Genuine authenticated application evidence.** Physical readiness requires repeated same-generation application evidence from the accepted authenticated SmartLife session. A single bootstrap/state-replay callback is insufficient, and transport liveness alone cannot substitute for ongoing application evidence.
12. **No silent raw-evidence relabeling.** The current supported SDK path may retain structured `ThingSmartDeviceDelegate.dpsUpdate` application evidence, but must not call `String(describing:)` projections byte-exact/raw FD50 notification bytes. Raw authenticated FD50/ATT evidence remains a separate unresolved rung and may be claimed only if a supported same-session one-owner source is later proven.
13. **Opaque payloads do not mint telemetry semantics.** Even accepted repeated application payloads prove only application-layer receipt. They do not authorize speed, battery, voltage, current, power, mode, odometer, command acknowledgement, or any other field meaning until a separately accepted repeatable decoding/correlation contract exists.
14. **Canonical evidence seal/export.** Accepted application evidence and target-correlation provenance must be admitted through the accepted chronology/provenance model, frozen immutably, and exported without credentials/secrets. Delayed callbacks after seal cannot mutate the accepted prefix.
15. **No semantic query or control expansion.** This gate must not add DP queries, unknown scooter commands, random writes, control toggles, or telemetry interpretation merely to provoke traffic.
16. **Exact-head app acceptance.** The final composed head must receive the required focused/source tests and exact-head Xcode 27 app/Capture runtime acceptance. Red, queued, cancelled, skipped, ancestor, child-only, or package-only results are not acceptance.
17. **Private intended-device acceptance.** The final accepted build identity and exact signed install must be bound to the intended iPhone 12 / iOS 27 and intended private Tuya workspace/dependency provenance. No stale retained IPA or rebuilt substitute may inherit authority.
18. **Final GO record.** Only after the exact composed candidate passes all applicable gates may a procedure record name the exact source SHA, build identity, signed artifact/install identity, recipe/procedure, expected artifact, and stop conditions.

Until every applicable blocker is closed on one final composed exact build, status remains **NO-GO / DO NOT SCAN / DO NOT RUN**.

## Required target-correlation sequence once GO exists

All interaction is stationary and foreground-only.

1. **OFF1** — scooter physically off; complete the package-owned bounded observation window.
2. **ON1** — power scooter on; complete the full window.
3. **OFF2** — power scooter off; complete the full window.
4. **ON2** — power scooter on; complete the full window.
5. Continue only if the accepted correlation authority yields exactly one repeatable full peripheral identity that is present in both ON windows and absent in both OFF windows under the accepted contract.
6. Present it only as a **correlated Bluetooth target / scooter signal found**.
7. Require explicit operator confirmation of that exact freshly correlated candidate.
8. Preserve the sealed correlation evidence and confirmation fact for the final artifact.
9. If the result is none, ambiguous, interrupted, lifecycle-invalid, or otherwise incomplete, stop. Do not use name/RSSI/FD50/Tuya hints or the old C7D09A22 UUID to guess.

The correlation step establishes only attempt-local target authority. It does not establish permanent hardware identity or telemetry semantics.

## Authenticated stationary experiment once GO exists

After exact target confirmation:

1. Keep the scooter stationary with its charger physically disconnected under the current-attempt operator declaration contract.
2. Establish the accepted legitimate Tuya authenticated application session for the already-bound scooter without unbinding, factory reset, or speculative control activity.
3. Observe only through the final accepted read-only/session evidence path.
4. Do **not** send DP queries, unknown commands, random writes, light/lock/mode/speed-limit controls, or other traffic merely to solicit a response.
5. Preserve every admitted application evidence item with exact current connection generation, source identity, callback/receipt order, monotonic timing, and build/procedure provenance.
6. Require at least **two genuine non-empty same-generation application payloads**. The latest accepted application payload must occur at least 30 seconds after authentication.
7. Keep the accepted authenticated generation alive for at least **45 seconds of canonical authenticated continuity measured from authentication**.
8. Seal through the canonical evidence path and use the app's normal Share/export flow only after all canonical acceptance conditions are met.

## Physical PASS conditions

The authenticated stationary experiment may be classified `PASS` only if the sealed accepted artifact proves all of the following for the same current authenticated generation:

- fresh target correlation completed and the operator explicitly confirmed the one accepted candidate;
- the four-window target-correlation provenance and confirmation fact are preserved;
- accepted Tuya authentication provenance exists for the intended already-bound device/account;
- at least **two genuine non-empty same-generation application payloads** are admitted from the accepted authenticated application source;
- the latest accepted application payload occurs at least 30 seconds after authentication;
- at least **45 seconds of canonical authenticated continuity measured from authentication** is preserved;
- the evidence remained observational/read-only under the accepted gate policy;
- admitted application evidence and chronology/provenance were sealed/exported without secrets;
- structured SDK evidence is not mislabeled as byte-exact/raw FD50 transport data;
- no opaque payload was promoted directly into telemetry semantics;
- no stale generation, replayed callback, display interpolation, GPS/scenario timing, or caller-constructed authority was promoted into physical protocol truth.

One callback plus 45 seconds of generic connection liveness is **not** a physical PASS. Two early callbacks whose latest accepted payload is before the 30-second post-authentication boundary are also not a physical PASS. A transport callback, write completion, notification subscription success, timer UI, or structured `dpsUpdate` projection mislabeled as raw bytes does not close the gate.

## Stop / fail-closed conditions

Stop the attempt and preserve only legitimately admitted evidence if any of these occurs:

- target correlation is none or ambiguous;
- the operator did not explicitly confirm the fresh target;
- correlation provenance cannot be preserved;
- the app backgrounds or required foreground/lifecycle integrity is lost;
- exact build/source/account/device membership or one-time signed authorization authority changes or becomes uncertain;
- a stale/duplicate generation cannot be safely classified;
- Bluetooth/local-BLE acquisition fails or the accepted monotonic clock becomes invalid and the exact generation cannot be safely retired;
- fewer than two genuine same-generation application payloads are admitted;
- the latest accepted application payload does not occur at least 30 seconds after authentication;
- authenticated continuity does not reach 45 seconds from authentication;
- artifact integrity/seal/export cannot be established;
- any unexpected command/control/write path becomes enabled;
- the exact installed build cannot prove the final accepted build/procedure identity.

Do not repair a failed physical attempt by relabeling missing evidence, substituting a different build, weakening application-evidence timing, weakening raw-vs-structured terminology, or inferring protocol semantics from timing/GPS/UI behavior.

## What PASS unlocks

A successful authenticated stationary gate unlocks only the **next smallest stationary semantic-correlation experiment**. It does not automatically establish speed, battery, current, power, mode, light, brake, lock, odometer, or command semantics.

After analyzing the sealed application payload artifact, identify exact remaining unknowns and generate the smallest safe next recipe—for example stationary idle/battery reference and individually controlled state changes—before considering moving/GPS scenarios.

## Durable handoff rule

Future workers must refresh live GitHub before using any software-head snapshot. Live exact heads and accepted composition win. Preserve the invariant requirements in this document while updating coordination state.

A green checkpoint is not automatically the endpoint. The gate closes only when the final composed app is accepted and the physical session produces the required sealed authenticated evidence.
