# ES80 Authenticated Acceptance Contract — V14

Status: **CANONICAL SOFTWARE ACCEPTANCE FLOOR / PHYSICAL SESSION STILL NO-GO UNTIL FINAL EXACT-BUILD AUTHORIZATION.**

Feature: Nembra Capture / ES80 physical truth
Protocol: V14
Physical predecessor: `C7D09A22-96DA-4E46-9BEF-E36F670ADB0E`

## Purpose

This record makes the authenticated stationary acceptance boundary unambiguous across code, tests, field-truth documentation, and app acceptance.

The old approximately-29.93-second unauthenticated disconnect pattern is not closed by generic Bluetooth liveness alone. The final physical artifact must prove that the authenticated **application path itself** survived beyond that region.

## Canonical acceptance floor

The current authenticated generation may become ready for stationary mapping only when all of these conditions are true in the same generation:

1. Authentication provenance is the official SmartLife App SDK for the current BLE generation.
2. At least **2** genuine, non-empty authenticated application updates have been admitted from that generation.
3. The **latest** accepted application update arrived at least **30 seconds after authentication**.
4. The authenticated generation remained continuously accepted for at least **45 seconds after authentication**.
5. Chronology remains valid and belongs to the same current generation.

A single bootstrap callback is insufficient. Two early callbacks followed only by generic BLE liveness are insufficient. A connection lasting merely more than 30 seconds is insufficient. A 45-second connection without the repeated late application evidence is insufficient.

## Mechanical authority

The mechanical gate lives in:

`Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlyPreflight.swift`

Its canonical constants are:

- `minimumAuthenticatedApplicationPayloadCount = 2`
- `minimumPostAuthenticationPayloadSurvivalNanoseconds = 30_000_000_000`
- `minimumAuthenticatedConnectionNanoseconds = 45_000_000_000`

The field app must consume `TuyaAuthenticatedReadOnlyPreflight.verdict(for:)` at the acceptance boundary. Documentation must never weaken these mechanical requirements.

## Documentation precedence

`docs/ES80_PHYSICAL_TRUTH_C7D09A22.md` is the physical predecessor ledger and is required to remain no weaker than the shipping preflight verdict.

`docs/ES80_AUTHENTICATED_STATIONARY_GATE_V14.md` remains the broad coordination/runbook authority for blockers and safe procedure. Any older sentence in that file that describes one payload or treats 45 seconds as guidance-only is superseded by this acceptance floor and by the mechanical preflight verdict until that prose is fully synchronized.

No weaker prose, old issue, historical PR body, simulator fixture, or previous runbook may authorize the physical session.

## Truth boundary

Passing this gate proves only authenticated application-path continuity and genuine application evidence for the accepted physical generation. It does **not** establish any ES80 DP meaning, speed, battery, voltage, current, power, mode, light, brake, lock, odometer, command acknowledgement, or other telemetry/control semantics.

Opaque payloads remain opaque until a separately accepted repeatable physical decoding/correlation contract exists.

## Physical status

This contract does not itself flip the experiment to GO. The final composed exact app build still needs all required source/build/private-device/runtime gates and one explicit final GO record before the user performs the stationary physical session.
