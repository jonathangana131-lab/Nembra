# Adaptive Range Learning Window Assembly

Status: software evidence-assembly contract. Depends on the adaptive range core in PR #10. It does **not** establish physical AOVOPRO ES80 battery or distance semantics.

## Purpose

`AdaptiveBatteryRangeModel` intentionally accepts only already-classified `BatteryRangeLearningWindow` evidence. This slice supplies the missing ephemeral assembly layer that turns a sequence of normalized battery anchors plus caller-classified distance/continuity evidence into those candidates.

It does not decide where evidence comes from.

The higher layer remains responsible for proving whether a value is:
- authoritative measured SoC versus estimated/display SoC;
- complete/partial/unknown distance evidence;
- affected by a scooter transport gap;
- appropriate for the currently selected physical scooter.

## Window behavior

The assembler starts a span only from an authoritative measured SoC anchor.

Estimated/display SoC:
- is representable elsewhere for presentation;
- never starts a learning span;
- never advances a learning anchor;
- never clears accumulated measured evidence.

A flat authoritative percentage keeps the original anchor. This is important for a battery source that may be coarse or slow: real distance can continue accumulating while the displayed measured percentage remains unchanged.

A lower authoritative percentage becomes eligible to close a window only after **both** minimum thresholds from the active `AdaptiveBatteryRangePolicy` are met:
- minimum percentage points consumed;
- minimum real distance.

This prevents a stream such as `80 → 79 → 78 → 77` from automatically becoming three tiny 1% training samples. One longer window can form from the earlier authoritative anchor instead.

The policy supplied to the current authoritative reading is the live threshold source. Tightening does not retroactively close a span under an older looser threshold, while loosening may legitimately close an already-retained span on a later authoritative reading, including a flat percentage update.

A higher authoritative percentage conservatively rebases the span and discards its in-flight distance evidence. The assembler does not decide whether the rise was charging, sag recovery, firmware filtering, or another effect. It simply refuses to relabel a non-consumption change as consumed battery.

## Distance evidence

`recordDistance(deltaMeters:coverage:)` accepts only finite nonnegative distance.

The assembler never decides whether that distance came from:
- scooter odometer;
- quality-screened GPS;
- a future reconciled ride-distance source;
- another legitimate source.

Coverage degrades monotonically inside a span:

`complete → partial → unknown`

Once evidence becomes partial or unknown, later complete deltas cannot repair the missing interval. The candidate preserves that classification so `AdaptiveBatteryRangeModel` can reject it.

A zero distance delta is valid. It may be used to degrade coverage without inventing distance.

## Transport continuity

`recordTransportGap()` marks the current span as having observed a scooter-transport continuity break. The flag is sticky until that span closes, rebases, or is explicitly reset.

The assembler preserves this evidence rather than smoothing it away. `AdaptiveBatteryRangeModel` remains responsible for rejecting transport-gap windows. Once such a candidate closes, the assembler rebases at its end reading so a rejected tainted span does not permanently poison later clean evidence.

There are two distinct higher-layer situations:

1. **A gap was discovered inside an already-active span and the pre/post-gap evidence must remain auditable together.** Mark that span with `recordTransportGap()`; any emitted candidate preserves the gap and the model rejects it.
2. **The higher layer knows the first trustworthy post-gap authoritative SoC reading and cannot prove continuity across the missing interval.** Discard the old in-flight span with `reset()`, then ingest that first post-gap authoritative reading as the new anchor before recording new distance. Do not carry pre-gap distance into the new span merely to save a sample.

This distinction lets a future battery/transport integration honor an explicit "after unobserved interval" signal without fabricating continuity or needlessly contaminating later clean distance.

## Atomic failure behavior

The assembler rejects:
- negative/nonfinite distance deltas;
- accumulated distance overflow;
- nonmonotonic authoritative SoC anchors.

Those errors occur before mutating the in-flight span.

## Lifecycle

The assembler is ephemeral evidence state. It should be reset at an explicit ride/device/session boundary when a higher layer can no longer prove continuity of the in-flight span.

A reset intentionally loses only the uncommitted learning candidate. The first subsequent authoritative SoC reading becomes a fresh anchor; distance before that anchor is not retroactively assigned a battery-consumption start value.

Persisted learned efficiency remains owned by `AdaptiveBatteryRangeModel` and its persistence layer. This assembler does not introduce another learned-history store.

## Explicit non-goals

This slice does not:
- decode raw ES80 BLE/Tuya battery data;
- prove 1% physical battery resolution;
- choose ES80 distance or identity semantics;
- infer reconnect behavior;
- persist per-scooter learning identity;
- integrate current, watts, watt-hours, or Wh/mi;
- modify Home/Dashboard presentation;
- send any motorized-hardware write.

The physical ES80 must still establish battery source, cadence, quantization, load/recovery behavior, distance source quality, continuity behavior, and stable per-scooter identity before production learning is hardware-validated.
