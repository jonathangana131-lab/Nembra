# ES80 Stationary Capture Manifest

Status: **software provenance / artifact-binding slice only. Physical AOVOPRO ES80 Experiment One remains NO-GO.**

## Purpose

The raw passive capture must remain immutable evidence. Experiment/build context belongs beside it in a closed-world sidecar rather than being injected into the captured event stream or inferred from a filename.

`PassiveBluetoothStationaryCaptureManifest` binds that context to the exact capture bytes while keeping three different kinds of truth separate:

1. **capture-derived facts** that Nembra recomputes from the immutable capture;
2. **software procedure identity** that records which versioned recipe the product intended to execute;
3. **operator/build declarations** that this package can validate structurally but cannot independently attest.

The sidecar never authenticates the physical scooter, proves an RF observation was complete, decodes Tuya/GATT semantics, or turns a software procedure step into physical evidence.

## Schema v2

Schema v2 is a deliberate evolution of the accepted schema-v1 sidecar. It adds one required top-level field:

- `recipeID: "ES80-FINGERPRINT-v1"`

The existing `experimentKind: stationaryBaseline` and per-run `experimentID` are not substitutes for a stable versioned procedure identifier. The builder emits only the canonical `PassiveBluetoothExperimentRecipe.es80FingerprintV1` identity; callers cannot relabel this sidecar as another future recipe through the public builder.

Schema v1 is intentionally **not silently migrated**. It never recorded a versioned recipe, so verification rejects it with `unsupportedSchemaVersion(1)` rather than guessing that an old sidecar followed the new 14-stage V14 contract. A future migration can only be added if there is legitimate evidence for that mapping.

Schema v2 remains closed-world. Unknown keys at the top level or inside `setup`, `sourceArtifact`, or `evidenceSummary` fail verification instead of being ignored.

## Canonical recipe identity

The manifest records stable recipe ID `ES80-FINGERPRINT-v1`, whose sealed product order is owned by `PassiveBluetoothExperimentRecipe`:

1. preflight;
2. find scooter;
3. OFF1 observation;
4. ON1 observation;
5. OFF2 observation;
6. ON2 observation;
7. explicit target confirmation;
8. passive discovery;
9. observation ready;
10. capture;
11. observation Horizon + immutable seal;
12. integrity check;
13. analyze;
14. share.

Recording the recipe ID means only that this sidecar belongs to that intended software procedure. It does **not** prove any step physically happened, that the operator followed the order, that the scooter was actually off/on, that the repeated CoreBluetooth UUID is a permanent ES80 identity, or that Horizon/seal authority was legitimately earned. The accepted controller/evidence layers must mechanically earn those states before final product integration.

## Exact capture binding

The builder requires a decodable versioned passive capture plus:

- a full 40- or 64-hex declared Nembra Git commit SHA, normalized lowercase;
- a valid full CoreBluetooth UUID for the explicitly selected peripheral;
- declared charger state;
- declared `foregroundUnlockedScreenOn` execution context;
- structured stock-app reference setup.

The sidecar stores and verification recomputes:

- SHA-256 of the **exact capture JSON bytes**;
- exact byte count;
- capture session UUID;
- canonical selected full CoreBluetooth UUID subject to the GATT-attribution gate;
- selected-target GATT/value record counts;
- stock-app marker count;
- capture-wide continuity-break count using NembraCore's canonical `event.breaksByteContinuity` authority.

Even semantically equivalent JSON with different bytes is a different source artifact. Serialized derived-summary tampering fails because `verifyCaptureBinding(manifestJSON:captureJSON:)` rebuilds the manifest from the supplied immutable bytes and requires exact equality.

## Target-attribution gate

Advertisements and connection-only records cannot establish the manifest target. The capture must contain GATT-attributable evidence for exactly one canonical CoreBluetooth UUID from service, included-service, characteristic, descriptor, subscription, or value records, and the explicitly selected UUID must match it.

The builder fails closed for no target GATT evidence, selected-target absence, more than one GATT peripheral, or malformed captured target UUIDs.

Continuity is intentionally stricter than target identity. Every event that NembraCore classifies as `breaksByteContinuity` increments the sidecar's continuity count, including an unattributed/unrelated disconnect. Identity uncertainty cannot erase a known raw-byte gap.

## Stock-app provenance

`stockAppReferenceSetup` is declared setup context. Raw stock-app markers are capture events. If setup says `.none`, any raw stock-app marker is a direct contradiction and manifest construction fails.

A non-`none` declaration is still not authenticated merely because markers exist. The sidecar does not claim simultaneous same-phone Bluetooth observation or private stock-app traffic interception.

## Build identity boundary

`nembraBuildCommitSHA` remains a **declared** full Git revision. The package validates its shape but does not cryptographically prove that the running binary came from that revision.

V14 final product wiring must supply the exact build SHA mechanically from trusted build/app metadata and expose a human-readable field build identifier without asking the operator to transcribe a commit. This schema preserves the exact SHA field needed for that integration, but this package slice does not pretend caller-supplied text is attestation.

Do not call a manifest physically trusted merely because its capture binding verifies.

## Physical GO boundary

This schema closes a provenance gap; it does not authorize Experiment One.

Physical GO still requires the final composed exact build to integrate and accept:

- deterministic OFF1 -> ON1 -> OFF2 -> ON2 correlation;
- explicit target confirmation;
- foreground/passive capture lifecycle;
- accepted Ready;
- at least 60 seconds of accepted monotonic Ready -> Horizon observation;
- exact-H freeze/seal and immutable artifact integrity;
- recipe progression driven only by accepted evidence/controller results;
- automatic exact build provenance;
- app-visible Capture Complete / Ready for analysis / Share Capture flow;
- final Xcode/runtime, visual, accessibility, and performance acceptance;
- explicit V14 runbook GO tied to that exact final build.

Until then: **DO NOT RUN PHYSICAL EXPERIMENT ONE.**

## Explicit non-claims

This manifest does not verify physical AOVOPRO ES80 identity, permanent UUID identity, RF completeness, GATT/Tuya/DP framing or semantics, battery percentage, voltage, current, watts/power, speed, throttle, regen, command acknowledgement, or any characteristic write. No application write path is added by this slice.
