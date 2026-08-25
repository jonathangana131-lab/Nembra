# ES80 Authenticated Stationary Gate — V14

Status: **NO-GO — DO NOT RUN THE NEXT PHYSICAL SESSION YET.**

Protocol: V14  
Feature: Nembra Capture / ES80 physical truth  
Physical predecessor: `docs/ES80_PHYSICAL_TRUTH_C7D09A22.md`  
Canonical acceptance floor: `docs/ES80_AUTHENTICATED_ACCEPTANCE_CONTRACT_V14.md`  
Baseline device: intended iPhone 12 / iOS 27  
Physical motion requirement: stationary for the entire experiment

## Purpose

Accepted capture `C7D09A22-96DA-4E46-9BEF-E36F670ADB0E` physically verified the modern Tuya FD50 transport, but it received zero application payloads and repeatedly disconnected at about 29.930 seconds.

The next useful physical experiment is therefore the smallest stationary experiment that can prove a legitimate authenticated SmartLife application session survived the historical rejection region and produced genuine same-generation application evidence.

This runbook is a coordination and physical-acceptance contract. It cannot authorize Bluetooth activity by itself. Only the final composed exact app build, with all required software, private-account/device, install, and runtime gates accepted, may flip this record to `GO`.

## Accepted predecessor truth

C7D09A22 physically established:

- transport family: Tuya FD50;
- service: `FD50`;
- app-to-device characteristic: `00000001-0000-1001-8001-00805F9B07D0` (`write`, `writeWithoutResponse`);
- device-to-app characteristic: `00000002-0000-1001-8001-00805F9B07D0` (`notify`);
- CCCD: `2902`;
- power-on advertisement manufacturer data beginning with Tuya company identifier `0x07D0`;
- application payload count: `0`;
- peripheral-initiated disconnects: `15`;
- mean connected interval before rejection: approximately `29.930 s`.

The historical CoreBluetooth peripheral UUID from C7D09A22 is capture-local evidence only. It is not durable scooter identity and cannot authorize a later attempt.

No DP ID, field meaning, scale, signedness, cadence, command acknowledgement, battery, voltage, current, power, speed, mode, light, lock, cruise, trip, or odometer semantics are physically established yet.

## Canonical authenticated acceptance floor

The shipping mechanical authority is `TuyaAuthenticatedReadOnlyPreflight`.

The current authenticated generation may become ready for stationary mapping only when **all** of the following are true for that same generation:

1. Authentication provenance is the official SmartLife App SDK for the current BLE generation.
2. At least **2** genuine, non-empty authenticated application updates have been admitted from that generation.
3. The **latest** accepted application update arrived at least **30 seconds after authentication**.
4. Authenticated continuity remained continuously accepted for at least **45 seconds after authentication**.
5. Connection/authentication/payload chronology remains valid and belongs to the same current generation.

The package also fail-closes an authenticated generation that reaches the bounded incomplete-observation horizon without satisfying the canonical verdict.

A single bootstrap callback is insufficient. Two early callbacks followed only by generic BLE liveness are insufficient. A connection lasting merely more than 30 seconds is insufficient. A 45-second connection without repeated late application evidence is insufficient. Simulator/test payloads are insufficient.

No document, historical issue, old PR body, or prior runbook may weaken these mechanical requirements.

## Read-only / safety boundary

The first authenticated experiment remains read-only at the product-semantic level.

Allowed activity is limited to the documented authentication/session establishment required by the supported SmartLife path and passive receipt of application evidence.

Do **not**:

- send arbitrary DP queries or control writes;
- probe undocumented characteristics merely because they are writable;
- toggle light, lock, mode, speed limit, cruise, or other scooter controls to solicit traffic;
- unbind, reset, factory-reset, transfer ownership, or alter scooter settings;
- create a second competing CoreBluetooth owner while the supported Tuya session owns BLE;
- interact with the phone while riding; this experiment is stationary anyway.

A transport write completion is not physical state acknowledgement.

## Fresh target authority

Every physical attempt must earn fresh attempt-local target authority before authentication:

1. **OFF1** — scooter physically off; complete the package-owned bounded observation window.
2. **ON1** — power scooter on; complete the full window.
3. **OFF2** — power scooter off; complete the full window.
4. **ON2** — power scooter on; complete the full window.
5. Continue only if the accepted correlation authority yields exactly one repeatable full CoreBluetooth identity present in both ON windows and absent in both OFF windows.
6. Present the result only as a **correlated Bluetooth target / scooter signal found**.
7. Require a distinct explicit operator confirmation of that exact freshly correlated candidate.
8. Preserve the four-window correlation provenance and confirmation fact in the accepted artifact.

