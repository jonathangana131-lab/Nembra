# ES80 Authenticated Stationary Gate — V14

Status: **NO-GO — DO NOT RUN THE NEXT PHYSICAL SESSION YET.**

Protocol: V14  
Feature: Nembra Capture / ES80 physical truth  
Physical predecessor: `docs/ES80_PHYSICAL_TRUTH_C7D09A22.md`  
Baseline device: intended iPhone 12 / iOS 27  
Physical motion requirement: stationary for the entire experiment

## Purpose

This document pins the *next* physical gate after accepted capture `C7D09A22-96DA-4E46-9BEF-E36F670ADB0E`.

C7D09A22 physically verified the modern Tuya FD50 transport, but it received zero application characteristic payloads and repeatedly disconnected at about 29.930 seconds. Therefore the next useful physical experiment is **not** another 17-step ride/fingerprint replay. It is the smallest stationary experiment that can demonstrate a legitimate authenticated Tuya application session and collect genuine application notifications.

This document is a coordination/acceptance checkpoint only. It cannot authorize Bluetooth activity by itself. Only the final composed exact app build, with all required software/private-device gates accepted, may flip this gate to `GO`.

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

`docs/ES80_TODAY_PRIVATE_FIELD_RUNBOOK.md` is still pinned to the earlier frozen Capture subject `#833@a0f4a33451f61411d6e0541f2e70edea5438342d` and the original private `ES80-FINGERPRINT-v1` field flow.

That prior runbook remains historical evidence for the first fingerprint field path, but its frozen source/build record **does not authorize this post-C7D09A22 authenticated-session experiment**. Do not reuse its old Final GO subject, signed IPA, retained-artifact identity, or historical target UUID as authorization for this gate.

## Current software acceptance snapshot

At the time this gate was authored:

- `main`: `b1ac247def491c7c76fa06212a1c1ad46313aab8`;
- current app-authority candidate: PR `#2094` at `9931f9e3d54f563bd37c5f983b49e27b6f13b5b4`;
- adversarial fresh-target/acquisition-terminal contract: PR `#2100` at `2f5f6904d377e91803604848b3902273290bd57b`;
- transport-success lifecycle repair: PR `#2102` at `c96dd8429d71b59cd0baa3eab9dad4b4152bf9b9`.

These heads are coordination facts, not accepted composition. A child PR, package green, source review, or old/ancestor Xcode success cannot authorize the physical session.

## Remaining software blockers before GO

The final composed candidate must close all of these on one exact head:

1. **Fresh target correlation.** Do not promote the historical C7D09A22 CoreBluetooth UUID to durable target authority. Run the accepted deterministic `OFF1 -> ON1 -> OFF2 -> ON2` correlation using full CoreBluetooth peripheral identity, accepted bounded observation windows, and fail-closed ambiguity handling.
2. **Explicit target confirmation.** Authentication must not begin merely because a candidate was auto-selected. The operator must explicitly confirm the one freshly correlated candidate.
3. **Non-authoritative hints stay non-authoritative.** Name, RSSI, local-name similarity, FD50 presence, Tuya company/product hints, and service-name vibes may be descriptive only; they cannot break ties or mint target identity.
4. **Exact private source authority.** The final app must use the intended private Tuya account/session authority, verify the exact same-account UID/device membership required by the accepted contract, and fail closed on source drift.
5. **Truthful local-BLE acquisition terminal.** A local-BLE timeout or invalid monotonic clock must not masquerade as Tuya account/source-authority invalidation.
6. **Transport-success lifecycle closure.** Duplicate/stale success callbacks, source drift during settlement, chronology rejection, and settlement ownership must terminally/uniquely resolve the current generation without silently stranding it.
7. **One BLE owner.** The authenticated Tuya driver and local observation path must not race independent BLE owners for the same scooter/session.
8. **No semantic query or control expansion.** This gate must not add DP queries, unknown scooter commands, random characteristic writes, control toggles, or telemetry interpretation merely to provoke traffic.
9. **Canonical evidence seal/export.** Genuine application notifications must be admitted through the accepted chronology/provenance model, sealed immutably, and exported without credentials/secrets.
10. **Exact-head app acceptance.** The final composed head must receive the required focused/source tests and exact-head Xcode 27 app/Capture runtime acceptance. Red, queued, cancelled, skipped, ancestor, child-only, or package-only results are not acceptance.
11. **Private intended-device acceptance.** The final accepted build identity and exact signed install must be bound to the intended iPhone 12 / iOS 27 and the intended private Tuya workspace/dependency provenance. No stale retained IPA or rebuilt substitute may inherit authority.
12. **Final GO record.** Only after the exact composed candidate passes all applicable gates may a procedure record name the exact source SHA, build identity, signed artifact/install identity, recipe/procedure, expected artifact, and stop conditions.

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
8. If the result is none, ambiguous, interrupted, lifecycle-invalid, or otherwise incomplete, stop. Do not use name/RSSI/FD50/Tuya hints or the old C7D09A22 UUID to guess.

