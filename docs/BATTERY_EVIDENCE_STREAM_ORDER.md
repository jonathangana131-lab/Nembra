# Battery Evidence Stream Ordering

Status: software receipt-order/continuity contract. No physical AOVOPRO ES80 battery source, cadence, packet grouping, reconnect behavior, or field mapping is verified by this slice.

## Purpose

`BatteryEvidenceObservation` separates semantic value, truth role, process-local callback receipt identity, receipt uptime, wall-clock metadata, and continuity. The stream layer must prevent delayed callbacks from replacing newer evidence or silently bridging an interval Nembra knows it did not observe.

Bare uptime is insufficient: one callback may produce several semantic fields, while two distinct callbacks can land in the same monotonic clock tick. `BatteryEvidenceStreamValidator` therefore uses receipt identity as callback order and uptime as a separate chronology constraint.

## Receipt identity

One live receipt is identified by:

- an acquisition epoch UUID;
- a strict `UInt64` sequence number inside that epoch.

The identity is minted before async semantic normalization/reordering. Sibling fields from one callback share the identity, uptime, and continuity metadata. Distinct callbacks receive strictly newer sequence numbers even if their uptime values are equal.

The identity is process-local and non-Codable. Generic imported observations are receipt-unbound and cannot enter the live ordered stream merely because their serialized payload contains plausible time or a forged receipt-shaped object.

Receipt identity is ordering evidence, **not** physical authority. Stream validation never promotes `BatteryEvidenceRole`.

## Ordering rule

Inside one validator/acquisition epoch:

1. the first accepted observation establishes the receipt and uptime baseline;
2. observations with the **same receipt identity** are accepted as sibling/idempotent stream events only when receipt uptime and continuity metadata exactly match the already-accepted receipt;
3. a distinct receipt must have a **strictly greater sequence number**;
4. a newer receipt's uptime may stay equal or increase, but may not decrease;
5. a lower sequence is stale even if its uptime is numerically newer;
6. a different acquisition epoch is rejected by an existing validator and requires a fresh validator.

This gives the two clocks different jobs:

- receipt sequence decides callback freshness/order;
- monotonic uptime constrains chronology and later supports age/freshness policy.

Equal uptime never means “same callback.” Wall-clock `Date` remains metadata only and is not used to repair ordering.

Field-level duplicate/conflict semantics belong to the snapshot accumulator. The stream validator only proves receipt order/metadata; it may accept multiple semantic fields sharing one receipt.

## Continuity boundary

`markUnobservedInterval()` records that evidence continuity is no longer known. It retains the prior receipt and uptime baselines and sets `requiresContinuityBoundary`.

The first post-gap acceptance must then:

- come from the same acquisition epoch;
- carry a **strictly newer receipt sequence** than the pre-gap receipt;
- use nondecreasing uptime;
- carry `.afterUnobservedInterval`.

The same pre-gap receipt cannot satisfy the boundary, even if replayed with changed continuity metadata. A lower/old receipt cannot satisfy it. Failure is atomic: the prior baseline and pending-boundary requirement remain intact.

A strictly newer boundary receipt may legitimately have the **same uptime** as the pre-gap receipt. This is the key distinction from the older uptime-only contract.

An observation already marked `.afterUnobservedInterval` may establish a conservative new segment even when the caller did not first call `markUnobservedInterval()`, provided normal receipt/uptime ordering is valid.

## Same-receipt consistency

All sibling semantic observations from one receipt must carry the same receipt metadata. Reusing one identity with a different uptime or continuity value fails `inconsistentReceiptMetadata` without state mutation.

After the first sibling of a post-gap receipt clears the pending boundary, later siblings with that same receipt and the same `.afterUnobservedInterval` metadata remain valid. Changing a sibling to `.continuous` would be inconsistent and fail closed.

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

A generic public/imported observation intentionally has no live receipt identity. Passing it to the stream validator fails `missingReceiptIdentity` without changing state.

That does not make the observation invalid for research/history presentation; it means only that it cannot claim membership in the current live callback stream.

## Atomic failure

Rejected observations do not mutate:

- `lastAcceptedReceiptIdentity`;
- `lastAcceptedUptimeNanoseconds`;
- same-receipt metadata baseline;
- `requiresContinuityBoundary`.

A later valid observation can continue from the last truthful state.

## Downstream reconciliation contract

Dependent battery/range slices must migrate from uptime-as-identity to receipt identity:

- snapshot duplicate/coalescing keys use field + receipt identity, not field + uptime;
- continuity-reset coalescing uses receipt identity;
- freshness/availability keeps using uptime as the age clock;
- range SoC ordering uses strictly newer receipt sequence with nondecreasing uptime;
- a derived live range must stay bound to the current accepted SoC receipt identity;
- a new acquisition epoch resets ephemeral current-segment/range binding rather than bridging across epochs.

No child implementation is silently changed by this parent slice; each dependent lane still requires its own review/tests.

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
