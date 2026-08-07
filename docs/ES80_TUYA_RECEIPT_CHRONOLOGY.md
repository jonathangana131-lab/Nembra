# ES80 Tuya Candidate Receipt Chronology

Status: **SOFTWARE RESEARCH TOOLING — NOT PHYSICAL ES80 VERIFICATION**

This slice hardens the already-merged public-family Tuya offline reassembler so it can consume the immutable callback receipt order preserved by Nembra's passive-capture pipeline.

It does not add decryption, credentials, DP semantics, telemetry fields, Bluetooth writes, command acknowledgement, or any physical AOVOPRO ES80 claim.

## Product gap

The first accepted offline analyzer ordered fragments only by `receiptUptimeNanoseconds` and required that uptime to increase strictly for every accepted fragment.

That is conservative when uptime is the only ordering evidence, but it creates a mechanical mismatch with passive capture: two distinct CoreBluetooth callbacks may legitimately be recorded on the same monotonic clock tick while the capture layer still knows their immutable callback order. Rejecting the second callback loses usable evidence. Inventing `+1 ns` timestamps to make it fit would be worse because fabricated time would become false provenance.

The capture/bridge path already retains callback sequence identity. This slice lets the analyzer use that stronger evidence directly.

## Sequence identity is scoped evidence

Nembra's passive capture does not define a bare process-global sequence. `PassiveBluetoothCaptureSession` carries an immutable session ID, and records inside that session enforce strictly increasing sequence plus nondecreasing uptime. A physical device reboot starts a new capture session because the boot-relative uptime clock resets.

That means a numeric sequence is meaningful only inside the counter epoch that minted it. Two unrelated captures can both contain sequence `40`; the number alone cannot prove those callbacks share one order domain.

`TuyaCandidateFragmentObservation` therefore supports both:

- `receiptSequenceNumber` — immutable callback order inside one source-owned counter epoch;
- `receiptSequenceScope` — optional opaque identity for that epoch, such as Nembra passive capture's immutable session ID.

A sequence scope without a sequence is invalid. Blank scope identity is invalid. Once a sequence-backed candidate starts with a scope, a different scope fails closed **before** sequence or uptime watermarks mutate. The completed candidate retains that scope alongside its first/last accepted sequence numbers.

Generic/public-family research callers may remain sequence-only when they truly own the ordering contract, but the physical passive-capture bridge must carry its real session/epoch scope rather than treating a bare integer as globally comparable.

## Two explicit ordering modes

`TuyaCandidateFragmentObservation.receiptSequenceNumber` is optional for compatibility with existing transcript producers.

### Sequence-backed mode

When the first observation carries a receipt sequence:

- every observation in that candidate must carry a sequence;
- any supplied sequence scope must remain identical for the candidate;
- sequence must increase strictly;
- uptime must be nondecreasing, so two distinct callbacks may share one real clock tick;
- no timestamp precision is synthesized;
- the highest seen sequence is consumed before later framing validation;
- a newer callback rejected for backward uptime or framing cannot later be replaced by an older/delayed callback;
- a rejected receipt identity cannot be retried with rewritten uptime;
- a foreign sequence scope is rejected before selected-scope chronology changes;
- the completed candidate preserves scope plus first and last accepted sequence numbers as provenance.

Sequence is callback-order evidence only. It is not packet meaning, protocol sequence, vehicle state, or physical timing cadence.

### Legacy uptime-only mode

When the first observation has no receipt sequence, the original behavior remains:

- accepted fragment uptime must increase strictly;
- equal uptime is rejected;
- existing producers are not silently assigned synthetic receipt identities.

A candidate cannot switch between sequence-backed and legacy ordering midway. Mixed authority fails closed rather than silently changing chronology rules.

## Why rejected callbacks consume sequence chronology

An immutable receipt sequence identifies one raw acquisition callback inside its source-owned scope. Once sequence `12` has been seen in that scope, later receipt `11` is stale even if callback `12` fails packet-index, length, or other framing checks.

