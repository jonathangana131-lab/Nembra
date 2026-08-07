# ES80 Stationary Capture Manifest

Status: **dependent software slice; physical AOVOPRO ES80 capture still not performed/verified by this lane**.

Dependency: the active passive-capture runtime recovery that supplies `NembraBluetoothCapture` and versioned `PassiveBluetoothCaptureJSON`.

## Product gap

The passive capture artifact preserves raw Bluetooth evidence, receipt chronology, target-attributable GATT observations, stock-app correlation markers, and explicit continuity breaks. The physical runbook also requires several experiment facts that are easy to lose when a JSON file is copied away from the exact build/session that produced it:

- exact Nembra Git commit;
- exact selected CoreBluetooth peripheral identifier;
- whether the scooter was intentionally stationary;
- charger connected/disconnected state;
- how any visible stock-app reference values were obtained;
- exact raw artifact bytes used for later analysis.

Those facts should not be shoved into the raw evidence stream after capture, and a free-form filename is not a durable evidence contract.

## Slice

`PassiveBluetoothStationaryCaptureManifest` is a separate versioned sidecar for the **first/smallest stationary physical experiment**. It does not alter `PassiveBluetoothCaptureSession` or its JSON bytes.

The builder requires:

- a decodable versioned passive capture artifact;
- a full 40- or 64-hex Git commit SHA (stored lowercase);
- a valid CoreBluetooth UUID for the explicitly selected peripheral;
- an explicit charger state (`connected` or `disconnected`);
- a structured stock-app reference setup:
  - none;
  - same device before capture;
  - same device after capture;
  - same device before and after capture;
  - separate observer device.

There is deliberately no “simultaneous same-phone stock-app observation” state. Nembra must not imply it sniffed or co-observed another app's private CoreBluetooth exchange.

## Exact artifact binding

The sidecar stores:

- SHA-256 of the **exact capture JSON bytes**;
- exact byte count;
- capture session UUID decoded from those bytes;
- canonical selected CoreBluetooth UUID;
- derived counts for selected-target GATT records, selected-target raw value records, stock-app markers, and known continuity breaks.

SHA-256 is only artifact-integrity/provenance evidence. It does not authenticate the physical scooter, prove that a peripheral UUID is a permanent scooter identity, verify who recorded the capture, or prove any Tuya/telemetry meaning.

`PassiveBluetoothStationaryCaptureManifestJSON.verify(manifestJSON:captureJSON:)` never accepts an imported sidecar by itself. It rebuilds the sidecar from the supplied raw capture and requires exact equality. Even semantically identical JSON with different bytes is a different source artifact and fails the old sidecar's verification.

## Target-attribution gate

Broad advertisements and connection-only callbacks are intentionally insufficient to bind this physical sidecar to a selected target.

The capture must contain GATT-attributable evidence for exactly one canonical CoreBluetooth peripheral UUID, drawn from service, included-service, characteristic, descriptor, subscription, or raw value records. The requested selected UUID must be that UUID.

The builder fails closed when:

- there is no target GATT evidence;
- the requested selected peripheral is absent from GATT evidence;
- more than one GATT peripheral appears in the artifact;
- a captured target-attributable peripheral identifier is not a valid CoreBluetooth UUID.

This keeps a broad-scan candidate or mixed-target artifact from silently becoming “the ES80” merely because a caller supplied a label.

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
3. scan, physically correlate, and explicitly select the intended peripheral;
4. acquire a healthy finite GATT/passive session;
5. record a short stationary baseline and any legitimate stock-app reference markers supported by the actual setup;
6. finish/export the immutable capture JSON;
7. create the stationary sidecar with the exact Git commit SHA, selected peripheral UUID, charger state, and reference-observation setup;
8. keep the raw JSON + sidecar together and verify the pair before offline correlation/decoder work.

No manual hex interpretation is required from the rider. The sidecar exists so Nembra tooling can retain experiment provenance mechanically.

## Explicit non-claims

This lane does **not** verify or enable:

- physical AOVOPRO ES80 identity;
- stable per-scooter identity across relaunch/reboot/rebind;
- Tuya framing, encryption, DP IDs/types/scales/signedness;
- battery %, voltage, current, watts, speed, throttle, regen, or cadence semantics;
- scooter commands or acknowledgement;
- any characteristic write path.

Software-side artifact provenance remains separate from physical hardware verification.
