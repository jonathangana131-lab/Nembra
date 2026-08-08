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
- fewer known gaps than the number of accepted-sample adjacencies that were not integrated;
- a late first accepted sample whose leading gap is not accounted **in addition to** later missing accepted intervals;
- accepted sample timestamps before the segment boundary;
- non-increasing first/last accepted chronology for multiple accepted samples;
- missing/non-finite/negative numeric distance for an allegedly integrated interval;
- synthetic motion-assist as an absolute distance source.

The missing-interval lower bound follows directly from the accumulator lifecycle: a successful accepted adjacency increments both accepted samples and integrated intervals, while each accepted adjacency that is skipped because of an oversized interval or a prior numeric continuity break is backed by an already recorded gap. A leading hole before the first accepted sample is a separate coverage event, so its gap cannot stand in for a later skipped accepted adjacency. A gapless snapshot therefore cannot contain fewer integrated intervals than `acceptedSampleCount - 1`.

These checks are defense in depth. Normal production snapshots are minted by `LiveDistanceSegmentAccumulator`.

## Snapshot authority boundary

`LiveDistanceSegmentSnapshot` is also compiled directly into Nembra.app, so a normal synthesized internal memberwise initializer would be callable by unrelated same-module app/UI code. That would let a caller manufacture apparently accepted live-distance evidence before it reaches the presentation projector.

The snapshot constructor is therefore explicitly scoped in `LiveDistanceIntegration.swift`:

- `package init` under SwiftPM, so deterministic NembraCore fixtures can model malformed inputs and verify fail-closed behavior;
- `fileprivate init` in the direct app build, so only the integration implementation in that source file can mint production snapshots.

This mirrors the existing direct-app authority seal on `FinalizedLiveDistanceSegment`. Repository search found no legitimate production construction site outside `LiveDistanceSegmentAccumulator.snapshot`, so the seal narrows authority without changing accepted runtime behavior.

## Integration boundary

The intended later product flow is:

`authoritative speed evidence`
→ `LiveDistanceSegmentAccumulator`
→ `LiveDistanceSegmentSnapshot`
→ `LiveDistanceCockpitState`
→ unit-aware app formatting / accessible cockpit disclosure.

For rides that cross process/recovery boundaries, the current segment must not simply overwrite or masquerade as whole-ride distance. Finalized segments belong to `RideLiveDistanceAggregator` and then the ride-level reconciliation path.

Dashboard integration should occur only after the active Dashboard/source owners can consume this contract without racing their current work. Until then the legacy `vehicle.state.tripKilometers` presentation remains a known product integration gap.

## Source visibility boundary

The Swift package auto-discovers `LiveDistanceCockpitPresentation.swift`, but Nembra.app manually compiles selected NembraCore files through `project.pbxproj`. This PR deliberately does not edit that high-contention project file while multiple app-surface workers are active.

A later coordinated Dashboard integration slice must add the accepted presentation source to the direct app target and prove the exact app build before consuming it. Package acceptance alone is not app visibility.

## Truth boundary

Software presentation semantics and constructor authority only.

No physical AOVOPRO ES80 speed source, cadence, latency, accuracy, BLE/Tuya field, odometer source, GPS quality threshold, or distance accuracy is claimed verified. Display formatting never becomes telemetry evidence, persistence evidence, or range-learning evidence.
