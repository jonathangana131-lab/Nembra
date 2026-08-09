# Battery Evidence Stream Ordering

Status: software ordering/continuity contract. No physical AOVOPRO ES80 battery source, cadence, packet grouping, or reconnect behavior is verified by this slice.

## Purpose

`BatteryEvidenceObservation` already separates semantic value, truth role, process-local receipt uptime, wall-clock metadata, and continuity. The stream layer must also prevent an out-of-order callback from replacing a newer ordering baseline or silently bridge an interval that Nembra knows it did not observe.

`BatteryEvidenceStreamValidator` provides that narrow stateful boundary.

## Ordering rule

Inside one known uptime epoch:

- receipt uptime may stay equal;
- receipt uptime may increase;
- receipt uptime may not decrease.

Equal uptime is deliberately valid because one received transport packet/callback may eventually decode into several normalized battery fields such as SoC, voltage, current, and power. The domain does not invent an ordering distinction that the source evidence did not provide.

Wall-clock `Date` is metadata only. System time can move while the app runs, so an earlier/later wall-clock value cannot repair or invalidate process-local monotonic ordering.

## Continuity boundary

`markUnobservedInterval()` is used when a higher layer knows battery evidence continuity has been lost before a post-gap observation arrives.

It:

- discards the previous uptime baseline;
- requires the next accepted observation to carry `.afterUnobservedInterval`;
- prevents a caller from accidentally continuing a battery-consumption window across the missing interval.

An observation already marked `.afterUnobservedInterval` may also reset the stream baseline conservatively even if `markUnobservedInterval()` was not called first. This is useful after process relaunch or another explicit evidence boundary where the new uptime epoch may be numerically lower than the old one.

After that boundary, ordinary nondecreasing uptime validation resumes in the new epoch.

## Atomic failure

Rejected observations do not mutate the last accepted ordering baseline or clear the pending continuity-boundary requirement. A later valid observation can therefore continue from the last truthful state.

## Truth-role independence

Stream ordering never changes `BatteryEvidenceRole`.

A stock-app correlation anchor that is perfectly ordered remains only a stock-app correlation anchor. A simulation fixture remains simulation evidence. A presentation estimate remains presentation/derived evidence. Ordering quality is not physical-protocol verification.

Likewise, a verified SoC observation being individually eligible for adaptive range does not mean a range-learning window may bridge a continuity boundary. The adaptive-range layer must continue rejecting missing/gapped evidence.

## Why the validator is not persisted

Receipt uptime is process/boot-epoch evidence. Persisting the validator's raw ordering baseline across launches would create a false comparison between unrelated uptime epochs.

Durable battery/range state may persist semantic evidence and learned results where its own schema permits, but a new process must establish a fresh stream baseline. If there was an unobserved interval, the first post-gap observation must remain explicitly classified as such.

## Not included

This slice does not:

- identify ES80 battery BLE/Tuya fields;
- determine real packet grouping or native cadence;
- infer transport gaps from guessed timing thresholds;
- define reconnect/background behavior;
- calculate SoC from voltage;
- integrate energy;
- teach adaptive range directly;
- change Home/Dashboard presentation;
- authorize any motorized-hardware write.
