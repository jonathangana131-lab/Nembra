# ES80 Authenticated Stationary Gate — V14

Status: **NO-GO — DO NOT RUN THE NEXT PHYSICAL SESSION YET.**

Protocol: V14  
Feature: Nembra Capture / ES80 physical truth  
Canonical field procedure: `docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md`  
Physical predecessor: `docs/ES80_PHYSICAL_TRUTH_C7D09A22.md`  
Baseline device: intended iPhone 12 / iOS 27  
Physical motion requirement: stationary for the entire experiment

## Purpose

This document is the durable acceptance checkpoint for the next physical rung after capture `C7D09A22-96DA-4E46-9BEF-E36F670ADB0E`. It is intentionally a short truth contract, not a second field runbook and not a snapshot of transient PR/branch state.

C7D09A22 physically verified the modern Tuya FD50 transport, observed zero application characteristic payloads, and repeatedly disconnected at about 29.930 seconds. It did **not** establish why that disconnect cadence occurred. The next useful physical experiment is therefore the smallest stationary experiment that can prove a legitimate current Tuya authenticated application session and genuine application evidence beyond the historical rejection region.

The physical acceptance threshold is intentionally no weaker than shipping `TuyaAuthenticatedReadOnlyPreflight`: at least **two** admitted non-empty application updates in one current SmartLife-authenticated generation, the latest admitted update at least **30 seconds after authentication**, and at least **45 seconds** of accepted authenticated observation continuity. Older one-payload / merely-`>30 s` wording is superseded. One bootstrap/state replay, two early updates followed only by generic BLE liveness, or transport-only survival cannot authorize stationary mapping.

This document cannot authorize Bluetooth activity by itself. Only the final composed exact app build, with all required software/private-device gates accepted and an explicit repository `GO`, may authorize the physical session.

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

The C7D09A22 CoreBluetooth peripheral UUID `6815A5F5-4D1E-E004-BAE8-6DF924123907` is historical capture-local evidence only. It is not durable scooter identity and may not break a later correlation tie.

No DP ID, field meaning, scale, signedness, cadence, command acknowledgement, battery, voltage, current, power, speed, mode, light, lock, cruise, trip, or odometer semantic is physically established yet.

## Current evidence-source contract

For the current authenticated stationary gate, the supported application evidence source is same-generation structured SmartLife SDK delivery through `ThingSmartDeviceDelegate.dpsUpdate`, admitted by the canonical package-owned authenticated-session authority.

That structured SDK application evidence is legitimate evidence that the authenticated application path is alive when it satisfies the canonical chronology and generation rules. It does **not** establish raw FD50/ATT bytes, byte-exact notification framing, DP semantics, or command acknowledgement.

Raw byte-exact authenticated FD50 evidence remains a separate unresolved evidence rung. The current gate must not open a second competing CoreBluetooth connection merely to collect bytes while the official SmartLife SDK owns the authenticated BLE session, and it must not relabel `String(describing:)` or other structured SDK projections as raw transport bytes.

Accordingly, a valid current structured-SDK artifact may truthfully retain `rawFD50BytesCaptured=false` while still closing this authenticated-session gate if every canonical application-evidence predicate is earned. That PASS would unlock only the next smallest stationary semantic-correlation experiment; it would not claim raw FD50 evidence or any telemetry meaning.

## Software and private-device prerequisites before GO

The final composed candidate must close all applicable prerequisites on one exact source/build lineage:

1. Fresh package-owned `OFF1 → ON1 → OFF2 → ON2` correlation using full CoreBluetooth identity, accepted bounded windows, and fail-closed ambiguity handling.
2. Explicit operator confirmation of the one freshly correlated candidate. Name, RSSI, FD50, Tuya hints, or the historical UUID remain descriptive only.
3. Preserved non-secret correlation provenance sufficient to audit the four sealed windows, final disposition, and explicit confirmation.
4. `NembraCaptureBuildIdentity.isAuthoritativeFieldBuild == true` as a necessary OFF1 build-provenance prerequisite, while remaining insufficient by itself.
5. Fresh package-owned one-time signed authorization session `.armed` for the live app attempt.
6. Official SmartLife SDK login using the same account that owns the scooter, with fresh exact-device membership and current account-identity lease authority.
7. One BLE owner: package correlation is retired before the official SmartLife authenticated local-BLE session begins.
8. Canonical generation-bound lifecycle authority rejects stale/late callbacks, account/source drift, chronology regression, incomplete-observation timeout, continuity failure, and transport loss without manufacturing evidence or resurrecting retired generations.
9. Structured application updates are admitted only as structured application evidence; no raw-FD50 claim is minted from them.
10. No DP query, arbitrary command, control mutation, random characteristic write, unbind, reset, or OTA path is added to provoke traffic.
11. Accepted evidence and correlation provenance are sealed immutably and exported without credentials/secrets; delayed post-seal callbacks cannot mutate the accepted prefix.
12. Exact-head focused/package tests and exact-head Xcode 27 app/Capture acceptance are terminal green on the unchanged final candidate.
13. The privately provisioned workspace builds, signs, installs, and identifies that exact accepted source on the intended iPhone 12 / iOS 27 with the intended Tuya private workspace/security inputs.
14. A final durable `GO` record names the exact accepted source/build/procedure and stop conditions.

