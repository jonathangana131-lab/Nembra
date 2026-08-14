# ES80 Authenticated Stationary Gate — V14 historical rationale

Status: **SUPERSEDED / NON-AUTHORITATIVE FOR EXECUTION / PHYSICAL NO-GO.**

Protocol history: V14  
Feature: Nembra Capture / ES80 physical truth  
Physical predecessor: `docs/ES80_PHYSICAL_TRUTH_C7D09A22.md`  
Current procedure authority: `docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md`  
Current procedure ID: `ES80-AUTHENTICATED-STATIONARY-v1`

## Purpose of this historical record

This file preserves the design rationale that followed accepted physical capture `C7D09A22-96DA-4E46-9BEF-E36F670ADB0E`. It is **not** a current runbook, PASS contract, GO record, software-head snapshot, or field instruction.

C7D09A22 physically verified the modern Tuya FD50 transport family but received zero application characteristic payloads and repeatedly disconnected at about 29.930 seconds. That evidence justified moving away from another outdoor 17-step ride replay toward the smallest stationary authenticated read-only experiment.

The historical CoreBluetooth peripheral UUID `6815A5F5-4D1E-E004-BAE8-6DF924123907` remains descriptive capture-local evidence only. It cannot establish durable scooter identity, break a target-correlation tie, or authorize a later run.

## Durable truth constraints retained from V14

These constraints remain useful design history and are preserved by the current procedure:

- perform fresh deterministic `OFF1 → ON1 → OFF2 → ON2` target correlation rather than trusting the historical UUID, name, RSSI, FD50 presence, Tuya hints, or service-name similarity;
- require explicit operator confirmation of the freshly correlated current-attempt target;
- preserve correlation provenance instead of collapsing the result to a detached UUID;
- use supported SmartLife SDK authentication/session authority for the already-bound scooter and keep package CoreBluetooth correlation retired before Tuya becomes the sole authenticated BLE owner;
- never relabel structured SDK `dpsUpdate` values as byte-exact FD50/ATT notification bytes;
- never let opaque payloads mint speed, battery, voltage, current, power, mode, odometer, command acknowledgement, or other telemetry semantics without separate repeatable physical decoding evidence;
- do not add DP queries, unknown characteristic writes, scooter controls, unbind/reset/OTA, or a competing post-auth CoreBluetooth owner merely to provoke traffic;
- keep accepted chronology/provenance immutable through seal/export and prevent stale generations or delayed callbacks from mutating the accepted prefix;
- require exact build/source/private-dependency/install authority and final exact-head software acceptance before physical execution.

## Superseded execution semantics

Earlier revisions of this V14 gate contained active-sounding instructions and a PASS shape based on **one** application notification plus optional byte-exact raw-FD50 evidence. Those instructions are deliberately retired.

They cannot authorize the current experiment because the accepted product contract is now stricter and materially different. The current `ES80-AUTHENTICATED-STATIONARY-v1` procedure requires, among other things:

- at least **two** accepted same-generation application observations;
- latest accepted application payload at least **30 seconds after authentication**;
- at least **45 seconds** of accepted authenticated continuity;
- fail-closed incomplete-observation retirement at **60 seconds** if readiness was not earned;
- exact selected-device callback source attribution before application evidence can count;
- package-visible, non-caller-mintable, one-shot/order-preserving delivery chronology so async scheduling cannot manufacture or reorder physical evidence;
- honest terminal/lifecycle presentation with no false tokenless observing state;
- signed iPhone 12 / iOS 27 field-build custody, intended-device admission, current visual/runtime acceptance, trusted signing/bootstrap, and an explicit final repository GO record.

The current supported SDK path may legitimately retain structured application observations while `rawFD50BytesCaptured=false`. That is not a weakening or a claim of raw bytes; it is a different explicitly labeled evidence gate. Structured application evidence still cannot mint telemetry semantics.

## Single-authority rule

Only `docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md` may define the current next physical procedure. This file must remain superseded and may not independently flip to GO/PASS or supply an alternate one-payload/raw-byte recipe.

If the current procedure changes, update the single current authority and its mechanical consistency tests. Preserve this file only as historical rationale.

**PHYSICAL NO-GO. DO NOT SCAN, INSTALL, RUN BLUETOOTH, OR RIDE BASED ON THIS FILE.**
