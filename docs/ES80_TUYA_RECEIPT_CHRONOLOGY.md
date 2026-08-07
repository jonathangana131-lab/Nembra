# ES80 Tuya Candidate Receipt Chronology

Status: **SOFTWARE RESEARCH TOOLING — NOT PHYSICAL ES80 VERIFICATION**

This slice hardens the already-merged public-family Tuya offline reassembler so it can consume the immutable callback receipt order preserved by Nembra's passive-capture pipeline.

It does not add decryption, credentials, DP semantics, telemetry fields, Bluetooth writes, command acknowledgement, or any physical AOVOPRO ES80 claim.

## Product gap

The first accepted offline analyzer ordered fragments only by `receiptUptimeNanoseconds` and required that uptime to increase strictly for every accepted fragment.

That is conservative when uptime is the only ordering evidence, but it creates a mechanical mismatch with passive capture: two distinct CoreBluetooth callbacks may legitimately be recorded on the same monotonic clock tick while the capture layer still knows their immutable callback order. Rejecting the second callback loses usable evidence. Inventing `+1 ns` timestamps to make it fit would be worse because fabricated time would become false provenance.

There is also a source-history problem if chronology advances only when framing succeeds. A newer callback that fails packet-index/length/framing validation still happened. Forgetting it can reopen the past and allow a delayed older callback into the candidate later. Both receipt-backed and legacy uptime-only modes therefore separate **seen source chronology** from **accepted candidate bytes**.

The capture/bridge path already retains callback sequence identity. This slice lets the analyzer use that stronger evidence directly without turning an unscoped integer into false global authority.

## Sequence identity is scoped evidence

Nembra's passive capture does not define a bare process-global sequence. `PassiveBluetoothCaptureSession` carries an immutable session ID, and records inside that session enforce strictly increasing sequence plus nondecreasing uptime. A physical device reboot starts a new capture session because the boot-relative uptime clock resets.

That means a numeric sequence is meaningful only inside the counter epoch that minted it. Two unrelated captures can both contain sequence `40`; the number alone cannot prove those callbacks share one order domain.

`TuyaCandidateFragmentObservation` therefore supports exactly two ordering forms:

1. legacy uptime-only evidence: both `receiptSequenceNumber` and `receiptSequenceScope` are absent;
2. receipt-backed evidence: both fields are present, where `receiptSequenceScope` is the opaque identity of the source-owned counter epoch and `receiptSequenceNumber` is the immutable callback order inside it.

A scope without a sequence is invalid. A sequence without a scope is also invalid. Blank scope identity is invalid. Once a receipt-backed candidate starts, a different scope fails closed **before** sequence or uptime watermarks mutate. The completed candidate retains that scope alongside its first/last accepted sequence numbers.

For Nembra's physical passive-capture bridge, the correct source scope is the exact immutable capture session ID. A display/model string, peripheral name, wall-clock timestamp, or inferred epoch must not replace it. The scope is deliberately **non-secret provenance identity**: never place a Tuya local key, token, session secret, credential, or other authentication material in this field.

## Two explicit ordering modes

### Receipt-backed mode

When the first observation carries the required sequence + scope pair:

- every observation in that candidate must remain receipt-backed;
- sequence scope must remain identical;
- sequence must increase strictly;
- uptime must be nondecreasing, so two distinct callbacks may share one real clock tick;
- no timestamp precision is synthesized;
- the highest seen sequence is consumed before later uptime/framing validation;
- a newer callback rejected for backward uptime or framing cannot later be replaced by an older/delayed callback;
- a rejected receipt identity cannot be retried with rewritten uptime;
- a foreign sequence scope is rejected before selected-scope chronology changes;
- the completed candidate preserves scope plus first and last accepted sequence numbers as provenance.

Sequence is callback-order evidence only. It is not packet meaning, protocol sequence, vehicle state, or physical timing cadence.

### Legacy uptime-only mode

When the first observation carries neither sequence field:

