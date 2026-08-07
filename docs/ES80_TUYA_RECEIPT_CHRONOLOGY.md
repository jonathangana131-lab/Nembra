# ES80 Tuya Candidate Receipt Chronology

Status: **SOFTWARE RESEARCH TOOLING — NOT PHYSICAL ES80 VERIFICATION**

This slice hardens Nembra's public-family Tuya offline analysis so immutable source-order evidence survives framing failure, candidate completion, same-stream packet-zero restart, and transcript boundaries without rewriting acquisition history or mixing exact streams.

It does not add decryption, credentials, DP semantics, telemetry fields, Bluetooth writes, command acknowledgement, or any physical AOVOPRO ES80 claim.

## Product gaps

The first accepted offline analyzer ordered fragments only by `receiptUptimeNanoseconds` and required that uptime to increase strictly for every accepted fragment.

That creates three evidence-integrity problems:

1. two distinct CoreBluetooth callbacks may legitimately be recorded on the same monotonic clock tick while passive capture still knows their immutable callback order; rejecting the second loses usable evidence, while inventing `+1 ns` corrupts provenance;
2. if chronology advances only when framing succeeds, a newer malformed/rejected callback can disappear and reopen the past to delayed older evidence;
3. if exact stream/generation identity binds only after framing succeeds, a malformed first observation from stream A can leave chronology behind and then let a valid packet-zero from stream B enter the same reassembler instance.

The hardened path therefore separates three concepts:

- **source binding** — exact stream identity + continuity generation from the first seen observation;
- **seen receipt chronology** — source-owned order evidence consumed before candidate framing;
- **accepted candidate bytes** — observations that additionally pass bounded framing validation.

## Exact stream/generation binding starts on first seen observation

A `TuyaCandidateFragmentReassembler` is one exact value stream and one continuity generation. That invariant begins with the first **seen** observation, not the first successfully framed packet zero.

If the first observation later fails framing:

- its exact `streamIdentity` and `continuityGeneration` remain the reassembler's source binding;
- a callback from another stream fails `.streamChanged` before receipt chronology mutates;
- a callback from another continuity generation fails `.continuityGenerationChanged` before receipt chronology mutates;
- a genuinely newer/same-tick admissible callback from the originally selected stream/generation may still recover the candidate according to the receipt-order policy.

This applies to both receipt-backed and legacy uptime-only ordering. It does not promote bytes from the malformed callback: source identity is transport provenance, while candidate message state remains committed only after framing succeeds.

The transcript layer intentionally creates a fresh reassembler at real stream/generation boundaries while retaining transcript-wide receipt chronology separately.

## Sequence identity is scoped evidence

Nembra passive capture does not define a bare process-global sequence. `PassiveBluetoothCaptureSession` carries an immutable session ID, and records inside that session enforce strictly increasing sequence plus nondecreasing uptime. A device reboot starts a new capture session because the boot-relative uptime clock resets.

That means a numeric sequence is meaningful only inside the counter epoch that minted it. Two unrelated captures can both contain sequence `40`; the number alone cannot prove those callbacks share one order domain.

`TuyaCandidateFragmentObservation` therefore supports exactly two ordering forms:

1. legacy uptime-only evidence: both `receiptSequenceNumber` and `receiptSequenceScope` are absent;
2. receipt-backed evidence: both fields are present, where `receiptSequenceScope` is the opaque identity of the source-owned counter epoch and `receiptSequenceNumber` is immutable callback order inside it.

A scope without a sequence is invalid. A sequence without a scope is invalid. Blank scope identity is invalid. Receipt ordering authority and receipt scope bind on the first **seen** observation, even if that observation later fails framing. A different scope therefore fails closed before selected sequence or uptime watermarks mutate. A completed candidate retains the accepted scope plus its first/last accepted sequence numbers.

For Nembra's passive-capture bridge, the correct source scope is the exact immutable capture session ID. A display/model string, peripheral name, wall-clock timestamp, or inferred epoch must not replace it. The scope is deliberately **non-secret provenance identity**: never place a Tuya local key, token, session secret, credential, or other authentication material in this field.

## Two explicit ordering modes

### Receipt-backed mode

When the first observation carries the required sequence + scope pair:

- receipt ordering authority cannot switch back to legacy uptime-only order;
- sequence scope must remain identical;
- sequence must increase strictly;
- uptime must be nondecreasing, so distinct callbacks may share one real clock tick;
- no timestamp precision is synthesized;
- highest seen sequence is consumed before later uptime/framing validation;
- a newer callback rejected for backward uptime or framing cannot later be replaced by older/delayed callback evidence;
- a rejected receipt identity cannot be retried with rewritten uptime;
- a foreign scope is rejected before selected-scope chronology changes;
- completed candidates preserve scope plus first and last accepted sequence numbers as provenance.

Sequence is callback-order evidence only. It is not packet meaning, protocol sequence, vehicle state, or physical timing cadence.

### Legacy uptime-only mode

When the first observation carries neither sequence field:

- uptime is the only ordering authority and must increase strictly across **seen observations**, not only accepted fragments;
- each admissible new uptime high-water is consumed before packet framing validation;
- a newer malformed/rejected callback therefore blocks delayed older evidence;
- equal uptime is rejected because no stronger receipt sequence exists to prove order;
- legacy producers are not silently assigned synthetic receipt identities or timestamp precision.

