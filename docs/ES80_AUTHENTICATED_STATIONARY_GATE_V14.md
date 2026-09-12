# ES80 Authenticated Stationary Gate — V14

Status: **PHYSICAL GO OPEN — authenticated Tuya transport survival is not C7D09A22 physical acceptance.**

Protocol: V14  
Feature: Nembra Capture / ES80 physical truth  
Canonical field procedure: `docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md`  
Physical predecessor: `docs/ES80_PHYSICAL_TRUTH_C7D09A22.md`  
Baseline device: intended iPhone 12 / iOS 27  
Physical motion requirement: stationary for the entire experiment

## Purpose

This document is the durable truth contract for the physical rung after capture `C7D09A22-96DA-4E46-9BEF-E36F670ADB0E`.

C7D09A22 selected peripheral `6815A5F5-4D1E-E004-BAE8-6DF924123907`, advertised as Tuya FD50 / local name `demo`, completed all 17 scenarios, captured zero application characteristic payloads, and observed repeated peripheral-initiated disconnects at about 30 seconds. The capture does not prove the cause of the disconnect cadence. The historical peripheral UUID is capture-local evidence only and is not durable scooter identity.

The next accepted physical result must prove both:

1. a legitimate current Tuya-authenticated, read-only session for the user's already-bound scooter survives beyond the historical rejection window; and
2. genuine non-empty raw FD50 device-to-app characteristic notification payloads are retained from that authenticated session.

Authenticated Smart Life SDK application/transparent callbacks are useful observation evidence, but they cannot substitute for raw FD50 characteristic-notification custody and cannot by themselves close physical GO.

No DP ID, field meaning, scale, signedness, cadence, command acknowledgement, battery, voltage, current, power, speed, mode, light, lock, brake, cruise, trip, or odometer semantic is physically established yet.

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

## Evidence-source contract

### Authenticated Tuya observation evidence

The production preflight may use documented Smart Life / Tuya SDK mechanisms with the user's own linked Tuya account and exact linked-device identity to establish authentication and connection continuity. Structured SDK callbacks and transparent/passthrough receive callbacks may be retained as **authenticated Tuya application evidence**.

That evidence may prove that the documented authenticated Tuya transport is alive and has survived beyond the historical rejection horizon. It does **not** establish raw FD50/ATT notification bytes, raw characteristic provenance, DP semantics, or command acknowledgement.

### Physical-first raw evidence

C7D09A22 physical acceptance requires retained non-empty payload bytes from the FD50 device-to-app notify characteristic `00000002-0000-1001-8001-00805F9B07D0`, with custody that is truthfully tied to the same authenticated connection generation.

The app must not manufacture that join from matching timestamps, matching names, RSSI, the historical CoreBluetooth UUID, SDK transparent bytes, or two independent BLE connections. If the official SDK owns the authenticated connection and does not expose a documented same-session raw characteristic callback, physical GO stays open rather than opening a competing CoreBluetooth owner or relabeling application-layer bytes as raw notifications.

The raw-notify acceptance prefix must retain at least **two** non-empty raw notify payloads, and at least one retained raw notification must arrive beyond the historical approximately-30-second rejection boundary while the authenticated generation remains valid.

## Safe preflight invariants

The preflight is read-only and fail-closed:

1. Use the official documented Tuya/Smart Life authentication mechanism or credentials/identity derived from the user's own linked Tuya account.
2. Do not guess authentication packets or arbitrary characteristic writes.
3. Do not issue semantic DP queries merely to provoke traffic.
4. Do not unbind, reset, remove, pair-over, OTA-update, or otherwise mutate scooter ownership/state.
5. Maintain one BLE owner for the authenticated session unless an officially documented same-session observation mechanism proves otherwise.
6. Reject stale generations, account/device identity drift, chronology regression, continuity loss, and delayed callbacks from retired sessions.
7. Keep SDK/application evidence and raw-characteristic evidence in separate evidence classes until an explicit same-session custody bridge proves their relationship.
8. Never mint speed/battery/mode/light/brake/power or other DP meaning from opaque bytes, timing, UI state, scenario timing, GPS, or prior assumptions.

## Physical PASS conditions

Physical GO may be classified `PASS` only when one current authenticated generation proves all of the following:

- accepted Smart Life / Tuya authentication provenance exists for the intended already-bound device under the user's linked account;
- authentication/session continuity survives beyond the previous approximately-30-second rejection window;
- the same authenticated generation has truthful raw-characteristic custody for the FD50 device-to-app notify characteristic;
- at least **two** genuine non-empty raw FD50 notify payloads are retained;
- at least one retained raw FD50 notify payload arrives after the historical rejection boundary;
- payload count and retained-byte accounting agree with the sealed raw evidence;
- the accepted evidence prefix is sealed before product success is presented;
- exported evidence contains no credentials or secrets;
- no raw payload is promoted into telemetry or control semantics;
- no independent competing post-auth CoreBluetooth session is treated as same-session evidence;
- Nembra performs no semantic control write, arbitrary GATT write, reset, removal, unbind, or OTA action.

Authenticated SDK transport survival, SDK transparent receive bytes, a subscription event without payload bytes, a UI timer, one raw packet, two early raw packets followed only by generic liveness, or an unauthenticated raw capture is **not** a PASS.

## Stop / fail-closed conditions

Stop the attempt and preserve only legitimately admitted evidence if any of these occurs:

- linked-account or exact-device authority is missing, stale, revoked, or changes;
- the authenticated generation is lost or cannot be unambiguously identified;
- target identity/correlation becomes ambiguous;
- foreground/lifecycle integrity required by the capture is lost;
- a stale/duplicate generation cannot be safely classified;
- the session drops before the rejection boundary without accepted raw notify evidence;
- raw notification provenance cannot be tied to the authenticated session without inference;
- a second BLE owner would be required merely to manufacture raw custody;
- artifact integrity/seal/export cannot be established;
- any secret appears in UI/log/export;
- any guessed authentication write, semantic DP query/control write, reset, removal, unbind, or OTA action is observed.

Do not repair a failed attempt by weakening the raw-notify requirement, joining independent connections by timing, relabeling SDK passthrough bytes as characteristic bytes, guessing a target, or inferring protocol semantics from opaque data.

## What authenticated Tuya survival unlocks

A documented authenticated Tuya session surviving beyond the historical rejection window is a valuable milestone: it proves the old unauthenticated ~30-second rejection behavior has been crossed under the supported authentication path. It does **not** close C7D09A22 physical acceptance by itself.

## What physical PASS unlocks

Physical PASS unlocks only the next smallest stationary correlation experiment over the opaque raw evidence actually observed. It does not automatically establish speed, battery, current, power, mode, light, brake, lock, odometer, command acknowledgement, or safe write authority.

Semantic assignment remains blocked until controlled authenticated physical evidence supports a specific mapping.

## Durable handoff rule

This contract supersedes older wording that allowed `rawFD50BytesCaptured=false` to close the physical gate. Structured SDK evidence remains useful, but physical GO now requires authenticated raw FD50 notify custody as defined above.

Do not spend capacity reviving stale #833 physical NO-GO ceremony. The real C7D09A22 field artifact is the physical predecessor and the current product source must remain aligned with this contract.
