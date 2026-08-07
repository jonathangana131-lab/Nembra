# ES80 Passive Capture -> Tuya Candidate Bridge

Status: SOFTWARE RESEARCH TOOLING ONLY. No physical AOVOPRO ES80 Tuya framing, DP, telemetry field, scaling, signedness, cadence, encryption key, command, or acknowledgement is verified by this bridge.

## Purpose

Nembra deliberately keeps two ES80 research layers separate:

1. passive CoreBluetooth capture that preserves raw GATT/value evidence, receipt provenance, target identity, and explicit continuity gaps; and
2. a bounded offline analyzer for one corroborated public Tuya BLE framing family.

The bridge closes only the mechanical gap between those layers. A retained capture artifact can be projected into analyzer inputs without asking the user to copy hex, choose a promising characteristic manually, renumber callbacks, repair timestamps, or invent continuity boundaries.

The bridge does not increase the truth status of the public Tuya candidate. A successful structural parse remains a transport/framing hypothesis until repeated physical ES80 evidence corroborates it.

## Current dependency shape

The recovered bridge is intentionally dependency-bound and must not be accepted independently.

The final bridge must compose on top of:

- the accepted final passive-capture runtime lineage currently being recovered by PR #297, followed by a non-destructive re-anchor of that passive model/package onto current `main`; and
- the accepted Tuya analyzer chronology lineage: accepted #272, packet-zero restart recovery #286, then #278 scoped receipt-sequence chronology.

The earlier #260 bridge head predates those final contracts. Recovery PR #305 preserves its useful implementation while keeping that older composition explicitly non-final.

Once both dependency lines are accepted, the final main-relative bridge delta should collapse to the bridge-owned source/tests/document instead of carrying stale copies of analyzer files or old feature-cell ancestry.

## Projection rules

`PassiveBluetoothTuyaCandidateBridge` requires an explicitly selected peripheral identifier.

For that target it:

- consumes immutable `PassiveBluetoothCaptureSession` records in original capture order;
- includes only raw `.value` observations from the exact selected peripheral;
- preserves capture session ID, vehicle identity, session start time, and selected peripheral identity on every detached transcript;
- preserves the exact peripheral, service, and characteristic strings supplied by capture;
- preserves boot-relative receipt uptime and wall-clock `receivedAtDate` without using wall clock to repair order;
- preserves the original global capture record index and immutable capture sequence number for audit mapping;
- groups independent transcripts by exact GATT identity **and** `PassiveBluetoothValueOrigin`;
- keeps transcript order deterministic by first observation in the source capture;
- never treats an interleaved callback from another characteristic as a byte gap for the selected stream;
- never splices read-response bytes with notification/indication/subscription-update bytes merely because they share a characteristic.

The stream builder uses one deterministic source array keyed by exact stream identity. It has no lossy final `compactMap` step that could silently discard an internally inconsistent stream.

### Producer authority

Bridge provenance/output structs are public read-only value views, but their construction is module-internal.

External modules may inspect capture context, source stream, source fragments, transcript, and analysis results returned by the bridge. They may not mint those values by pairing arbitrary analyzer observations/events with capture provenance that was never actually derived from the immutable session.

This is a software evidence boundary, not authentication. It does not prove who created a capture artifact or that a physical scooter is an ES80.

### Receipt chronology

Passive capture retains three distinct chronology/provenance facts:

- `sequenceNumber`: immutable capture-session record order;
- `receivedAtUptimeNanoseconds`: boot-relative monotonic receipt clock metadata; and
- `receivedAtDate`: wall-clock correlation metadata.

Wall-clock dates never repair, reorder, or interpolate callback chronology.

The recovered predecessor bridge still feeds uptime-only observations because it predates #278. That is not the final physical-capture contract. After #286 + #278 reach their accepted final descendant, the bridge must map:

- original capture record `sequenceNumber` -> analyzer `receiptSequenceNumber`; and
- exact immutable capture `session.id` -> analyzer `receiptSequenceScope`.

The final receipt-backed analyzer contract uses strict sequence order with nondecreasing uptime metadata, so two real callbacks may retain the same uptime tick when their immutable capture sequence advances. A bare sequence, bare scope, blank scope, replayed/equal sequence, or backward uptime remains fail-closed according to the accepted analyzer contract.

