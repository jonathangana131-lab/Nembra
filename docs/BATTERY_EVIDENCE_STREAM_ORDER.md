# Battery Evidence Stream Ordering

Status: software ordering/continuity contract. No physical AOVOPRO ES80 battery source, cadence, packet grouping, or reconnect behavior is verified by this slice.

## Purpose

`BatteryEvidenceObservation` already separates semantic value, truth role, process-local receipt uptime, wall-clock metadata, and continuity. The stream layer must also prevent an out-of-order callback from replacing a newer ordering baseline or silently bridge an interval that Nembra knows it did not observe.

`BatteryEvidenceStreamValidator` provides that narrow stateful boundary.

## Ordering rule

Inside one validator's process/boot uptime epoch:

- receipt uptime may stay equal;
- receipt uptime may increase;
- receipt uptime may not decrease, including on an explicit continuity boundary.

Equal uptime is deliberately valid because one received transport packet/callback may eventually decode into several normalized battery fields such as SoC, voltage, current, and power. The domain does not invent an ordering distinction that the source evidence did not provide.

Wall-clock `Date` is metadata only. System time can move while the app runs, so an earlier/later wall-clock value cannot repair or invalidate process-local monotonic ordering.

## Continuity boundary

`markUnobservedInterval()` is used when a higher layer knows battery evidence continuity has been lost before a post-gap observation arrives.

It:

- retains the previous process-local uptime baseline;
- requires the next accepted observation to carry `.afterUnobservedInterval`;
- prevents a caller from accidentally continuing a battery-consumption window across the missing interval;
- prevents delayed pre-gap evidence from becoming current merely because a gap occurred.

An observation already marked `.afterUnobservedInterval` may also establish a conservative fresh continuity segment even if `markUnobservedInterval()` was not called first, but it still must not move an existing validator's uptime baseline backwards.

This distinction is intentional. A Bluetooth disconnect, missed callback interval, or reconnect does not reset system uptime. Allowing the same validator to jump from, for example, uptime `900` to boundary uptime `4` would make a delayed old observation at uptime `900` look newer than the boundary and would let stale pre-gap evidence re-enter a fresh segment.

A true process relaunch or boot-epoch change must create a **fresh `BatteryEvidenceStreamValidator`**. The validator is process-local and is not persisted. A fresh validator has no old baseline and may therefore establish the new process epoch at any legitimate first receipt uptime.

After an accepted boundary, ordinary nondecreasing uptime validation resumes in that same process epoch.

## Delayed pre-gap replay fails closed

Consider one process-local stream:

1. verified voltage is accepted at uptime `900`;
2. a known unobserved interval is marked;
3. the first post-gap boundary arrives at uptime `901`;
4. the old voltage observation at uptime `900` is delivered again later.

The retained baseline makes step 4 fail `nonMonotonicUptime`. It cannot be re-admitted into a current-segment snapshot or adaptive-range consumer merely because a continuity reset occurred.

If a caller presents a lower-uptime boundary while an existing validator still has a higher process-local baseline, that boundary also fails `nonMonotonicUptime` atomically. Cross-process uptime epochs are represented by validator lifetime, not by mutating one validator backwards in time.

## Atomic failure

Rejected observations do not mutate the last accepted ordering baseline or clear the pending continuity-boundary requirement. A later valid observation can therefore continue from the last truthful state.

A rejected lower-uptime boundary after `markUnobservedInterval()` leaves the prior baseline intact and leaves `requiresContinuityBoundary == true`. The caller must supply a valid same-epoch boundary or, after a real process relaunch, use a fresh validator.

## Truth-role independence

Stream ordering never changes `BatteryEvidenceRole`.

A stock-app correlation anchor that is perfectly ordered remains only a stock-app correlation anchor. A simulation fixture remains simulation evidence. A presentation estimate remains presentation/derived evidence. Ordering quality is not physical-protocol verification.

Likewise, a verified SoC observation being individually eligible for adaptive range does not mean a range-learning window may bridge a continuity boundary. The adaptive-range layer must continue rejecting missing/gapped evidence.

## Why the validator is not persisted

Receipt uptime is process/boot-epoch evidence. Persisting the validator's raw ordering baseline across launches would create a false comparison between unrelated uptime epochs.

Durable battery/range state may persist semantic evidence and learned results where its own schema permits, but a new process must create a fresh stream validator and establish a fresh baseline. Verified observation authority is also not restored through the generic Codable channel.

This lifecycle rule is what makes the retained-baseline continuity defense sound: one validator never represents two unrelated uptime epochs.

## Not included

This slice does not:

- identify ES80 battery BLE/Tuya fields;
- determine real packet grouping or native cadence;
- infer transport gaps from guessed timing thresholds;
- define reconnect/background behavior;
- persist or restore the process-local validator;
- calculate SoC from voltage;
- integrate energy;
- teach adaptive range directly;
- change Home/Dashboard presentation;
- authorize any motorized-hardware write.
