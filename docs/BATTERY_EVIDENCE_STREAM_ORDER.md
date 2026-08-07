# Battery Evidence Stream Ordering

Status: software receipt-order/continuity contract. No physical AOVOPRO ES80 battery source, cadence, packet grouping, reconnect behavior, or field mapping is verified by this slice.

## Purpose

`BatteryEvidenceObservation` separates semantic value, truth role, process-local callback receipt identity, receipt uptime, wall-clock metadata, and continuity. The stream layer must prevent delayed callbacks from replacing newer evidence or silently bridging an interval Nembra knows it did not observe.

Bare uptime is insufficient: one callback may produce several semantic fields, while two distinct callbacks can land in the same monotonic clock tick. `BatteryEvidenceStreamValidator` therefore uses receipt identity as callback order and uptime as a separate chronology constraint.

The validator deliberately keeps two concepts separate:

- **seen callback chronology**: which immutable raw receipt identities have already arrived, including a newer receipt whose semantic observation later fails admission;
- **accepted semantic evidence**: the newest receipt whose normalized observation actually satisfied ordering, uptime, and continuity requirements.

A rejected semantic observation never becomes battery truth. It also does not erase the fact that its raw callback occurred.

## Receipt identity

One live receipt is identified by:

- an acquisition epoch UUID;
- a strict `UInt64` sequence number inside that epoch.

The identity is minted before async semantic normalization/reordering. Sibling fields from one callback share the identity, uptime, and continuity metadata. Distinct callbacks receive strictly newer sequence numbers even if their uptime values are equal.

The identity is process-local and non-Codable. Generic imported observations are receipt-unbound and cannot enter the live ordered stream merely because their serialized payload contains plausible time or a forged receipt-shaped object.

Receipt identity is ordering evidence, **not** physical authority. Stream validation never promotes `BatteryEvidenceRole`.

## Ordering rule

Inside one validator/acquisition epoch:

1. the first identified raw receipt establishes the seen callback sequence and monotonic uptime floor; it establishes the accepted baseline only if the observation also passes semantic stream admission;
2. observations with the **same receipt identity** are accepted as sibling/idempotent stream events only when that receipt was already accepted and its uptime/continuity metadata exactly match the immutable metadata first seen for that receipt;
3. a distinct receipt must have a **strictly greater sequence number than the last seen receipt**, not merely the last accepted receipt;
4. a newer receipt's uptime may stay equal or increase relative to the greatest valid seen uptime, but may not decrease;
5. a backward-uptime receipt still consumes its newer sequence identity but cannot lower the future uptime floor or become accepted evidence;
6. a lower sequence is stale even if its uptime is numerically newer;
7. a different acquisition epoch is rejected by an existing validator and requires a fresh validator.

This gives the two clocks different jobs:

- receipt sequence decides raw callback freshness/order;
- monotonic uptime constrains chronology and later supports age/freshness policy.

Equal uptime never means “same callback.” Wall-clock `Date` remains metadata only and is not used to repair ordering.

Field-level duplicate/conflict semantics belong to the snapshot accumulator. The stream validator only proves receipt order/metadata; it may accept multiple semantic fields sharing one already-accepted receipt.

## Why rejected callbacks still affect chronology

Receipt identity is minted at the trusted serialized acquisition boundary before semantic normalization fans out. Once receipt 22 has been observed, a delayed receipt 21 is older raw callback evidence even if receipt 22's normalized battery observation was rejected.

For example:

1. receipt 20 is accepted at uptime `200`;
2. receipt 22 arrives at uptime `199` and fails `nonMonotonicUptime`;
3. delayed receipt 21 arrives at uptime `201`.

Step 3 still fails `staleReceiptIdentity` because receipt 22 already proved that callback sequence 21 is old. Receipt 22's battery value remains unaccepted, while its sequence identity remains part of callback-order evidence.

Likewise, receipt 22 cannot later be retried with a different uptime or continuity marker. One `(epoch, sequence)` pair identifies one immutable raw callback, not a slot whose metadata may be edited until validation passes.

## Monotonic seen-uptime floor

The validator preserves both the exact uptime attached to the highest seen receipt and a separate nondecreasing uptime floor.

This matters when rejected callbacks have different failure reasons. Suppose a pending continuity gap exists:

1. accepted receipt 20 is at uptime `200`;
2. receipt 21 arrives at uptime `300` but omits `.afterUnobservedInterval`, so its semantic observation is rejected;
3. receipt 22 arrives at uptime `250` with the correct boundary marker.

Receipt 21 still established that a raw callback was observed at uptime `300`. Receipt 22 therefore fails `nonMonotonicUptime`; it cannot make process time move backward merely because receipt 21 failed a separate continuity rule. Receipt 22 consumes sequence identity but does not lower the `300` uptime floor. A later receipt must use uptime `300` or newer.

Conversely, a callback already below the existing uptime floor cannot raise or lower that floor. A genuinely newer receipt at the existing floor may recover if all remaining admission rules pass.

## Continuity boundary

`markUnobservedInterval()` records that evidence continuity is no longer known. It retains the prior accepted baseline, seen receipt watermark, monotonic uptime floor, and sets `requiresContinuityBoundary`.

The first post-gap **acceptance** must then:

- come from the same acquisition epoch;
- carry a **strictly newer receipt sequence than every already-seen receipt**;
- use uptime at or above the preserved seen-uptime floor;
- carry `.afterUnobservedInterval`.