The bridge must never renumber filtered stream-local fragments, synthesize nanoseconds, infer order from `Date`, or substitute peripheral/model/display identity for capture-session scope.

### Continuity

Candidate continuity generation starts at zero for one projection and advances only when the capture already contains explicit gap evidence relevant to the selected target:

- a structured `.disconnected` event for that exact peripheral; or
- a global `.interruption` event.

A disconnect belonging to another peripheral does not split the selected target's transcript. Service invalidation/reacquisition in the hardened runtime records an explicit interruption before later raw value evidence, so the bridge does not splice bytes across that topology break.

The bridge does not infer hidden packet loss, reconnect success, subscription continuity, device reboot semantics, or missing callback bytes beyond what the capture artifact explicitly records.

### Fail-closed observations

A raw value callback with an empty payload cannot be represented by `TuyaCandidateFragmentObservation`. The bridge therefore rejects the projection with exact capture record/sequence/GATT/origin context. It does **not** silently drop that callback and analyze bytes on either side as though nothing happened.

Continuity-generation overflow also fails with exact source record/sequence provenance rather than wrapping and falsely reusing an earlier generation.

## Analyzer output and provenance

`PassiveBluetoothTuyaCandidateBridge.analyze(...)` runs the bounded `TuyaCandidateTranscriptAnalyzer` independently for every projected GATT+origin transcript.

Analyzer observation indices are stream-local. Each `PassiveBluetoothTuyaCandidateStreamTranscript` retains:

- the source capture session ID;
- the capture's `VehicleIdentity`;
- the session start date;
- the explicitly selected peripheral identity;
- the exact GATT + value-origin stream identity; and
- its source-fragment array containing original capture record index, immutable capture sequence number, wall-clock receipt date, receipt uptime, and raw candidate bytes.

That lets an analyzer event remain auditable back to the immutable capture even after the transcript is detached from the UI/export object. No filename convention or external bookkeeping becomes evidence truth.

No analyzer event is telemetry. In particular, `completed` means only that raw bytes satisfy the bounded public-family candidate reassembly rules. It does not mean:

- the physical ES80 is verified to use that Tuya family;
- ciphertext is authenticated or decrypted;
- a logical packet is verified for the ES80;
- any DP is battery, voltage, current, power, speed, lock, light, mode, throttle, or regen;
- any command is authorized or acknowledged.

## Acceptance requirements

Before this bridge can supersede the stopped #260 lineage:

1. the final passive-capture runtime must earn exact-head Apple-toolchain acceptance and be re-anchored onto then-current main without unrelated feature-cell history;
2. #286 packet-zero restart must be recovered/accepted on the merged chronology parent;
3. #278 must reconcile scoped receipt chronology on top of that accepted restart descendant;
4. the bridge must implement exact capture-sequence/session-scope mapping against that accepted analyzer API;
5. the final bridge-relative diff must be refreshed for overlap and kept bridge-owned where upstream dependencies are already on main;
6. focused package tests, package-wide no-application-`writeValue(...)` guard, and generic iOS Simulator package build must pass on the exact final head.

Queued, running, skipped, stale, ancestor, or dependency-obsolete checks are not acceptance.

## Intended physical workflow

Only after the combined runtime, product-facing capture shell, bridge, and offline report path are accepted should the first physical experiment proceed:

1. select the real ES80 in Nembra Research Capture while stationary;
2. perform a short passive acquisition with no characteristic writes;
3. retain a stationary baseline and deliberately marked stock-app observations;
4. finish and export the immutable capture artifact;
5. run the bridge/offline candidate tooling automatically across exact captured value streams;
6. compare structural candidate outcomes and repeated marker correlation without manually editing bytes.

A failed candidate parse is useful falsifying evidence. Do not shift offsets, remove bytes, merge origins, alter clocks, or alter continuity until a public protocol source or new physical evidence justifies a different hypothesis.

## Safety boundary

This bridge adds no `writeValue`, no command path, no encryption/decryption key handling, no device authentication, no production `ScooterService`, and no Dashboard telemetry wiring.

Its role is narrower: move trustworthy raw capture evidence into reproducible offline analysis while preserving capture identity, receipt provenance, transport provenance, and known gaps.