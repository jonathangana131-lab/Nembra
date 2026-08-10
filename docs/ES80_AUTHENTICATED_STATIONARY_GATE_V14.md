# ES80 Authenticated Stationary Gate — V14

Status: **NO-GO — DO NOT RUN THE NEXT PHYSICAL SESSION YET.**

Protocol: V14  
Feature: Nembra Capture / ES80 physical truth  
Physical predecessor: `docs/ES80_PHYSICAL_TRUTH_C7D09A22.md`  
Baseline device: intended iPhone 12 / iOS 27  
Physical motion requirement: stationary for the entire experiment

## Purpose

This document pins the next physical gate after accepted capture `C7D09A22-96DA-4E46-9BEF-E36F670ADB0E`.

C7D09A22 physically verified the modern Tuya FD50 transport, but it received zero application characteristic payloads and repeatedly disconnected at about 29.930 seconds. Therefore the next useful physical experiment is **not** another 17-step ride/fingerprint replay. It is the smallest stationary experiment that can demonstrate a legitimate authenticated Tuya application session, preserve genuine application notification evidence, and survive beyond the old rejection region.

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

## Current software convergence snapshot

At this document revision:

- `main`: `b1ac247def491c7c76fa06212a1c1ad46313aab8`;
- obsolete app-authority parent: PR `#2094` at `9931f9e3d54f563bd37c5f983b49e27b6f13b5b4` — exact-head Xcode run failed and its historical-UUID target authority is superseded;
- fresh-target app successor: PR `#2109` at `fab6bb700b5670be2e964d7a987a4fefb079296a`;
- transport-success lifecycle repair donor: PR `#2102` at `c96dd8429d71b59cd0baa3eab9dad4b4152bf9b9`;
- no-resample chronology-integrity terminal donor: closed/unmerged PR `#2108` at `f4a671fd15949467308537a9cde552626e4d87b0`;
- app-visible field-build authority red contract: PR `#2104` at `e590f2b787d3d42ef092e30ee90babad6c3ee303`;
- authenticated raw FD50 evidence-ledger donor: PR `#1997` at `10357b8a3fd8f8d311c2553dfb63c67a978eab93`;
- opaque-payload telemetry-authority hardening: PR `#2099` at `783b2b19762a32d7d3a288056f38226972c575cc`.

These heads are coordination facts, not accepted composition. A child PR, donor branch, package green, source review, queued/skipped workflow, or ancestor Xcode success cannot authorize the physical session. Future workers must refresh live GitHub; newer accepted composition wins over this snapshot.

## Remaining software blockers before GO

The final composed candidate must close all applicable items on one exact head:

1. **Fresh target correlation.** Do not promote the historical C7D09A22 CoreBluetooth UUID to durable target authority. Run the accepted deterministic `OFF1 -> ON1 -> OFF2 -> ON2` correlation using full CoreBluetooth peripheral identity, accepted bounded observation windows, and fail-closed ambiguity handling.
2. **Explicit target confirmation.** A unique correlated candidate is not automatically operator-confirmed. Present the exact package result as a correlated Bluetooth target and require a distinct explicit confirmation action before authentication may begin. Do not expose arbitrary candidate selection or hint-based override.
3. **Non-authoritative hints stay non-authoritative.** Name, RSSI, local-name similarity, FD50 presence, Tuya company/product hints, one-cycle appearance, and service-name vibes may be descriptive only; they cannot break ties or mint target identity.
4. **Preserve correlation provenance.** Do not collapse the four-window result to only a winning UUID. The accepted artifact must preserve enough non-secret deterministic evidence to audit why the target earned current-attempt authority: accepted procedure/recipe identity, four sealed window receipt/snapshot metadata, complete full-UUID/connectability catalogs or an equivalent canonical package representation, final correlation disposition, and the explicit operator-confirmation fact.
5. **App-visible exact build authority.** The primary preflight UI must consume compiled build authority directly. `Field build`, the primary NO-GO treatment, and the first OFF1 action must visibly reflect `buildIdentity.isAuthoritativeFieldBuild`; an action that looks enabled but immediately fails a hidden runtime build guard is not accepted product truth. Preserve the runtime guard as defense in depth.
6. **Exact private Tuya source authority.** The final app must use the intended private Tuya account/session authority, freshly verify exact same-account UID/device membership required by the accepted contract, bind the lease to that identity, and fail closed on source drift without logging/exporting credentials or account identity.
7. **Truthful local-BLE acquisition terminal.** A normal bounded local-BLE acquisition timeout must resolve as authentication/acquisition failure. It must not masquerade as Tuya account/source-authority invalidation.
8. **No-resample chronology terminal.** A regressed/invalid monotonic clock or authentication-promotion chronology rejection must be able to retire the exact current generation **without taking another authorizing clock sample**. Do not hide a failing ordinary terminal with `try?` and then clear only controller state while package callback authority remains alive. Genuine account/membership drift remains source-authority invalidation; real transport loss remains transport loss.
9. **Transport-success lifecycle closure.** Current-generation phase/source/driver drift may not silently return and strand an authenticating ledger generation. Enforce one bounded local-BLE settlement owner per current generation; duplicate/stale transport-success callbacks are idempotently classified; authentication-promotion rejection terminally retires the current generation; settlement ownership clears on every terminal/reset path.
10. **One BLE owner.** Fresh CoreBluetooth correlation must retire before supported Tuya authenticated BLE ownership begins. Do not create a second competing CoreBluetooth connection merely to observe bytes while the official Tuya/SmartLife session owns the scooter.
11. **Genuine authenticated application evidence.** The physical artifact must not relabel a structured SDK `dpsUpdate` string projection as byte-exact FD50 notification data. If final physical acceptance requires raw FD50 notification bytes, the composed build must prove an accepted legitimate raw-byte source under the one-owner rule and feed it through an admission ledger equivalent to the #1997 contract: exact physical notify characteristic, current authenticated generation, non-empty payload, monotonic receipt chronology, immutable receipt order, and credential-free raw-byte preservation such as base64/hex. Structured SDK application updates may be retained as additional application-level evidence but must be labeled as such.
12. **No silent weakening of the raw-evidence gate.** If investigation proves the supported official SDK surface cannot lawfully expose byte-exact notifications without violating the one-owner/session contract, the swarm must stop and make that limitation explicit. A reviewed successor may deliberately define a different smallest physical evidence gate, but no implementation may silently call `String(describing:)` DP values “raw payloads” to claim the original gate passed.
13. **Opaque payloads do not mint telemetry semantics.** Even one real non-empty application payload proves only application-layer receipt. Transport evidence remains unable to authorize speed, battery, voltage, current, power, mode, odometer, command acknowledgement, or any other field meaning until a separately accepted repeatable decoding/correlation contract exists.
14. **Canonical evidence seal/export.** Accepted notification/application evidence and target-correlation provenance must be admitted through the accepted chronology/provenance model, frozen immutably, and exported without credentials/secrets. Delayed callbacks after seal cannot mutate the accepted prefix.
15. **No semantic query or control expansion.** This gate must not add DP queries, unknown scooter commands, random characteristic writes, control toggles, or telemetry interpretation merely to provoke traffic.
16. **Exact-head app acceptance.** The final composed head must receive the required focused/source tests and exact-head Xcode 27 app/Capture runtime acceptance. Red, queued, cancelled, skipped, ancestor, child-only, or package-only results are not acceptance.
17. **Private intended-device acceptance.** The final accepted build identity and exact signed install must be bound to the intended iPhone 12 / iOS 27 and the intended private Tuya workspace/dependency provenance. No stale retained IPA or rebuilt substitute may inherit authority.
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

