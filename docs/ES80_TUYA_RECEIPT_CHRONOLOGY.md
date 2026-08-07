# ES80 Tuya Candidate Receipt Chronology

Status: **SOFTWARE RESEARCH TOOLING — NOT PHYSICAL ES80 VERIFICATION**

This slice hardens the already-merged public-family Tuya offline reassembler so it can consume the immutable callback receipt order preserved by Nembra's passive-capture pipeline.

It does not add decryption, credentials, DP semantics, telemetry fields, Bluetooth writes, command acknowledgement, or any physical AOVOPRO ES80 claim.

## Product gap

The first accepted offline analyzer ordered fragments only by `receiptUptimeNanoseconds` and required that uptime to increase strictly for every accepted fragment.

That is conservative when uptime is the only ordering evidence, but it creates a mechanical mismatch with passive capture: two distinct CoreBluetooth callbacks may legitimately be recorded on the same monotonic clock tick while the capture layer still knows their immutable callback order. Rejecting the second callback loses usable evidence. Inventing `+1 ns` timestamps to make it fit would be worse because fabricated time would become false provenance.

The capture/bridge path already retains callback sequence identity. This slice lets the analyzer use that stronger evidence directly.

## Two explicit ordering modes

`TuyaCandidateFragmentObservation.receiptSequenceNumber` is optional for compatibility with existing transcript producers.

### Sequence-backed mode

When the first observation carries a receipt sequence:

- every observation in that candidate must carry a sequence;
- sequence must increase strictly;
- uptime must be nondecreasing, so two distinct callbacks may share one real clock tick;
- no timestamp precision is synthesized;
- the highest seen sequence is consumed before later framing validation;
- a newer callback rejected for backward uptime or framing cannot later be replaced by an older/delayed callback;
- a rejected receipt identity cannot be retried with rewritten uptime;
- the completed candidate preserves its first and last accepted sequence numbers as provenance.

Sequence is callback-order evidence only. It is not packet meaning, protocol sequence, vehicle state, or physical timing cadence.

### Legacy uptime-only mode

When the first observation has no receipt sequence, the original behavior remains:

- accepted fragment uptime must increase strictly;
- equal uptime is rejected;
- existing producers are not silently assigned synthetic receipt identities.

A candidate cannot switch between sequence-backed and legacy ordering midway. Mixed authority fails closed rather than silently changing chronology rules.

## Why rejected callbacks consume sequence chronology

An immutable receipt sequence identifies one raw acquisition callback. Once sequence `12` has been seen, later receipt `11` is stale even if callback `12` fails packet-index, length, or other framing checks.

The analyzer therefore keeps two concepts separate:

1. **seen callback chronology** — immutable source ordering evidence;
2. **accepted candidate bytes** — fragments that also pass framing validation.

A rejected callback does not enter the reconstructed encrypted message, but it also cannot disappear from source order and reopen the past.

This mirrors Nembra's wider truth rule: rejection must not promote bad semantic evidence, but immutable transport chronology must not be rewritten to make a later parse convenient.

## Stream and continuity isolation

Exact stream identity and continuity generation are still checked before receipt chronology admission.

A callback from another peripheral/service/characteristic or another continuity generation therefore cannot poison the selected stream's sequence watermark. The existing transcript boundary contract remains authoritative for starting a fresh candidate after a known byte-continuity break.

## Downstream bridge handoff

The active passive-capture-to-Tuya bridge already preserves the original capture sequence number. Once this parent hardening is accepted, that bridge can map its immutable capture receipt sequence into `TuyaCandidateFragmentObservation.receiptSequenceNumber` instead of leaving equal-uptime observations to be rejected by the legacy analyzer.

That integration must preserve the exact original sequence; it must not renumber filtered fragments, infer order from wall-clock dates, or manufacture timestamps.

## Tests

Focused regressions cover:

- two sequence-backed callbacks at identical uptime completing one message;
- first/last receipt-sequence provenance on the completed message;
- a rejected newer callback blocking a delayed older receipt;
- a backward-uptime callback consuming its newer receipt identity so it cannot be rewritten in place;
- recovery with a genuinely newer sequence at the preserved uptime floor;
- rejection of sequence-backed/legacy authority switching in either direction;
- preservation of legacy strict-uptime behavior;
- foreign-stream rejection occurring before selected-stream chronology admission.

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