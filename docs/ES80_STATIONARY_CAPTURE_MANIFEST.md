# ES80 Stationary Capture Manifest

Status: **dependent software slice; physical AOVOPRO ES80 capture still not performed/verified by this lane**.

Dependency: the corrected current passive-capture runtime lineage that supplies `NembraBluetoothCapture` and versioned `PassiveBluetoothCaptureJSON`. This recovery is re-anchored onto that runtime; experiment one still remains blocked on the active target-correlation, observation-horizon, product-shell, and mechanical provenance-consumer integration gates.

## Product gap

The passive capture artifact preserves raw Bluetooth evidence, receipt chronology, target-attributable GATT observations, stock-app correlation markers, and explicit continuity breaks. The physical runbook also requires several experiment facts that are easy to lose when a JSON file is copied away from the build/session that produced it:

- declared exact Nembra Git commit;
- exact selected CoreBluetooth peripheral identifier;
- whether the scooter was intentionally stationary;
- declared charger connected/disconnected state;
- the declared foreground/unlocked/screen-on execution condition required by the current research path;
- how any visible stock-app reference values were obtained;
- exact raw artifact bytes used for later analysis.

Those facts should not be shoved into the raw evidence stream after capture, and a free-form filename is not a durable evidence contract. The sidecar preserves them structurally, while keeping operator declarations distinct from facts that can actually be recomputed from the immutable capture.

## Slice

`PassiveBluetoothStationaryCaptureManifest` is a separate versioned sidecar for the **first/smallest stationary physical experiment**. It does not alter `PassiveBluetoothCaptureSession` or its JSON bytes.

The wire format serializes `experimentKind: stationaryBaseline` so a copied sidecar remains self-describing outside the Swift type system. This identifies the intended experiment procedure; it is **not** telemetry evidence proving the scooter was physically stationary. Physical execution still has to establish that condition.

The builder requires:

- a decodable versioned passive capture artifact;
- a full 40- or 64-hex declared Git commit SHA (stored lowercase);
- a valid CoreBluetooth UUID for the explicitly selected peripheral;
- an explicitly declared charger state (`connected` or `disconnected`);
- an operator-declared execution context. Schema v1 intentionally has only `foregroundUnlockedScreenOn`, matching the current foreground-only research procedure;
- a structured stock-app reference setup:
  - none;
  - same device before capture;
  - same device after capture;
  - same device before and after capture;
  - separate observer device.

`foregroundUnlockedScreenOn` is operator-declared provenance, not an iOS attestation that the app stayed continuously active. If the phone locks/backgrounds or Nembra leaves the foreground during the real experiment, that physical attempt must be treated according to the runbook rather than assuming missing callbacks are protocol silence. A future background-capable case belongs here only after Nembra legitimately implements and validates that lifecycle.

There is deliberately no “simultaneous same-phone stock-app observation” state. Nembra must not imply it sniffed or co-observed another app's private CoreBluetooth exchange.

## Capture binding vs declared setup

The sidecar deliberately separates **capture-derived facts** from **operator-declared experiment context**.

Capture-derived fields that `verifyCaptureBinding(manifestJSON:captureJSON:)` recomputes from the supplied immutable capture include:

- SHA-256 of the **exact capture JSON bytes**;
- exact byte count;
- capture session UUID decoded from those bytes;
- canonical selected CoreBluetooth UUID subject to the GATT-attribution gate;
- selected-target GATT/value counts;
- stock-app marker count;
- known continuity-break count.

Changing the raw capture bytes changes the binding. Tampering with a serialized derived summary or selected-target claim is rejected because verification rebuilds those facts from the supplied capture and requires the rebuilt manifest to match.

The following are operator-declared sidecar fields rather than capture-authenticated facts:

- experiment ID;
- preparation time;
- Nembra Git commit SHA;
- charger state;
- foreground/unlocked/screen-on declaration;
- non-`none` stock-app reference setup.

`verifyCaptureBinding(...)` schema-checks those declarations and applies direct consistency gates where the raw capture can contradict them, but it **does not cryptographically authenticate who supplied them or prove they were true in the physical world**. An external trusted build record, signature, attestation, or other trust anchor would be required for that stronger property. Schema v1 does not claim one.

The Git SHA format check therefore proves only that the declared value has a full supported hexadecimal commit shape. Product wiring should eventually supply that revision from trusted build metadata rather than asking an operator to transcribe it manually, but this standalone sidecar API does not independently attest the running binary's revision.

## Exact artifact binding

SHA-256 is artifact-integrity/binding evidence for the provided bytes. It does not authenticate the physical scooter, prove that a peripheral UUID is a permanent scooter identity, verify who recorded the capture, authenticate the declared build/setup context, or prove any Tuya/telemetry meaning.

`PassiveBluetoothStationaryCaptureManifestJSON.verifyCaptureBinding(manifestJSON:captureJSON:)` never trusts serialized capture-derived fields by themselves. It rebuilds those fields from the supplied raw capture and requires exact manifest equality after applying the declared setup's supported consistency gates. Even semantically identical capture JSON with different bytes is a different source artifact and fails an old sidecar's capture binding.

The schema-v1 execution context is required rather than defaulted. An imported sidecar missing `setup.executionContext` fails JSON decoding instead of silently assuming the physical procedure was followed.

Schema v1 is also closed-world during verification: unrecognized keys at the top level or inside `setup`, `sourceArtifact`, or `evidenceSummary` are rejected rather than silently ignored by `JSONDecoder`. An unsupported field such as `physicallyVerified` therefore cannot travel beside an otherwise valid sidecar and appear to gain legitimacy from a successful capture-binding check. New semantics require a deliberate schema/version change.