Name, RSSI, local-name similarity, FD50 presence, Tuya company/product hints, one-cycle appearance, and historical UUIDs are descriptive only. They cannot break ties or mint target identity.

If the result is none, ambiguous, interrupted, lifecycle-invalid, or incomplete, stop. Do not guess.

## Private Tuya source authority

The final app must use the intended private Tuya account/session authority and freshly prove the accepted same-account UID/device membership contract before BLE discovery/authentication.

Credential material is private runtime authority. Never commit, print into normal logs, attach to fixtures/artifacts, or export tokens, local keys, session keys, passwords, account identity, or equivalent secrets.

Source/account/device drift must fail closed and must remain distinct from ordinary local-BLE acquisition failure or transport loss.

Device Sharing or account metadata alone cannot substitute for authentication of the current BLE generation.

## Lifecycle / chronology closure

The final composed candidate must preserve the package-owned lifecycle contracts already established by the Capture foundation:

- one bounded local-BLE settlement owner per current generation;
- duplicate/stale transport-success callbacks classified idempotently;
- authentication-promotion rejection terminally retires the exact current generation;
- invalid/regressed monotonic chronology can retire the generation without taking a fresh authorizing clock sample;
- settlement ownership clears on every terminal/reset path;
- stale callbacks from an older generation cannot satisfy the current gate;
- accepted evidence chronology is immutable at seal.

A normal bounded local-BLE timeout is authentication/acquisition failure, not account/source-authority invalidation.

## Genuine application evidence

Application evidence must be attributed to the current authenticated generation and accepted target.

Structured SDK application updates may satisfy the package-owned authenticated application-evidence gate only when admitted through the accepted same-generation chronology model. They must remain labeled as structured application evidence.

If a final physical GO contract separately requires byte-exact FD50 notification evidence, the build must prove a legitimate package-owned raw-byte source under the one-BLE-owner rule and preserve those bytes with exact source identity, receipt order, monotonic timing, and secret-free encoding.

Never relabel `String(describing:)` output, structured `dpsUpdate` projections, simulator fixtures, or raw-looking synthetic bytes as byte-exact physical FD50 notification evidence.

If the supported official SDK cannot lawfully expose byte-exact notifications under the one-owner contract, stop and make that limitation explicit. A reviewed successor may deliberately define a different smallest physical evidence gate; no implementation may silently weaken terminology to claim success.

## Opaque payload truth boundary

Even a fully accepted authenticated application gate proves only application-path continuity and receipt.

Opaque payloads do **not** directly authorize:

- speed;
- battery percentage or charging state;
- voltage;
- current;
- watts / power;
- mode;
- light;
- brake / throttle;
- lock / cruise / speed limit;
- trip;
- odometer;
- command acknowledgement.

Those semantics require a separate repeatable physical decoding/correlation contract.

GPS, scenario timing, display interpolation, simulator values, historical odometer references, or generic Tuya assumptions must never be transformed into Bluetooth semantics.

## Canonical evidence seal / export

Accepted target-correlation, authentication, application-evidence, and chronology provenance must be admitted through the canonical evidence model and frozen immutably.

The final artifact must:

- preserve accepted receipt order and monotonic timing;
- preserve current-generation identity/provenance without secrets;
- preserve the correlation/confirmation proof needed to audit target authority;
- reject stale/replayed application deliveries;
- prevent delayed callbacks after the accepted seal from mutating the frozen prefix;
- export through the normal Capture Share flow;
- embed exact build/procedure provenance without credential material.

## Remaining blockers before GO

The physical experiment remains NO-GO until one final composed exact build closes every applicable item below:

1. **Exact current build authority.** The primary preflight UI and runtime guard both consume the compiled authoritative field-build identity.
2. **Fresh target correlation and explicit confirmation.** OFF1 -> ON1 -> OFF2 -> ON2 succeeds unambiguously and preserves provenance.
3. **Exact private source authority.** Current intended Tuya account/device membership is freshly revalidated and leased to the same session.
4. **One BLE owner.** Correlation CoreBluetooth ownership retires before supported SmartLife authenticated BLE ownership begins.
5. **Lifecycle/chronology settlement.** Current-generation success, rejection, timeout, drift, duplicate, reset, and terminal paths cannot strand package callback authority.
6. **Canonical 2 / 30 s / 45 s gate.** The app cannot reach acceptance before `TuyaAuthenticatedReadOnlyPreflight.verdict(for:)` returns `readyForStationaryMapping`.
7. **Truthful application evidence.** Structured-vs-raw provenance is explicit; no synthetic or mislabeled evidence can pass.
8. **Immutable seal/export.** Accepted evidence and target provenance freeze secret-free and cannot be mutated by later callbacks.
9. **Exact-head app acceptance.** Required focused/source tests plus Xcode 27 Capture/app/runtime acceptance pass on the exact final head. Queued, skipped, cancelled, red, ancestor, child-only, or package-only results are not acceptance.
10. **Intended-device install acceptance.** The exact signed build/install is bound to the intended iPhone 12 / iOS 27 and intended private Tuya dependency/workspace provenance.
11. **Final GO record.** One explicit durable record names the exact source SHA, build identity, signed artifact/install identity, procedure version, expected artifact, and stop conditions.