The analyzer therefore keeps two concepts separate:

1. **seen callback chronology** — immutable source ordering evidence;
2. **accepted candidate bytes** — fragments that also pass framing validation.

A rejected callback does not enter the reconstructed encrypted message, but it also cannot disappear from source order and reopen the past.

This mirrors Nembra's wider truth rule: rejection must not promote bad semantic evidence, but immutable transport chronology must not be rewritten to make a later parse convenient.

## Stream and continuity isolation

Exact stream identity and continuity generation are still checked before receipt chronology admission.

A callback from another peripheral/service/characteristic or another continuity generation therefore cannot poison the selected stream's sequence watermark. The existing transcript boundary contract remains authoritative for starting a fresh candidate after a known byte-continuity break.

Sequence scope is separate from stream and continuity identity: session/epoch scope answers **which counter owns this sequence**, while stream identity answers **which GATT value stream produced the bytes**, and continuity generation answers **whether byte continuity is known across observations**. None substitutes for another.

## Transcript-wide dependency

Active PR #272 owns transcript-wide chronology across candidate completion, rejection, and stream/continuity boundaries. Its current uptime-only high-water and this scoped sequence-backed reassembler must be reconciled before this lane can merge.

Final composition must preserve #272's cross-candidate replay closure while using the same authority law as the reassembler:

- scoped/sequence-backed transcript: same scope, strict sequence, nondecreasing uptime;
- sequence-only research transcript: strict sequence, nondecreasing uptime;
- legacy transcript: strict uptime;
- rejected newer receipts consume source chronology without promoting candidate bytes;
- boundary evidence remains explicit before the next observation is rejected;
- chronology authority does not reset merely because one candidate completes or fails.

This lane must not merge independently until that composition is implemented and revalidated on the accepted #272 parent.

## Downstream bridge handoff

The active passive-capture-to-Tuya bridge already preserves both the immutable capture session ID in `captureContext.sessionID` and the original record sequence number in each source fragment.

After parent chronology reconciliation, that bridge should map:

- exact `captureSequenceNumber` -> `receiptSequenceNumber`;
- exact immutable capture session ID -> `receiptSequenceScope`.

It must not renumber filtered fragments, infer order from wall-clock dates, manufacture timestamps, or replace the session ID with a display/model string.

## Tests

Focused regressions cover:

- two sequence-backed callbacks at identical uptime completing one message;
- first/last receipt-sequence provenance on the completed message;
- capture-scope provenance retained on a completed message;
- foreign capture scope rejected before selected-scope chronology mutation;
- scope-without-sequence and blank-scope construction rejected;
- sequence-only generic research compatibility retained;
- a rejected newer callback blocking a delayed older receipt;
- a backward-uptime callback consuming its newer receipt identity so it cannot be rewritten in place;
- recovery with a genuinely newer sequence at the preserved uptime floor;
- rejection of sequence-backed/legacy authority switching in either direction;
- preservation of legacy strict-uptime behavior;
- foreign-stream rejection occurring before selected-stream chronology admission.

Local composition testing additionally keeps #272's transcript-wide boundary/recovery regressions active while exercising equal-tick sequence order, cross-candidate sequence high-water, rejected-receipt consumption, authority switching, and recovery. Repository-native exact-head QA remains the acceptance gate.

## Truth boundary

This is an offline evidence-ordering improvement only.

It does **not** establish:

- that a physical AOVOPRO ES80 uses this Tuya framing family;
- ES80 advertisement/GATT identity;
- any DP ID/type/scale/signedness/unit/cadence;
- battery %, voltage, current, watts/power, speed, odometer, trip, charging state, throttle, or regen semantics;
- authentication, encryption keys, command authorization, command acknowledgement, or writable behavior;
- physical callback cadence or latency.

Physical ES80 capture and repeated stock-app correlation remain required before any field can become production telemetry.