## Stock-app provenance consistency

`stockAppReferenceSetup` is operator-declared setup context, while `stockAppMarkerCount` is derived from immutable raw capture events. They are not allowed to make a direct factual contradiction.

If the declared reference setup is `none`, the raw artifact must contain **zero** stock-app markers. A marker-bearing artifact paired with `.none` fails manifest construction and therefore also fails capture-binding verification.

For the non-`none` cases, marker presence alone does **not** prove when another app refreshed, simultaneous Bluetooth observation, or the truth of a same-device/separate-device declaration. Those enum values remain declared experiment setup. Raw marker receipt clocks retain only their existing correlation semantics.

## Target-attribution gate

Broad advertisements and connection-only callbacks are intentionally insufficient to bind this physical sidecar to a selected target.

The capture must contain GATT-attributable evidence for exactly one canonical CoreBluetooth peripheral UUID, drawn from service, included-service, characteristic, descriptor, subscription, or raw value records. The requested selected UUID must be that UUID.

The builder fails closed when:

- there is no target GATT evidence;
- the requested selected peripheral is absent from GATT evidence;
- more than one GATT peripheral appears in the artifact;
- a captured target-attributable GATT peripheral identifier is not a valid CoreBluetooth UUID.

Connection-only records remain deliberately weaker for **identity**. A connection/disconnection callback never establishes the selected target, and an unrelated or legacy/non-UUID connection-only record does not invalidate an otherwise clean selected-target GATT artifact merely by existing.

Continuity semantics are stricter than identity semantics. `NembraCore` defines every structured `.disconnected` capture event as `breaksByteContinuity == true`, independent of whether this sidecar can attribute that record to the selected UUID. The sidecar therefore preserves **every captured disconnect** in `continuityBreakCount` rather than under-reporting a known gap. This can conservatively retain an unattributed break; it can never turn a disconnect into evidence of target identity.

Implementation consumes `PassiveBluetoothCaptureEvent.breaksByteContinuity` directly for every record rather than re-listing the current continuity-breaking cases inside the manifest. The sidecar therefore follows the core capture domain if that vocabulary evolves, while target-attribution handling remains separately fail-closed.

This keeps a broad-scan candidate, connection-only neighbor, or mixed-target GATT artifact from silently becoming “the ES80,” while also preventing identity uncertainty from erasing continuity evidence.

The selected UUID still does not explain **why the operator associated that UUID with the physical scooter**. The product-facing deterministic physical-candidate correlation flow is owned by the research-shell/runbook lanes. Once that executable flow is accepted, this incumbent sidecar should preserve only the actual accepted correlation method/result, without promoting it into permanent or cryptographic scooter identity.

## Derived summary semantics

The summary is descriptive only:

- `targetGATTRecordCount` counts selected-target service/included-service/characteristic/descriptor/subscription/value records;
- `targetValueRecordCount` counts selected-target raw value records;
- `stockAppMarkerCount` counts human-observed correlation markers already present in the raw artifact;
- `continuityBreakCount` counts **every structured disconnect plus every generic interruption marker**, matching the core capture domain's byte-continuity semantics even when a disconnect record cannot establish target identity.

None of these counts decodes a DP, proves field semantics, repairs a gap, or promotes a displayed stock-app value into raw protocol truth.

## First physical experiment handoff

Experiment one remains blocked until the passive foundation, product-facing shell, deterministic physical-candidate correlation path, sidecar, and runbook are reconciled onto accepted exact heads.

Once those dependencies are genuinely accepted, the minimal experiment can become:

1. build/run the accepted Nembra ES80 research configuration on the iPhone 12;
2. obtain the exact running build revision from trusted product/build plumbing where available, rather than relying on manual transcription;
3. keep the scooter stationary and declare charger state explicitly;
4. keep the phone unlocked, screen on, and Nembra foreground for the finite capture window; record `foregroundUnlockedScreenOn` as declared execution context;
5. use the accepted deterministic physical-candidate correlation flow and explicitly select the intended full CoreBluetooth UUID; do not guess by local name, truncated UUID, or strongest RSSI;
6. acquire a healthy finite GATT/passive session;
7. record the bounded stationary evidence window and only the stock-app reference markers allowed by that experiment's accepted setup;
8. finish/export the immutable capture JSON;
9. create the stationary sidecar with the declared build revision, selected peripheral UUID, charger state, execution context, reference-observation setup, and—once the product flow is settled—the accepted target-correlation provenance;
10. keep the raw JSON + sidecar together and run `verifyCaptureBinding(...)` before offline correlation/decoder work.

No manual hex interpretation is required from the rider. The sidecar exists so Nembra tooling can retain experiment context mechanically while preserving the distinction between recomputable capture evidence and operator declarations.

## Explicit non-claims

This lane does **not** verify or enable:

- that a physical session actually remained stationary merely because its sidecar declares `stationaryBaseline`;
- that iOS cryptographically proved continuous foreground/unlocked/screen-on execution merely because the operator declared `foregroundUnlockedScreenOn`;
- that the declared Git revision, charger state, stock-app observation arrangement, experiment ID, or preparation time is authentic merely because capture binding verifies;
- physical AOVOPRO ES80 identity;
- permanent/cryptographic association of the selected CoreBluetooth UUID with the scooter;
- stable per-scooter identity across relaunch/reboot/rebind;
- Tuya framing, encryption, DP IDs/types/scales/signedness;
- battery %, voltage, current, watts, speed, throttle, regen, or cadence semantics;
- scooter commands or acknowledgement;
- any characteristic write path.

Software-side capture binding and declared experiment context remain separate from physical hardware verification.