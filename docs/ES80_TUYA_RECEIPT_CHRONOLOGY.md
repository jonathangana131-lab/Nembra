# ES80 Tuya Candidate Receipt Chronology

Status: **SOFTWARE RESEARCH TOOLING — NOT PHYSICAL ES80 VERIFICATION**

This slice hardens the already-merged public-family Tuya offline reassembler so it can consume immutable source-order evidence without rewriting acquisition history or mixing exact streams.

It does not add decryption, credentials, DP semantics, telemetry fields, Bluetooth writes, command acknowledgement, or any physical AOVOPRO ES80 claim.

## Product gaps

The first accepted offline analyzer ordered fragments only by `receiptUptimeNanoseconds` and required that uptime to increase strictly for every accepted fragment.

That creates three evidence-integrity problems:

1. two distinct CoreBluetooth callbacks may legitimately be recorded on the same monotonic clock tick while passive capture still knows their immutable callback order; rejecting the second loses usable evidence, while inventing `+1 ns` corrupts provenance;
2. if chronology advances only when framing succeeds, a newer malformed/rejected callback can disappear and reopen the past to delayed older evidence;
3. if exact stream/generation identity binds only after framing succeeds, a malformed first observation from stream A can leave chronology behind and then let a valid packet-zero from stream B enter the same reassembler instance.

The hardened primitive therefore separates three concepts:

- **source binding** — exact stream identity + continuity generation from the first seen observation;
- **seen receipt chronology** — source-owned order evidence consumed before candidate framing;
- **accepted candidate bytes** — observations that additionally pass bounded framing validation.

## Exact stream/generation binding starts on first seen observation

A `TuyaCandidateFragmentReassembler` is one exact value stream and one continuity generation. That invariant now begins with the first **seen** observation, not the first successfully framed packet zero.

If the first observation later fails framing:

- its exact `streamIdentity` and `continuityGeneration` still remain the reassembler's source binding;
- a callback from another stream fails `.streamChanged` before receipt chronology mutates;
- a callback from another continuity generation fails `.continuityGenerationChanged` before receipt chronology mutates;
- a genuinely newer/same-tick admissible callback from the originally selected stream/generation may still recover the candidate according to the receipt-order policy.

This applies to both receipt-backed and legacy uptime-only ordering. It does not promote bytes from the malformed callback: source identity is transport provenance, while candidate message state remains committed only after framing succeeds.

The transcript layer remains responsible for intentionally creating a fresh reassembler when it observes a real stream/generation boundary.

## Sequence identity is scoped evidence

Nembra's passive capture does not define a bare process-global sequence. `PassiveBluetoothCaptureSession` carries an immutable session ID, and records inside that session enforce strictly increasing sequence plus nondecreasing uptime. A device reboot starts a new capture session because the boot-relative uptime clock resets.

That means a numeric sequence is meaningful only inside the counter epoch that minted it. Two unrelated captures can both contain sequence `40`; the number alone cannot prove those callbacks share one order domain.

`TuyaCandidateFragmentObservation` therefore supports exactly two ordering forms:

1. legacy uptime-only evidence: both `receiptSequenceNumber` and `receiptSequenceScope` are absent;
2. receipt-backed evidence: both fields are present, where `receiptSequenceScope` is the opaque identity of the source-owned counter epoch and `receiptSequenceNumber` is immutable callback order inside it.

A scope without a sequence is invalid. A sequence without a scope is invalid. Blank scope identity is invalid. Receipt ordering authority and receipt scope bind on the first **seen** observation, even if that observation later fails framing. A different scope therefore fails closed before selected sequence or uptime watermarks mutate. A completed candidate retains the accepted scope plus its first/last accepted sequence numbers.

For Nembra's passive-capture bridge, the correct source scope is the exact immutable capture session ID. A display/model string, peripheral name, wall-clock timestamp, or inferred epoch must not replace it. The scope is deliberately **non-secret provenance identity**: never place a Tuya local key, token, session secret, credential, or other authentication material in this field.

## Two explicit ordering modes

### Receipt-backed mode

When the first observation carries the required sequence + scope pair:

- every observation in that candidate must remain receipt-backed;
- sequence scope must remain identical;
- sequence must increase strictly;
- uptime must be nondecreasing, so distinct callbacks may share one real clock tick;
- no timestamp precision is synthesized;
- highest seen sequence is consumed before later uptime/framing validation;
- a newer callback rejected for backward uptime or framing cannot later be replaced by older/delayed callback evidence;
- a rejected receipt identity cannot be retried with rewritten uptime;
- a foreign scope is rejected before selected-scope chronology changes;
- the completed candidate preserves scope plus first and last accepted sequence numbers as provenance.

Sequence is callback-order evidence only. It is not packet meaning, protocol sequence, vehicle state, or physical timing cadence.

### Legacy uptime-only mode

When the first observation carries neither sequence field:

- uptime is the only ordering authority and must increase strictly across **seen observations**, not only accepted fragments;
- each admissible new uptime high-water is consumed before packet framing validation;
- a newer malformed/rejected callback therefore blocks delayed older evidence;
- equal uptime is rejected because no stronger receipt sequence exists to prove order;
- legacy producers are not silently assigned synthetic receipt identities or timestamp precision.

A candidate cannot switch between receipt-backed and legacy ordering midway. Mixed authority fails closed rather than silently changing chronology rules, including when the first seen observation itself later fails framing.

## Why rejected callbacks consume source chronology