The correlation step establishes only attempt-local target authority. It does not establish permanent hardware identity or telemetry semantics.

## Authenticated stationary experiment once GO exists

After exact target confirmation:

1. Keep the scooter stationary and charger state consistent with the final accepted procedure.
2. Establish the accepted legitimate Tuya authenticated application session for the already-bound scooter without unbinding, factory reset, or speculative control activity.
3. Subscribe/observe only through the accepted application notification path and accepted read-only evidence policy.
4. Do **not** send DP queries, unknown commands, random writes, light/lock/mode/speed-limit controls, or other traffic merely to solicit a response.
5. Preserve every admitted raw application notification with exact connection generation, characteristic identity, callback/receipt order, monotonic timing, source/provenance, and build/procedure identity.
6. Keep the accepted authenticated session alive past the old approximately-30-second rejection region; the target gate is at least **45 seconds** of accepted authenticated continuity.
7. Seal through the canonical evidence path and use the app's normal Share/export flow only after acceptance conditions are met.

## Physical PASS conditions

This experiment may be classified `PASS` only if the sealed accepted artifact proves all of the following for the same current authenticated generation:

- fresh target correlation completed and the operator explicitly confirmed the one accepted candidate;
- accepted Tuya authentication provenance exists for the intended already-bound device/account;
- at least **one genuine non-empty application notification payload** was admitted from the physical FD50 device-to-app notification characteristic;
- the authenticated connection remained continuously accepted beyond the old rejection window, with a target of at least **45 seconds**;
- the evidence remained observational/read-only under the accepted gate policy;
- raw payload bytes and chronology/provenance were sealed/exported without secrets;
- no stale generation, replayed callback, display interpolation, GPS/scenario timing, or caller-constructed authority was promoted into physical protocol truth.

A transport callback, write completion, notification subscription success, timer UI, or 45 seconds without a genuine application payload is **not** a physical PASS.

## Stop / fail-closed conditions

Stop the attempt and preserve only legitimately admitted evidence if any of these occurs:

- target correlation is none or ambiguous;
- the operator did not explicitly confirm the fresh target;
- the app backgrounds or required foreground/lifecycle integrity is lost;
- exact source/account/device membership authority changes or becomes uncertain;
- a stale/duplicate generation cannot be safely classified;
- Bluetooth/local-BLE acquisition fails or the accepted monotonic clock becomes invalid;
- the session disconnects before the accepted continuity target;
- no genuine non-empty application notification is received;
- artifact integrity/seal/export cannot be established;
- any unexpected command/control/write path becomes enabled;
- the exact installed build cannot prove the final accepted build/procedure identity.

Do not repair a failed physical attempt by relabeling missing evidence, substituting a different build, or inferring protocol semantics from timing/GPS/UI behavior.

## What PASS unlocks

A successful authenticated stationary gate unlocks only the **next smallest stationary semantic-correlation experiment**. It does not automatically establish speed, battery, current, power, mode, light, brake, lock, odometer, or command semantics.

After analyzing the sealed application payload artifact, identify exact remaining unknowns and generate the smallest safe next recipe—for example stationary idle/battery reference and individually controlled state changes—before considering moving/GPS scenarios.

## Durable handoff rule

Future workers must refresh live GitHub before using the software-head snapshot above. If `main`, #2094, #2100, #2102, or their successors change, live exact heads win. Preserve the invariant requirements in this document while updating coordination state.

A green checkpoint is not automatically the endpoint. The gate closes only when the final composed app is accepted and the physical session produces the required sealed authenticated payload evidence.