Queued, running, skipped, ancestor-green, package-only, Simulator-only, source-review-only, or historical evidence cannot authorize the physical session.

Until every applicable prerequisite is closed on one final composed exact build, status remains **NO-GO / DO NOT SCAN / DO NOT RUN**.

## Physical sequence once GO exists

The detailed operator sequence is owned by `docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md`; this document does not duplicate it. The invariant physical order is:

1. Keep the scooter stationary, initially OFF, charger physically disconnected, and Capture foregrounded under the accepted current-attempt declarations.
2. Earn fresh `OFF1 → ON1 → OFF2 → ON2` correlation under the package-owned bounded observation contract.
3. Continue only if exactly one repeatable full CoreBluetooth identity is accepted, then explicitly confirm that correlated target.
4. Re-prove current same-account exact-device authority.
5. Allow the official SmartLife SDK to become the sole authenticated BLE owner.
6. Observe without Nembra DP queries or control writes.
7. Preserve genuine same-generation `ThingSmartDeviceDelegate.dpsUpdate` application evidence through the canonical ledger.
8. Require at least **two** genuine non-empty same-generation application updates, with the latest at least **30 seconds after authentication**, while maintaining at least **45 seconds** of accepted authenticated observation continuity.
9. Seal the canonical ready prefix before presenting success or sharing the sanitized artifact.

## Physical PASS conditions

The current authenticated stationary gate may be classified `PASS` only if the sealed accepted artifact proves all of the following for one current authenticated generation:

- fresh four-window target correlation completed and the operator explicitly confirmed the one accepted candidate;
- accepted SmartLife SDK authentication provenance exists for the intended already-bound device/account;
- current same-account exact-device membership/identity authority remained valid;
- at least **two** genuine non-empty same-generation application updates were admitted from `ThingSmartDeviceDelegate.dpsUpdate`;
- the latest accepted application update occurred at least **30 seconds after authentication**;
- accepted authenticated observation continuity reached at least **45 seconds** after authentication;
- the canonical accepted prefix was sealed before product success;
- application evidence and chronology/provenance were exported without secrets;
- the artifact labels structured SDK evidence truthfully and does not pretend it contains raw FD50 bytes when `rawFD50BytesCaptured=false`;
- no opaque payload was promoted into telemetry semantics;
- no stale generation, replayed callback, GPS/scenario timing, UI timer, or caller-constructed state was promoted into physical protocol truth;
- Nembra sent no semantic DP query/control command or competing post-auth CoreBluetooth connection.

A transport callback, notification subscription, timer UI, one application callback/state replay, two early callbacks, a latest callback before 30 seconds, 45 seconds of transport-only liveness, or structured SDK evidence mislabeled as raw bytes is **not** a PASS.

Passing this gate proves a supported authenticated Tuya application session plus genuine repeated application evidence. It does **not** establish raw FD50/ATT bytes, permanent CoreBluetooth identity, DP meanings, speed/battery/power semantics, command acknowledgement, or safe write authority.

## Stop / fail-closed conditions

Stop the attempt and preserve only legitimately admitted evidence if any of these occurs:

- exact build/procedure or one-time signed authorization authority is missing, stale, revoked, or mismatched;
- account identity or exact-device membership authority changes;
- the current-attempt stationary/charger-disconnected/no-riding declarations become absent or false;
- target correlation is none, ambiguous, interrupted, chronology-invalid, or cannot preserve required provenance;
- the operator has not explicitly confirmed the fresh target;
- foreground/lifecycle integrity is lost;
- a stale/duplicate generation cannot be safely classified;
- local-BLE acquisition, accepted chronology, or continuity fails;
- fewer than two genuine non-empty application updates are admitted, or the latest does not survive to at least 30 seconds post-authentication;
- the authenticated continuity minimum of 45 seconds is not earned;
- artifact integrity/seal/export cannot be established;
- any secret appears in UI/log/export;
- any Nembra DP query/control write, reset/unbind/OTA action, or competing post-auth CoreBluetooth ownership path is observed.

Do not repair a failed attempt by substituting another build/account, guessing a target, weakening the 2/30/45 predicates, relabeling structured SDK evidence as raw bytes, or inferring protocol semantics from timing/GPS/UI behavior.

## What PASS unlocks

A successful authenticated stationary gate unlocks only the next smallest stationary semantic-correlation experiment using the genuine application evidence that was actually observed. It does not automatically establish speed, battery, current, power, mode, light, brake, lock, odometer, or command semantics.

Raw byte-exact authenticated FD50 evidence remains a separate unresolved rung unless a later accepted one-owner-compatible source earns it. The swarm should generalize only from evidence that the ES80 path actually produces.

## Durable handoff rule

Do not pin this document to mutable PR numbers or transient branch heads. Fresh GO workers must inspect live GitHub and the current hard-freeze/convergence state before acting. Live accepted composition wins over stale chat or historical coordination snapshots.

A green checkpoint is not automatically the endpoint. The gate closes only when the final composed app/private-device path is accepted and a real stationary session produces the required sealed authenticated evidence.