The same pre-gap receipt cannot satisfy the boundary, even if replayed with changed continuity metadata. A lower/old receipt cannot satisfy it.

A newer receipt that omits the required boundary is rejected as semantic evidence, but its immutable callback identity remains seen. If its uptime is nondecreasing, that uptime also remains part of the monotonic seen floor. The caller must wait for a **genuinely newer receipt** carrying the boundary; it may not rewrite the rejected receipt's continuity metadata and retry it.

A strictly newer boundary receipt may legitimately have the **same uptime** as the preserved floor. This is the key distinction from the older uptime-only contract.

An observation already marked `.afterUnobservedInterval` may establish a conservative new segment even when the caller did not first call `markUnobservedInterval()`, provided normal receipt/uptime ordering is valid.

## Same-receipt consistency

All semantic observations from one receipt must carry the same immutable receipt metadata first seen for that identity. Reusing one identity with a different uptime or continuity value fails `inconsistentReceiptMetadata`.

Sibling fields are accepted only when that same receipt was already admitted. A receipt first seen through a rejected observation is consumed for chronology and cannot later become accepted through either an identical retry or altered metadata.

After the first sibling of a valid post-gap receipt clears the pending boundary, later siblings with that same receipt and the same `.afterUnobservedInterval` metadata remain valid. Changing a sibling to `.continuous` is inconsistent and fails closed.

## Acquisition epoch lifecycle

A validator represents exactly one acquisition epoch. It never accepts an epoch switch in-place, regardless of wall clock, uptime, continuity tag, or sequence number.

A genuine process/acquisition restart creates:

- a fresh receipt sequencer with a new epoch;
- a fresh `BatteryEvidenceStreamValidator`.

That fresh validator may establish a low uptime/low sequence baseline because it has no relationship to the old epoch. Durable state must not compare unrelated process-local receipt identities as if they were one continuous stream.

## Delayed pre-gap replay example

Consider one acquisition epoch:

1. receipt 40 / voltage is accepted at uptime `900`;
2. a known unobserved interval is marked;
3. receipt 41 / SoC arrives as `.afterUnobservedInterval` at the **same uptime `900`** and is accepted;
4. delayed receipt 40 / voltage arrives again later.

Step 4 fails `staleReceiptIdentity` even though its uptime equals the current baseline. The older callback cannot re-enter a current-segment snapshot or adaptive-range consumer.

This is stronger than an uptime-only rule, which cannot distinguish steps 3 and 4 when both expose the same clock tick.

## Missing receipt identity

A generic public/imported observation intentionally has no live receipt identity. Passing it to the stream validator fails `missingReceiptIdentity` without changing seen or accepted stream state.

That does not make the observation invalid for research/history presentation; it means only that it cannot claim membership in the current live callback stream.

## Rejection-state contract

Rejected observations never promote their semantic value and never clear `requiresContinuityBoundary`.

They do **not** all have identical mutation behavior, because raw callback chronology is itself evidence:

- missing receipt identity, foreign acquisition epoch, lower/stale sequence, and same-receipt metadata mismatch fail before advancing the seen callback watermark;
- a genuinely newer same-epoch receipt advances `lastSeenReceiptIdentity` and stores that receipt's exact immutable metadata before later admission checks;
- if that new receipt is below the monotonic uptime floor, it fails `nonMonotonicUptime` and does not lower the floor;
- if its uptime is nondecreasing, it advances the monotonic seen-uptime floor even if a later continuity requirement rejects the semantic observation;
- `lastAcceptedReceiptIdentity` and `lastAcceptedUptimeNanoseconds` change only after the full stream admission succeeds.

This separation is intentional: a bad battery observation must not become truth, while a trusted newer callback must not disappear in a way that lets delayed older evidence masquerade as fresh.

## Downstream reconciliation contract

Dependent battery/range slices must migrate from uptime-as-identity to receipt identity and consume **validator-accepted** semantic evidence:

- snapshot duplicate/coalescing keys use field + receipt identity, not field + uptime;
- continuity-reset coalescing uses receipt identity;
- freshness/availability keeps using accepted uptime as the age clock;
- range SoC ordering uses accepted receipt identity after stream validation rather than reimplementing a weaker last-accepted-only callback gate;
- a derived live range must stay bound to the current accepted SoC receipt identity;
- a new acquisition epoch resets ephemeral current-segment/range binding rather than bridging across epochs.

No child implementation is silently changed by this parent/recovery slice; each dependent lane still requires its own review/tests.

## Why validator/receipt identity are not persisted

Receipt identity describes process-local callback order. Persisting it as a generic trust token would let retained/imported data masquerade as current after restart. `BatteryEvidenceReceiptIdentity` is therefore non-Codable, the observation codec omits it, verified authority cannot use generic Codable, and the validator is not persisted.

Durable learned range/history may persist only through their own evidence-aware schemas. On launch/reacquisition, current battery truth starts with a new acquisition epoch and new validator.

## Not included

This slice does not:

- identify ES80 battery BLE/Tuya fields;
- determine real packet grouping or native cadence;
- infer gaps from guessed timing thresholds;
- define reconnect/background behavior;
- persist/restore process-local receipt identity or validator state;
- calculate SoC from voltage;
- integrate energy;
- teach adaptive range directly;
- change Home/Dashboard presentation;
- authorize any motorized-hardware write.