1. Keep the scooter stationary and charger state consistent with the final accepted procedure.
2. Establish the accepted legitimate Tuya authenticated application session for the already-bound scooter without unbinding, factory reset, or speculative control activity.
3. Observe only through the final accepted read-only/session evidence path.
4. Do **not** send DP queries, unknown commands, random writes, light/lock/mode/speed-limit controls, or other traffic merely to solicit a response.
5. Preserve every admitted application evidence item with exact current connection generation, source identity, callback/receipt order, monotonic timing, and build/procedure provenance. Where byte-exact FD50 notification evidence is accepted, preserve the raw bytes and exact notification characteristic identity.
6. Keep the accepted authenticated session alive past the old approximately-30-second rejection region; the target gate is at least **45 seconds** of accepted authenticated continuity.
7. Seal through the canonical evidence path and use the app's normal Share/export flow only after acceptance conditions are met.

## Physical PASS conditions

The original authenticated raw-evidence experiment may be classified `PASS` only if the sealed accepted artifact proves all of the following for the same current authenticated generation:

- fresh target correlation completed and the operator explicitly confirmed the one accepted candidate;
- the four-window target-correlation provenance and confirmation fact are preserved;
- accepted Tuya authentication provenance exists for the intended already-bound device/account;
- at least **one genuine non-empty application notification payload** is admitted from the accepted physical FD50 device-to-app notification source; byte-exact evidence is preserved where the final GO contract requires it;
- the authenticated connection remained continuously accepted beyond the old rejection window, with a target of at least **45 seconds**;
- the evidence remained observational/read-only under the accepted gate policy;
- admitted application/raw evidence and chronology/provenance were sealed/exported without secrets;
- no opaque payload was promoted directly into telemetry semantics;
- no stale generation, replayed callback, display interpolation, GPS/scenario timing, or caller-constructed authority was promoted into physical protocol truth.

A transport callback, write completion, notification subscription success, timer UI, structured `dpsUpdate` string projection mislabeled as raw bytes, or 45 seconds without accepted genuine application evidence is **not** a physical PASS.

## Stop / fail-closed conditions

Stop the attempt and preserve only legitimately admitted evidence if any of these occurs:

- target correlation is none or ambiguous;
- the operator did not explicitly confirm the fresh target;
- correlation provenance cannot be preserved;
- the app backgrounds or required foreground/lifecycle integrity is lost;
- exact build/source/account/device membership authority changes or becomes uncertain;
- a stale/duplicate generation cannot be safely classified;
- Bluetooth/local-BLE acquisition fails or the accepted monotonic clock becomes invalid and the exact generation cannot be safely retired;
- the session disconnects before the accepted continuity target;
- the required genuine application evidence is not received;
- required byte-exact evidence is unavailable under the final accepted raw-evidence contract;
- artifact integrity/seal/export cannot be established;
- any unexpected command/control/write path becomes enabled;
- the exact installed build cannot prove the final accepted build/procedure identity.

Do not repair a failed physical attempt by relabeling missing evidence, substituting a different build, weakening raw-vs-structured evidence terminology, or inferring protocol semantics from timing/GPS/UI behavior.

## What PASS unlocks

A successful authenticated stationary gate unlocks only the **next smallest stationary semantic-correlation experiment**. It does not automatically establish speed, battery, current, power, mode, light, brake, lock, odometer, or command semantics.

After analyzing the sealed application payload artifact, identify exact remaining unknowns and generate the smallest safe next recipe—for example stationary idle/battery reference and individually controlled state changes—before considering moving/GPS scenarios.

## Durable handoff rule

Future workers must refresh live GitHub before using the software-head snapshot above. Live exact heads and accepted composition win. Preserve the invariant requirements in this document while updating coordination state.

A green checkpoint is not automatically the endpoint. The gate closes only when the final composed app is accepted and the physical session produces the required sealed authenticated evidence.