An immutable scoped receipt sequence identifies one raw acquisition callback. Once sequence `12` has been seen in that scope, later receipt `11` is stale even if callback `12` fails packet-index, length, or other framing checks.

Legacy uptime-only evidence follows the same no-rewrite principle with the weaker authority it has: once uptime `300` is seen and admitted as newer than the previous high-water, a later uptime `200` is stale even if the callback at `300` failed framing.

A rejected callback does not enter the reconstructed encrypted message, but it cannot disappear from source order and reopen the past. Rejection must not promote bad semantic evidence, while immutable/source-owned transport chronology must not be rewritten to make a later parse convenient.

## Stream, continuity, and sequence scope are distinct

Exact stream identity and continuity generation are checked before receipt chronology admission.

A callback from another peripheral/service/characteristic or continuity generation therefore cannot poison the selected stream's sequence/uptime watermark, including before any candidate packet zero has been accepted.

Sequence scope is a different dimension:

- sequence scope answers **which counter epoch owns this receipt sequence**;
- stream identity answers **which exact GATT value stream produced the bytes**;
- continuity generation answers **whether byte continuity is known across observations**.

None substitutes for another.

## Transcript-wide dependency

Accepted PR #272 now owns transcript-wide chronology across candidate completion, rejection, and stream/continuity boundaries on `main`. Dependent PR #286 owns same-stream packet-zero restart recovery on top of that accepted chronology. Its transcript files remain actively owned by another worker, so this lane does not edit them before #286 is reconciled and accepted.

Final composition must preserve that parent chain while using one shared receipt-order law:

- receipt-backed transcript: same scope, strict sequence, nondecreasing uptime;
- legacy transcript: strict **seen** uptime;
- rejected newer receipts consume source chronology without promoting candidate bytes;
- boundary evidence remains explicit before the next observation is rejected;
- chronology authority does not reset merely because one candidate completes or fails;
- real stream/generation boundaries remain stronger than packet-zero restart;
- receipt chronology remains stronger than packet-zero restart, so replayed/stale packet zero cannot manufacture a new candidate;
- a chronology-admitted packet-zero restart may start a fresh candidate without losing the exact immutable observation.

The intended integration order is **accepted #272 -> #286 -> this receipt-chronology lane**. This lane must not merge independently until #286 is accepted and the final transcript authority composition is implemented and revalidated on that descendant.

A local composition prototype already extracts this exact receipt-order state machine into one internal helper consumed by both the bounded reassembler and transcript analyzer. That prototype exists only as validation until the incumbent transcript parent is accepted; it is not a competing GitHub edit.

## Downstream bridge handoff

The active passive-capture-to-Tuya bridge already preserves both immutable capture session ID in `captureContext.sessionID` and original record sequence number in each source fragment.

After parent chronology reconciliation, that bridge should map:

- exact `captureSequenceNumber` -> `receiptSequenceNumber`;
- exact immutable capture session ID -> `receiptSequenceScope`.

It must not renumber filtered fragments, infer order from wall-clock dates, manufacture timestamps, or replace the session ID with a display/model string.

## Tests

Focused branch regressions cover:

- two receipt-backed callbacks at identical uptime completing one message;
- first/last receipt-sequence provenance on the completed message;
- capture-scope provenance retained on a completed message;
- foreign capture scope rejected before selected-scope chronology mutation;
- rejected **first** framing observation binding receipt scope so another scope cannot replace it;
- scope-without-sequence rejection;
- sequence-without-scope rejection;
- blank-scope rejection;
- a rejected newer receipt-backed callback blocking delayed older evidence;
- backward uptime consuming newer receipt identity so it cannot be rewritten in place;
- recovery with a genuinely newer sequence at the preserved uptime floor;
- receipt-backed/legacy authority switching rejected in either direction;
- legacy equal-uptime rejection;
- rejected newer legacy callback consuming uptime high-water so delayed older input is rejected and only genuinely newer input recovers;
- foreign stream rejection after candidate acceptance without poisoning selected chronology;
- malformed first receipt-backed observation binding exact stream before framing, rejecting a foreign stream before chronology, then recovering on the selected stream;
- malformed first receipt-backed observation binding continuity generation before framing, rejecting a foreign generation before chronology, then recovering on the selected generation;
- malformed first **legacy** observation binding exact stream before framing, rejecting a foreign stream before chronology, then recovering only on genuinely newer selected-stream uptime.

Local parent-composition testing additionally keeps #272 transcript-wide boundary/recovery regressions and #286 packet-zero restart regressions active while exercising same-tick receipt-backed ordering, cross-candidate scoped high-water, rejected-receipt consumption, authority switching, scope changes, restart precedence, and shared-helper reuse. Current supplemental Swift 6.2.1 results are **32/32 debug** and **32/32 release with warnings-as-errors**. Repository-native exact-head QA remains the acceptance gate after dependency reconciliation.

## Truth boundary

This is offline evidence-ordering and source-binding hardening only.

It does **not** establish:

- that a physical AOVOPRO ES80 uses this Tuya framing family;
- ES80 advertisement/GATT identity;
- any DP ID/type/scale/signedness/unit/cadence;
- battery %, voltage, current, watts/power, speed, odometer, trip, charging state, throttle, or regen semantics;
- authentication, encryption keys, command authorization, command acknowledgement, or writable behavior;
- physical callback cadence or latency.

Physical ES80 capture and repeated stock-app correlation remain required before any field can become production telemetry.
