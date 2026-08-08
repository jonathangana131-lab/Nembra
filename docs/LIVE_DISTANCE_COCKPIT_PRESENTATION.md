# Live Distance Cockpit Presentation

## Scope

`LiveDistanceCockpitPresentation.swift` is a presentation-only bridge from one current `LiveDistanceSegmentSnapshot` into a product-safe cockpit value.

It exists because a raw `VehicleState.tripKilometers` number cannot express the evidence distinctions already present in NembraCore's live-distance integration model.

This layer does **not** wire Dashboard, select a production ES80 speed source, choose a production cadence limit, finalize a ride, reconcile ODO/GPS distance, persist history, or train adaptive range.

## Product states

### Unavailable

The cockpit value remains unavailable when no accepted measurement interval has been integrated.

A first speed sample is only an integration anchor. It is not converted into `0 m`.

Malformed or contradictory snapshot state also fails closed to unavailable.

### Observed, no recorded gap

`observedNoRecordedGap` means:

- at least one authoritative selected-source interval was actually integrated;
- the observed distance is finite and nonnegative;
- the current process-local snapshot records no known coverage gap.

It does **not** mean:

- the whole ride has complete distance coverage;
- there was no gap before this process-local segment;
- there will be no trailing gap after the latest accepted sample;
- this is a reconciled final ride distance;
- provider route distance, ODO, GPS geometry, or manufacturer range agrees with it.

### Partial observed

`partialObserved` preserves the real integrated numeric subtotal while requiring the consumer to disclose that the segment contains known missing observation coverage.

The subtotal must not be relabeled as complete trip distance.

## Zero is evidence-sensitive

A legitimate integrated zero-meter interval remains a real numeric zero. For example, two accepted zero-speed measurements separated by an accepted interval may integrate to `0 m`.

By contrast, an empty segment or a single anchor remains unavailable. This prevents `0` from being used as a placeholder for missing evidence.

## Structural fail-closed checks

The projector rejects contradictory snapshot shapes, including:

- negative counters;
- a gap flag that disagrees with the gap count;
- more integrated intervals than accepted samples can support;
- accepted sample timestamps before the segment boundary;
- non-increasing first/last accepted chronology for multiple accepted samples;
- a late first accepted sample whose required initial coverage gap has disappeared;
- missing/non-finite/negative numeric distance for an allegedly integrated interval;
- synthetic motion-assist as an absolute distance source.

These checks are defense in depth. Normal production snapshots are minted by `LiveDistanceSegmentAccumulator`.

## Integration boundary

The intended later product flow is:

`authoritative speed evidence`
→ `LiveDistanceSegmentAccumulator`
→ `LiveDistanceSegmentSnapshot`
→ `LiveDistanceCockpitState`
→ unit-aware app formatting / accessible cockpit disclosure.

For rides that cross process/recovery boundaries, the current segment must not simply overwrite or masquerade as whole-ride distance. Finalized segments belong to `RideLiveDistanceAggregator` and then the ride-level reconciliation path.

Dashboard integration should occur only after the active Dashboard/source owners can consume this contract without racing their current work. Until then the legacy `vehicle.state.tripKilometers` presentation remains a known product integration gap.

## Truth boundary

Software presentation semantics only.

No physical AOVOPRO ES80 speed source, cadence, latency, accuracy, BLE/Tuya field, odometer source, GPS quality threshold, or distance accuracy is claimed verified. Display formatting never becomes telemetry evidence, persistence evidence, or range-learning evidence.