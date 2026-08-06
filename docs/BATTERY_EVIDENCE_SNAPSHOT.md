# Coherent Battery Evidence Snapshot

Status: software-only current-segment aggregation. No physical AOVOPRO ES80 telemetry semantics, native cadence, packet grouping, or reconnect behavior is verified by this slice.

## Purpose

Once Nembra can represent normalized battery evidence truthfully, it still must avoid a subtler failure: combining fields from different evidence-continuity segments and presenting them as one live battery state.

Example of what must not happen:

1. before a disconnect, Nembra last saw 39.2 V and 4.1 A;
2. an unobserved interval occurs;
3. after reconnect, only a fresh 54% SoC arrives;
4. UI incorrectly shows `54% · 39.2 V · 4.1 A` as though all three values were live together.

`BatteryEvidenceSnapshotAccumulator` prevents that class of stale/fresh mixing.

## Current-segment semantics

The accumulator keeps at most one latest observation per `BatteryEvidenceField` inside the current uninterrupted evidence segment.

It composes the process-local `BatteryEvidenceStreamValidator`, so:

- uptime may remain equal for several fields decoded from one source callback;
- uptime may increase;
- backwards continuous uptime is rejected;
- wall-clock movement is irrelevant to ordering;
- explicit continuity boundaries create a fresh segment.

The accumulator does not decide that several same-uptime fields really came from one physical ES80 packet. Equal uptime is merely allowed because the software must not invent a finer ordering distinction than the source evidence provides.

## Gap behavior

When a higher layer calls `markUnobservedInterval()`:

- the current live snapshot is cleared immediately;
- the stream requires an explicit `.afterUnobservedInterval` observation before accepting ordinary continuous evidence again;
- prior segment fields cannot leak into the fresh segment.

A spontaneous explicit `.afterUnobservedInterval` observation also clears all prior current-segment fields conservatively. This supports process relaunch or another explicit evidence boundary where the new uptime epoch may restart at a lower number.

Historical/retained presentation is a separate concern. Clearing this current-segment accumulator does not require deleting durable history; it only prevents stale values from masquerading as current live evidence.

## Same-field ambiguity

Different fields may legitimately share one receipt uptime.

For the **same field** at the exact same uptime:

- an exact duplicate observation is idempotent;
- a conflicting value/role/timestamp shape is rejected rather than arbitrarily choosing whichever callback happened to be processed last.

Without an additional sequence identifier, choosing between conflicting same-field same-uptime observations would manufacture an ordering fact that does not exist.

## Atomicity

Stream-order failures and same-uptime field conflicts do not partially mutate the snapshot or ordering baseline. The previous coherent snapshot survives intact.

## Truth roles remain intact

Snapshot retention never promotes evidence.

- stock-app correlation anchors remain correlation anchors;
- simulation fixtures remain simulation evidence;
- derived/presentation values remain non-measured;
- only already-verified vehicle measurements can satisfy the authoritative measurement gates defined by the parent battery evidence domain.

This accumulator therefore supports a future Battery detail UI without creating a shortcut around physical ES80 verification.

## Not included

This slice does not:

- decode ES80 BLE/Tuya packets;
- establish field cadence or staleness thresholds;
- infer a gap from elapsed time;
- choose which fields are user-facing;
- convert voltage to SoC;
- integrate current/power into energy or Wh/mi;
- bridge into the adaptive-range model;
- persist current-process ordering state;
- wire app UI;
- authorize motorized-hardware writes.