Until every applicable blocker is closed on one final composed exact build, status remains **NO-GO / DO NOT SCAN / DO NOT RUN**.

## Authenticated stationary experiment once GO exists

After the final GO record exists and the fresh target has been explicitly confirmed:

1. Keep the scooter stationary and keep the app foregrounded.
2. Establish the accepted official SmartLife authenticated session for the already-bound scooter without unbinding, reset, or speculative control activity.
3. Observe only through the accepted read-only/session evidence path.
4. Do not send DP queries or controls merely to solicit a response.
5. Preserve every admitted application evidence item with current generation, source identity, receipt order, monotonic timing, and build/procedure provenance.
6. Continue observation until the canonical verdict is earned: at least 2 genuine non-empty application updates, latest update >=30 seconds after authentication, and accepted authenticated continuity >=45 seconds.
7. If the verdict is not earned, stop according to the fail-closed rules; do not reinterpret the run as PASS.
8. Seal through the canonical evidence path and use the app's normal Share/export flow.

## Physical PASS conditions

The authenticated stationary experiment may be classified `PASS` only if the sealed accepted artifact proves all of the following for the same current authenticated generation:

- fresh target correlation completed and the operator explicitly confirmed the single accepted candidate;
- the four-window target-correlation provenance and confirmation fact are preserved;
- accepted official SmartLife authentication provenance exists for the intended already-bound account/device;
- at least **2** genuine, non-empty authenticated application updates were admitted from that same generation;
- the **latest** accepted application update arrived at least **30 seconds after authentication**;
- authenticated continuity remained accepted for at least **45 seconds after authentication**;
- the evidence remained observational/read-only under the accepted gate policy;
- accepted application/raw evidence and chronology/provenance were sealed/exported without secrets;
- structured evidence was not mislabeled as byte-exact raw FD50 evidence;
- no opaque payload was promoted directly into telemetry semantics;
- no stale generation, replayed callback, display interpolation, GPS/scenario timing, or caller-constructed authority was promoted into physical protocol truth.

A transport callback, write completion, notification-subscription success, timer UI, one application callback, two early callbacks, 45 seconds of generic BLE liveness, or simulator-shaped payload evidence is **not** a physical PASS.

## Stop / fail-closed conditions

Stop the attempt and preserve only legitimately admitted evidence if any of these occurs:

- target correlation is none or ambiguous;
- the operator did not explicitly confirm the fresh target;
- correlation provenance cannot be preserved;
- the app backgrounds or required lifecycle integrity is lost;
- exact build/source/account/device authority changes or becomes uncertain;
- a stale/duplicate generation cannot be safely classified;
- local-BLE acquisition fails or monotonic chronology becomes invalid and the exact generation cannot be safely retired;
- the session disconnects before the accepted continuity floor;
- fewer than 2 qualifying application updates are admitted;
- the latest qualifying application update does not survive to >=30 seconds after authentication;
- the 45-second authenticated continuity floor is not reached;
- a separately required raw-byte source is unavailable under the final accepted raw-evidence contract;
- artifact integrity/seal/export cannot be established;
- any unexpected semantic command/control path becomes enabled;
- the exact installed build cannot prove the final accepted build/procedure identity.

Do not repair a failed physical attempt by relabeling missing evidence, substituting a different build, weakening raw-vs-structured terminology, or inferring protocol semantics from timing/GPS/UI behavior.

## What PASS unlocks

A successful authenticated stationary gate unlocks only the **next smallest stationary semantic-correlation experiment**.

It does not automatically establish speed, battery, current, power, mode, light, brake, lock, odometer, or command semantics.

After analyzing the sealed application artifact, identify the exact remaining unknowns and generate the smallest safe next recipe—beginning with stationary idle/battery reference and individually controlled normal state changes—before considering moving/GPS scenarios.

## Durable handoff rule

Live GitHub wins over stale snapshots. This runbook intentionally does not pin a long list of volatile donor PR heads.

At every GO or after any meaningful merge, refresh current main, active Capture PRs/branches, exact heads, CI/Xcode state, accepted dependencies, and physical status before using this document operationally.

A green checkpoint is not automatically the endpoint. The gate closes only when the final composed exact app is accepted and the real stationary session produces the required sealed authenticated evidence.
