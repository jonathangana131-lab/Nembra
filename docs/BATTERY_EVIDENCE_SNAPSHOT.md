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

## Construction boundary follows both Nembra build graphs

`BatteryEvidenceCurrentSegmentSnapshot` is public as a read-only output type, but production raw-dictionary construction is **file-scoped** to `BatteryEvidenceSnapshotAccumulator.swift`.

That is intentionally stronger than ordinary module-internal access. The current iOS project may manually compile selected NembraCore package-domain source files directly into the `Nembra` app target. In that composition, plain `internal` would also be callable by unrelated app source files and could let them manufacture a fake "current segment" without stream/continuity validation.

The source therefore has two explicit paths:

- direct app-source compilation: raw aggregate construction stays file-scoped; the production path is `BatteryEvidenceSnapshotAccumulator.currentSnapshot`;
- real Swift-package compilation (`SWIFT_PACKAGE`): an internal fixture initializer remains available to NembraCore `@testable` and dependent package-domain tests, while external package clients still cannot call it.

A direct same-module compile probe without `SWIFT_PACKAGE` fails when it tries the raw current-segment initializer. The same package-fixture spelling compiles with `SWIFT_PACKAGE`. This is supplemental software evidence, not hosted acceptance or physical ES80 proof.

## Current-segment semantics

The accumulator keeps at most one latest observation per `BatteryEvidenceField` inside the current uninterrupted evidence segment.

It composes the process-local `BatteryEvidenceStreamValidator`, so:

- uptime may remain equal for several fields decoded from one source callback;
- uptime may increase;
- backwards continuous uptime is rejected;
- wall-clock movement is irrelevant to ordering;
- explicit continuity boundaries create a fresh segment.

The accumulator does not claim that several same-uptime fields physically came from one ES80 packet. Equal uptime only means the source boundary did not provide a finer process-local ordering distinction.

## Gap behavior

When a higher layer calls `markUnobservedInterval()`:

- the current live snapshot is cleared immediately;
- the stream requires explicit post-gap continuity evidence before accepting ordinary continuous evidence again;
- prior segment fields cannot leak into the fresh segment.

A spontaneous explicit `.afterUnobservedInterval` observation also starts a fresh segment conservatively. This supports process relaunch or another explicit evidence boundary where the new uptime epoch may restart at a lower number.

Historical/retained presentation is a separate concern. Clearing this current-segment accumulator does not require deleting durable history; it only prevents stale values from masquerading as current live evidence.

## Multi-field post-gap boundary batches

One source callback may eventually decode into several normalized fields. If that first callback follows an unobserved interval, each normalized field may legitimately inherit `.afterUnobservedInterval` with the **same receipt uptime**.

The accumulator therefore treats same-uptime explicit boundary observations as one post-gap boundary batch:

- the first genuinely new boundary observation clears the old segment;
- additional different fields carrying the same boundary uptime join that fresh segment instead of clearing one another;
- replaying an already accepted boundary observation is idempotent and does not erase other same-uptime fields;
- once accepted evidence advances to a greater uptime, that boundary batch closes;
- a later explicit boundary can then start another fresh segment, including one whose new uptime epoch is numerically lower;
- `markUnobservedInterval()` always closes any open boundary batch and clears the current segment immediately.

Without a separate sequence identifier, two spontaneous distinct gaps that somehow present the exact same receipt uptime cannot be distinguished from one multi-field boundary batch. The model does not invent a sequence fact that the evidence lacks. A higher layer that actually knows another gap occurred must call `markUnobservedInterval()`.

## Same-field ambiguity and replay ordering

Different fields may legitimately share one receipt uptime.

For the **same field** at the exact same uptime:

- an exact duplicate observation is globally idempotent;
- a conflicting value/role/timestamp shape is rejected rather than arbitrarily choosing whichever callback happened to be processed last.

Exact duplicate detection happens before stream-validator mutation. This is required because replaying an older retained field after newer evidence arrived must not rewind the process-local ordering baseline. Focused regressions also prove that a later genuinely new lower-uptime field remains rejected after such a replay.

Without an additional sequence identifier, choosing between conflicting same-field same-uptime observations would manufacture an ordering fact that does not exist.

## Atomicity

Stream-order failures and same-uptime field conflicts do not partially mutate the snapshot or ordering baseline. The previous coherent snapshot survives intact.

## Truth roles remain intact

Snapshot retention never promotes evidence.

- stock-app correlation anchors remain correlation anchors;
- simulation fixtures remain simulation evidence;
- derived/presentation values remain non-measured;
- only already-verified vehicle measurements can satisfy the authoritative measurement gates defined by the parent battery evidence domain.

This accumulator therefore supports future battery consumers without creating a shortcut around physical ES80 verification.

## Not included

This slice does not:

- decode ES80 BLE/Tuya packets;
- establish physical packet grouping;
- establish field cadence or staleness thresholds;
- infer a gap from elapsed time;
- choose which fields are user-facing;
- convert voltage to SoC;
- integrate current/power into energy or Wh/mi;
- bridge into the adaptive-range model;
- persist current-process ordering state;
- wire app UI;
- authorize motorized-hardware writes.
