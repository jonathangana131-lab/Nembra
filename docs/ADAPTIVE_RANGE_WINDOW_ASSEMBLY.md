# Adaptive Range Learning Window Assembly

Status: software evidence-assembly contract. Depends on the adaptive range core in PR #10 / its coordinator-owned recovery. It does **not** establish physical AOVOPRO ES80 battery or distance semantics.

## Purpose

`AdaptiveBatteryRangeModel` intentionally accepts only already-classified `BatteryRangeLearningWindow` evidence. This slice supplies the missing ephemeral assembly layer that turns a sequence of normalized battery anchors plus caller-classified distance/continuity evidence into those candidates.

It does not decide where evidence comes from.

The higher layer remains responsible for proving whether a value is:
- authoritative measured SoC versus estimated/display SoC;
- complete/partial/unknown distance evidence;
- affected by a scooter transport gap;
- appropriate for the currently selected physical scooter.

## Window behavior

The assembler starts a span only from an authoritative measured SoC anchor. It separately remembers the **latest accepted authoritative reading** inside that span.

Estimated/display SoC:
- is representable elsewhere for presentation;
- never starts a learning span;
- never advances the latest authoritative measurement;
- never triggers measured-recovery rebasing, even if its percentage is higher;
- never constrains authoritative ordering, even if its presentation timestamp is later;
- never clears accumulated measured evidence.

A flat or falling authoritative percentage keeps the original span anchor. This is important for a battery source that may be coarse or slow: real distance can continue accumulating while measured percentage remains unchanged or falls in small steps.

A lower authoritative percentage becomes eligible to close a window only after **both** minimum thresholds from the active `AdaptiveBatteryRangePolicy` are met:
- minimum percentage points consumed from the span anchor;
- minimum real distance.

This prevents a stream such as `80 → 79 → 78 → 77` from automatically becoming three tiny 1% training samples. One longer window can form from the earlier authoritative anchor instead.

The policy supplied to the current authoritative reading is the live threshold source. Tightening does not retroactively close a span under an older looser threshold, while loosening may legitimately close an already-retained span on a later authoritative reading, including a flat percentage update. The same rule applies independently to both the consumed-percentage and minimum-distance thresholds.

### Measured recovery / charging defense

**Any authoritative increase versus the immediately preceding authoritative reading rebases the span**, even when the new value remains below the original anchor.

Example:

`80 → 77 → 79`

The `79` reading starts a fresh span. The assembler does not keep pretending the original `80` anchor describes one uninterrupted consumption interval, because `77 → 79` may represent charging, voltage-sag recovery, firmware filtering, or another non-consumption effect.

This is intentionally stricter than comparing only with the original anchor. It prevents hidden in-span recovery from being folded into a later consumption sample.

Authoritative uptime ordering is likewise checked against the **latest accepted authoritative reading**, not merely the span anchor. If a stream has accepted uptimes `10 → 20`, an authoritative reading at uptime `15` fails closed even though `15` is newer than the original anchor. Ordering is validated before any measured-recovery rebase, so a duplicate/same-timestamp higher percentage cannot erase in-flight evidence.

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

## Candidate closure versus model acceptance

Emitting a `BatteryRangeLearningWindow` **closes the assembler span immediately**. The end authoritative SoC becomes the next anchor and span-local distance/coverage/gap evidence is reset before the caller asks `AdaptiveBatteryRangeModel` whether the candidate should teach history.

That separation is intentional. Model rejection does not roll the assembler back:
- a transport-gap or incomplete-coverage candidate must not keep contaminating future clean evidence;
- a statistically rejected efficiency outlier must not cause its distance to be replayed into the next sample;
- a rejection never authorizes a higher layer to re-add the old span's distance merely to recover a training sample.

The next clean evidence span therefore begins at the rejected candidate's end SoC. Persisted learned history remains unchanged when the model rejects the candidate, while ephemeral assembly continuity moves forward.

## Atomic failure behavior

The assembler rejects:
- negative/nonfinite distance deltas;
- accumulated distance overflow;
- authoritative SoC timestamps that do not advance beyond the latest accepted authoritative measurement.

Those errors occur before mutating the in-flight span.

## Lifecycle

The assembler is ephemeral evidence state. It should be reset at an explicit ride/device/session boundary when a higher layer can no longer prove continuity of the in-flight span.

A reset intentionally loses only the uncommitted learning candidate. It clears both the span anchor and latest-authoritative cursor. The first subsequent authoritative SoC reading becomes a fresh anchor; distance before that anchor is not retroactively assigned a battery-consumption start value.

Reset also abandons the prior authoritative uptime-ordering baseline, so a genuinely new higher-layer epoch may begin from a lower process-local uptime value. That is only valid when the caller has explicit continuity/session evidence for a new epoch; `reset()` must not be used to hide an unexplained timestamp regression inside one observed epoch.

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
