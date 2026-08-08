# ES80 Tuya Candidate Bridge — Provenance Authority

Status: **SOFTWARE / PUBLIC-FAMILY RESEARCH ONLY — NOT PHYSICAL ES80 PROOF.**

## In-memory bridge input is caller-constructible

`PassiveBluetoothTuyaCandidateBridge` accepts `PassiveBluetoothCaptureSession` directly. That core session type, its record type, and the validated event/observation constructors are public API. A caller can therefore construct a structurally valid session in memory and pass it to the bridge without that session ever having come from Nembra's live CoreBluetooth recorder or a retained Capture artifact.

The bridge may truthfully preserve exact values *within the session it receives* — session UUID, vehicle metadata, peripheral identifier, record index, capture sequence number, receipt clocks, GATT identity, value origin, payload bytes, and continuity generation. That is deterministic software-session provenance.

It must not infer from those fields alone that:
- Nembra's live recorder produced the session;
- an immutable exported Capture artifact existed;
- exact artifact bytes were retained or independently hashed;
- a signed/field-authorized build produced the evidence;
- the selected peripheral is physically authenticated as an AOVOPRO ES80;
- any Tuya candidate framing is verified ES80 protocol semantics.

`PassiveBluetoothTuyaCandidateCaptureContext.sessionProvenanceAuthority` therefore reports only `validatedSoftwareSession`.

## What package-private output initializers do prove

The bridge's context/transcript/fragment initializers remain package-internal. That prevents external code from directly assembling mutually inconsistent bridge output objects. It does **not** authenticate the public input session. Output-construction integrity and input provenance authority are separate claims.

## Stronger artifact provenance is a separate rung

A downstream offline artifact tool may establish stronger integrity/provenance by validating the versioned Capture JSON and binding derived output to the exact retained input bytes (for example with an independently checked SHA-256). That stronger artifact binding must remain explicit and separate from the in-memory bridge's authority label. Artifact integrity still does not equal physical scooter identity or protocol verification.

No characteristic-value write path, command authority, telemetry meaning, DP mapping, encryption/authentication claim, or physical GO authority is added by this contract.