A transcript or candidate cannot switch between receipt-backed and legacy ordering. Mixed authority fails closed rather than silently changing chronology rules, including when a seen observation later fails framing.

## Why rejected callbacks consume source chronology

An immutable scoped receipt sequence identifies one raw acquisition callback. Once sequence `12` has been seen in that scope, later receipt `11` is stale even if callback `12` fails packet-index, length, or other framing checks.

Legacy uptime-only evidence follows the same no-rewrite principle with the weaker authority it has: once uptime `300` is seen and admitted as newer than the previous high-water, a later uptime `200` is stale even if the callback at `300` failed framing.

A rejected callback does not enter the reconstructed encrypted message, but it cannot disappear from source order and reopen the past. Rejection must not promote bad semantic evidence, while immutable/source-owned transport chronology must not be rewritten to make a later parse convenient.

## Stream, continuity, and sequence scope are distinct

Exact stream identity and continuity generation are classified before receipt chronology admission.

A real stream/generation boundary remains explicit transcript evidence before the next observation is evaluated against transcript-wide receipt chronology. Inside an individual reassembler, a foreign stream/generation fails before that reassembler's receipt chronology mutates.

Sequence scope is a different dimension:

- sequence scope answers **which counter epoch owns this receipt sequence**;
- stream identity answers **which exact GATT value stream produced the bytes**;
- continuity generation answers **whether byte continuity is known across observations**.

None substitutes for another.

## Transcript-wide composition after packet-zero restart

Merged #310 established same-stream packet-zero restart recovery on `main`: an admitted packet-zero observation can preserve an unfinished candidate as `.candidatePacketZeroRestart` and then seed the next candidate without dropping or synthesizing that immutable observation.

This recovery lane composes scoped receipt chronology above that framing recovery. The transcript owns a receipt high-water for the whole supplied transcript rather than resetting it when a candidate completes, rejects, restarts, or crosses a transport boundary.

The enforced precedence is:

1. **real stream / continuity-generation boundary** — preserve the unfinished prior candidate as explicit boundary evidence and reset only candidate framing state;
2. **transcript receipt chronology** — require the already-selected receipt authority/scope and reject stale, replayed, or clock-invalid evidence before restart/framing;
3. **same-stream candidate packet-zero restart** — only a chronology-admitted packet zero may truncate the unfinished candidate and seed a new one;
4. **bounded candidate framing** — packet index, declared length, fragment count, assembled length, and other candidate-family framing checks.

This means:

- receipt-backed transcript chronology keeps one scope, strict sequence, and nondecreasing uptime;
- legacy transcript chronology keeps strict **seen** uptime;
- rejected newer receipts consume source chronology without promoting candidate bytes;
- receipt authority does not reset merely because one candidate completes or fails;
- real stream/generation boundaries remain stronger than packet-zero restart;
- receipt chronology remains stronger than packet-zero restart, so stale/replayed packet zero cannot manufacture a new candidate;
- an increasing scoped sequence may legitimately restart on the same real uptime tick without synthetic timestamp precision;
- a scoped callback rejected for backward uptime consumes its immutable sequence, so the same sequence cannot be replayed with a rewritten timestamp.

The direct `TuyaCandidateFragmentReassembler` deliberately remains self-defending when used without the transcript analyzer. The transcript adds the wider high-water needed across multiple candidate instances; focused regressions keep both surfaces on the same receipt-order contract.

## Downstream passive-capture bridge handoff

The passive-capture-to-Tuya bridge must preserve original acquisition provenance. The required mapping is:

- original capture `sequenceNumber` -> analyzer `receiptSequenceNumber`;
- exact immutable capture `session.id` -> analyzer `receiptSequenceScope`.

It must not renumber filtered fragments, infer order from wall-clock dates, manufacture timestamps, or replace the session ID with a display/model string.

That bridge remains a software evidence path until real ES80 passive capture proves the physical stream identity and candidate-family correlation.

## Focused regression coverage

Direct reassembler regressions cover:

- receipt-backed callbacks at identical uptime;
- first/last receipt-sequence provenance;
- capture-scope provenance;
- foreign scope rejection before selected-scope chronology mutation;
- rejected first framing observation binding receipt scope;
- invalid scope/sequence pair construction;
- rejected newer receipt blocking delayed older evidence;
- backward uptime consuming newer receipt identity;
- recovery with a genuinely newer sequence at the preserved uptime floor;
- receipt-backed/legacy authority switching rejected in either direction;
- legacy equal-uptime rejection and rejected-callback high-water;
- first-seen exact stream/generation binding before framing.

Transcript composition regressions additionally cover:

- equal-tick scoped callbacks across completed candidates;
- rejected newer scoped receipt consuming transcript sequence high-water;
- foreign scope rejection without poisoning the selected chronology;
- ordering authority persistence across candidate completion;
- equal-tick scoped packet-zero restart preserving the exact admitted observation;
- backward uptime consuming scoped sequence before restart classification;
- real continuity boundary classification before chronology rejection;
- legacy strict seen-uptime compatibility across candidates.

Inherited merged #310 regressions continue to cover restart preservation, malformed restart chronology, boundary precedence, and legacy non-monotonic restart rejection.

Repository-native exact-head QA remains the acceptance gate for the final branch head. A queued or skipped workflow is not green.

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
