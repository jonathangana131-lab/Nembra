# ES80 Stationary Capture Manifest

Status: **dependent software slice; physical AOVOPRO ES80 capture still not performed/verified by this lane**.

Dependency: the active passive-capture runtime recovery that supplies `NembraBluetoothCapture` and versioned `PassiveBluetoothCaptureJSON`.

## Product gap

The passive capture artifact preserves raw Bluetooth evidence, receipt chronology, target-attributable GATT observations, stock-app correlation markers, and explicit continuity breaks. The physical runbook also requires several experiment facts that are easy to lose when a JSON file is copied away from the exact build/session that produced it:

- exact Nembra Git commit;
- exact selected CoreBluetooth peripheral identifier;
- whether the scooter was intentionally stationary;
- charger connected/disconnected state;
- the declared foreground/screen-on execution condition required by the current research path;
- how any visible stock-app reference values were obtained;
- exact raw artifact bytes used for later analysis.

Those facts should not be shoved into the raw evidence stream after capture, and a free-form filename is not a durable evidence contract.

## Slice

`PassiveBluetoothStationaryCaptureManifest` is a separate versioned sidecar for the **first/smallest stationary physical experiment**. It does not alter `PassiveBluetoothCaptureSession` or its JSON bytes.

The wire format serializes `experimentKind: stationaryBaseline` so a copied sidecar remains self-describing outside the Swift type system. This identifies the intended experiment procedure; it is **not** telemetry evidence proving the scooter was physically stationary. Physical execution still has to establish that condition.

The builder requires:

- a decodable versioned passive capture artifact;
- a full 40- or 64-hex Git commit SHA (stored lowercase);
- a valid CoreBluetooth UUID for the explicitly selected peripheral;
- an explicit charger state (`connected` or `disconnected`);
- an operator-declared execution context. Schema v1 intentionally has only `foregroundScreenOn`, matching the current foreground-only research procedure;
- a structured stock-app reference setup:
  - none;
  - same device before capture;
  - same device after capture;
  - same device before and after capture;
  - separate observer device.

`foregroundScreenOn` is operator-declared provenance, not an iOS attestation that the app stayed continuously active. If the phone locks/backgrounds during the real experiment, that physical attempt must be treated according to the runbook rather than assuming missing callbacks are protocol silence. A future background-capable case belongs here only after Nembra legitimately implements and validates that lifecycle.

There is deliberately no “simultaneous same-phone stock-app observation” state. Nembra must not imply it sniffed or co-observed another app's private CoreBluetooth exchange.

## Exact artifact binding

The sidecar stores:

- the serialized stationary-baseline experiment kind;
- the declared charger / execution / stock-app-reference setup;
- SHA-256 of the **exact capture JSON bytes**;
- exact byte count;
- capture session UUID decoded from those bytes;
- canonical selected CoreBluetooth UUID;
- derived counts for selected-target GATT records, selected-target raw value records, stock-app markers, and known continuity breaks.

SHA-256 is only artifact-integrity/provenance evidence. It does not authenticate the physical scooter, prove that a peripheral UUID is a permanent scooter identity, verify who recorded the capture, or prove any Tuya/telemetry meaning.

`PassiveBluetoothStationaryCaptureManifestJSON.verify(manifestJSON:captureJSON:)` never accepts an imported sidecar by itself. It rebuilds the sidecar from the supplied raw capture and requires exact equality. Even semantically identical JSON with different bytes is a different source artifact and fails the old sidecar's verification. Tampering with derived summary fields also fails verification even if digest/session/setup fields are left unchanged.

## Stock-app provenance consistency

`stockAppReferenceSetup` is operator-declared setup context, while `stockAppMarkerCount` is derived from immutable raw capture events. They are not allowed to make a direct factual contradiction.

If the declared reference setup is `none`, the raw artifact must contain **zero** stock-app markers. A marker-bearing artifact paired with `.none` fails manifest construction and therefore also fails imported-manifest verification.

For the non-`none` cases, marker presence alone does **not** prove when another app refreshed, simultaneous Bluetooth observation, or the truth of a same-device/separate-device claim. Those enum values remain declared experiment setup. Raw marker receipt clocks retain only their existing correlation semantics.

## Target-attribution gate

Broad advertisements and connection-only callbacks are intentionally insufficient to bind this physical sidecar to a selected target.

The capture must contain GATT-attributable evidence for exactly one canonical CoreBluetooth peripheral UUID, drawn from service, included-service, characteristic, descriptor, subscription, or raw value records. The requested selected UUID must be that UUID.

The builder fails closed when:

- there is no target GATT evidence;
- the requested selected peripheral is absent from GATT evidence;
- more than one GATT peripheral appears in the artifact;
- a captured target-attributable peripheral identifier is not a valid CoreBluetooth UUID.

Connection-only noise is deliberately weaker. A connection/disconnection callback never establishes target identity. An unrelated or legacy/non-UUID connection-only record does not invalidate an otherwise clean selected-target GATT artifact, and only a canonical connection identifier equal to the selected target can add a disconnect continuity break.

This keeps a broad-scan candidate, connection-only neighbor, or mixed-target GATT artifact from silently becoming “the ES80” merely because a caller supplied a label.

## Derived summary semantics

The summary is descriptive only:

- `targetGATTRecordCount` counts selected-target service/included-service/characteristic/descriptor/subscription/value records;
- `targetValueRecordCount` counts selected-target raw value records;
- `stockAppMarkerCount` counts human-observed correlation markers already present in the raw artifact;
- `continuityBreakCount` counts generic interruption markers plus disconnects belonging to the selected target.

None of these counts decodes a DP, proves field semantics, repairs a gap, or promotes a displayed stock-app value into raw protocol truth.

## First physical experiment handoff

Once the parent passive-capture app/runtime is accepted on the exact product head, the minimal experiment can become:

1. build/run the accepted Nembra ES80 research configuration on the iPhone 12;
2. keep the scooter stationary and record charger state explicitly;
3. keep the phone unlocked, screen on, and Nembra foreground for the finite capture window; record `foregroundScreenOn` as declared execution context;
4. scan, physically correlate, and explicitly select the intended peripheral;
5. acquire a healthy finite GATT/passive session;
6. record a short stationary baseline and any legitimate stock-app reference markers supported by the actual setup;
7. finish/export the immutable capture JSON;
8. create the stationary sidecar with the exact Git commit SHA, selected peripheral UUID, charger state, execution context, and reference-observation setup;
9. keep the raw JSON + sidecar together and verify the pair before offline correlation/decoder work.

No manual hex interpretation is required from the rider. The sidecar exists so Nembra tooling can retain experiment provenance mechanically.

## Explicit non-claims

This lane does **not** verify or enable:

- that a physical session actually remained stationary merely because its sidecar declares `stationaryBaseline`;
- that iOS cryptographically proved continuous foreground/screen-on execution merely because the operator declared `foregroundScreenOn`;
- physical AOVOPRO ES80 identity;
- stable per-scooter identity across relaunch/reboot/rebind;
- Tuya framing, encryption, DP IDs/types/scales/signedness;
- battery %, voltage, current, watts, speed, throttle, regen, or cadence semantics;
- scooter commands or acknowledgement;
- any characteristic write path.

Software-side artifact provenance remains separate from physical hardware verification.