- uptime is the only ordering authority and must increase strictly across **seen observations**, not only accepted fragments;
- the new admissible uptime high-water is consumed before packet framing validation;
- a newer malformed/rejected callback therefore blocks delayed older callback evidence from entering later;
- equal uptime is rejected because no stronger receipt sequence exists to prove order;
- existing legacy producers are not silently assigned synthetic receipt identities or timestamp precision.

A candidate cannot switch between receipt-backed and legacy ordering midway. Mixed authority fails closed rather than silently changing chronology rules.

## Why rejected callbacks consume source chronology

An immutable scoped receipt sequence identifies one raw acquisition callback. Once sequence `12` has been seen in that scope, later receipt `11` is stale even if callback `12` fails packet-index, length, or other framing checks.

Legacy uptime-only evidence follows the same no-rewrite principle with the weaker authority it has: once uptime `300` is seen and admitted as newer than the previous high-water, a later uptime `200` is stale even if the callback at `300` failed framing. The rejected callback does not become candidate bytes, but it cannot disappear from acquisition history.

The analyzer therefore keeps two concepts separate:

1. **seen callback chronology** — immutable/source-owned ordering evidence;
2. **accepted candidate bytes** — observations that also pass framing validation.

A rejected callback does not enter the reconstructed encrypted message, but it also cannot disappear from source order and reopen the past.

This mirrors Nembra's wider truth rule: rejection must not promote bad semantic evidence, but transport chronology must not be rewritten to make a later parse convenient.

## Stream and continuity isolation

Exact stream identity and continuity generation are still checked before receipt chronology admission.

A callback from another peripheral/service/characteristic or another continuity generation therefore cannot poison the selected stream's sequence/uptime watermark. The existing transcript boundary contract remains authoritative for starting a fresh candidate after a known byte-continuity break.

Sequence scope is separate from stream and continuity identity: session/epoch scope answers **which counter owns this sequence**, stream identity answers **which GATT value stream produced the bytes**, and continuity generation answers **whether byte continuity is known across observations**. None substitutes for another.

## Transcript-wide dependency

Active PR #272 owns transcript-wide chronology across candidate completion, rejection, and stream/continuity boundaries. Dependent PR #286 owns same-stream packet-zero restart recovery on top of that chronology. Their current uptime-only transcript gate and this receipt-backed reassembler must be reconciled before this lane can merge.

Final composition must preserve the parent chain's behavior while using the same authority law as the reassembler:

- receipt-backed transcript: same scope, strict sequence, nondecreasing uptime;
- legacy transcript: strict **seen** uptime;
- rejected newer receipts consume source chronology without promoting candidate bytes;
- boundary evidence remains explicit before the next observation is rejected;
- chronology authority does not reset merely because one candidate completes or fails;
- real stream/generation boundaries remain stronger than packet-zero restart;
- receipt chronology remains stronger than packet-zero restart, so replayed or stale packet zero cannot manufacture a new candidate;
- a chronology-admitted packet-zero restart may start a fresh candidate without losing the exact immutable observation.

The intended integration order is **#272 -> #286 -> this receipt-chronology lane**. This lane must not merge independently until that composition is implemented and revalidated on the accepted parent descendant.

## Downstream bridge handoff

The active passive-capture-to-Tuya bridge already preserves both the immutable capture session ID in `captureContext.sessionID` and the original record sequence number in each source fragment.

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
- scope-without-sequence rejection;
- sequence-without-scope rejection;
- blank-scope rejection;
- a rejected newer receipt-backed callback blocking delayed older receipt evidence;
- a backward-uptime callback consuming its newer receipt identity so it cannot be rewritten in place;
- recovery with a genuinely newer sequence at the preserved uptime floor;
- rejection of receipt-backed/legacy authority switching in either direction;
- preservation of legacy strict seen-uptime behavior;
- a rejected newer legacy callback consuming uptime high-water so delayed older input is rejected and only genuinely newer input can recover;
- foreign-stream rejection occurring before selected-stream chronology admission.

Local composition testing additionally keeps #272's transcript-wide boundary/recovery regressions and #286's packet-zero restart regressions active while exercising same-tick receipt-backed ordering, cross-candidate scoped high-water, rejected-receipt consumption, authority switching, scope changes, and restart precedence. Repository-native exact-head QA remains the acceptance gate.

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
