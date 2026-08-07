# ES80 Passive Capture -> Tuya Candidate Bridge

Status: SOFTWARE RESEARCH TOOLING ONLY. No physical AOVOPRO ES80 Tuya framing, DP, telemetry field, scaling, signedness, cadence, encryption key, command, or acknowledgement is verified by this bridge.

## Purpose

Nembra already has two deliberately separate pieces of the ES80 research path:

1. passive CoreBluetooth capture that preserves raw GATT/value evidence and continuity; and
2. a bounded offline analyzer for one corroborated public Tuya BLE framing family.

The bridge closes the mechanical gap between those systems. A captured artifact can be projected directly into analyzer inputs without asking the user to copy hex, choose a promising characteristic manually, renumber fragments, or invent continuity boundaries.

The bridge does not increase the truth status of the public Tuya candidate. A successful structural parse is still only a transport/framing hypothesis until repeated physical ES80 evidence corroborates it.

## Dependency shape

This lane is intentionally dependent on both active parent lanes:

- passive-capture runtime/recovery head from PR #239; and
- public-family offline analyzer head from PR #219.

It should not be merged independently of those parents. Its own source delta is additive inside `Packages/NembraBluetoothCapture` plus this document.

## Projection rules

`PassiveBluetoothTuyaCandidateBridge` requires an explicitly selected peripheral identifier.

For that target it:

- consumes immutable `PassiveBluetoothCaptureSession` records in original capture order;
- includes only raw `.value` observations from the exact selected peripheral;
- preserves capture session ID, vehicle identity, session start time, and selected peripheral identity on every detached transcript;
- preserves the exact peripheral, service, and characteristic strings supplied by capture;
- preserves both source clocks: boot-relative receipt uptime for ordering and wall-clock `receivedAtDate` as metadata;
- preserves the original capture record index and sequence number for audit mapping;
- groups independent transcripts by exact GATT identity **and** `PassiveBluetoothValueOrigin`;
- keeps transcript order deterministic by first observation in the source capture;
- never treats an interleaved callback from another characteristic as a byte gap for the selected stream;
- never splices read-response bytes with notification/indication/subscription-update bytes merely because they share a characteristic.

The stream builder uses one deterministic source array keyed by exact stream identity. It has no lossy final `compactMap` step that could silently discard an internally inconsistent stream.

### Timing provenance

The passive capture domain intentionally distinguishes two clocks:

- `receivedAtUptimeNanoseconds` is the boot-relative monotonic ordering clock; and
- `receivedAtDate` is wall-clock correlation metadata.

The bridge preserves both values exactly. Wall-clock dates never repair, reorder, or interpolate capture chronology. Equal uptime values remain equal even when their wall-clock metadata differs; if the bounded analyzer rejects that chronology inside a candidate, the rejection is retained as evidence instead of being hidden by synthesized timing.

### Continuity

Candidate continuity generation starts at zero for the projection and advances only when the capture already contains explicit gap evidence relevant to the selected target:

- a structured `.disconnected` event for that exact peripheral; or
- a global `.interruption` event.

A disconnect belonging to another peripheral does not split the selected target's transcript.

The bridge does not infer hidden packet loss, reconnect success, subscription continuity, or device reboot semantics beyond what the capture artifact explicitly records.

### Fail-closed observations

A raw value callback with an empty payload cannot be represented by `TuyaCandidateFragmentObservation`. The bridge therefore rejects the projection with the exact capture record/sequence/GATT/origin context. It does **not** silently drop that callback and analyze the bytes on either side as though nothing happened.

The bridge also preserves equal receipt uptimes exactly. If the candidate analyzer requires a strictly increasing uptime inside an in-progress candidate, equal timestamps remain rejection evidence; the bridge does not add fake nanoseconds to make a parse succeed.

## Analyzer output and provenance

`PassiveBluetoothTuyaCandidateBridge.analyze(...)` runs the existing `TuyaCandidateTranscriptAnalyzer` independently for every projected GATT+origin transcript.

Analyzer observation indices are stream-local. Each `PassiveBluetoothTuyaCandidateStreamTranscript` retains:

- the source capture session ID;
- the capture's `VehicleIdentity`;
- the session start date;
- the explicitly selected peripheral identity;
- the exact GATT + value-origin stream identity; and
- its `PassiveBluetoothTuyaCandidateSourceFragment` array containing source record index, sequence number, wall-clock receipt date, monotonic receipt uptime, and raw candidate bytes.

That lets an analyzer event remain auditable back to the immutable capture even after the transcript is detached from the UI/export object. No filename convention or external bookkeeping becomes part of evidence truth.

No analyzer event is telemetry. In particular, `completed` means only that raw bytes satisfy the bounded public-family candidate reassembly rules. It does not mean:

- the physical ES80 is verified to use that Tuya family;
- ciphertext is authenticated or decrypted;
- a logical packet is verified for the ES80;
- any DP is battery, voltage, current, power, speed, lock, light, mode, throttle, or regen;
- any command is authorized or acknowledged.

## Intended physical workflow

After the passive-capture parent is accepted on a physical-device-capable build, the safe next evidence loop is:

1. select the real ES80 in Nembra Research Capture;
2. perform a short passive acquisition with no characteristic writes;
3. record a stable stationary baseline and one or more stock-app markers for a displayed value;
4. export the immutable capture artifact;
5. run this bridge and the offline candidate analyzer automatically across every exact captured value stream;
6. compare structural candidate outcomes and repeated marker correlation without manually editing bytes.

A failed candidate parse is useful falsifying evidence. Do not shift offsets, remove bytes, merge origins, alter clocks, or alter continuity until a public protocol source or new physical evidence justifies a different hypothesis.

## Safety boundary

This bridge adds no `writeValue`, no command path, no encryption/decryption key handling, no device authentication, no production `ScooterService`, and no Dashboard telemetry wiring.

Its role is narrower: move trustworthy raw capture evidence into reproducible offline analysis while preserving capture identity, timing provenance, transport provenance, and known gaps.
