# Battery display SoC transition

Worker lane: `battery-presentation-transition`

This slice implements only the integer presentation transition required by Nembra's battery/range contract. It does not decide where battery percentage comes from and does not classify a target as measured, estimated, derived, or presentation-only evidence.

## Contract

`BatteryDisplaySOCTransitionPlanner` accepts two already-classified display-layer percentage values and returns one of:

- `clear` when no legitimate target display percentage exists;
- `snap` when the target is valid but no meaningful integer animation can be formed;
- `animate` with ordered integer frames that exclude the already-rendered start and include the caller-supplied target.

For a visible change from `84` to `80`, the planned frames are `83, 82, 81, 80`. The first three are explicitly `presentationIntermediate`; only the last is labeled `targetDisplayValue`. That final role still does not claim measured provenance. Upstream battery evidence remains authoritative for that distinction.

## Truth boundary

Intermediate frames are visual-only. They must never be:

- persisted as measured scooter telemetry;
- inserted into adaptive-range learning windows;
- treated as BLE/Tuya packets;
- used to infer physical ES80 percentage resolution or cadence;
- promoted from presentation state into measured or estimated SoC evidence.

An unavailable or invalid target clears the readout rather than animating toward zero. `0%` remains valid only when zero is actually supplied as the target display value.

## Interruption behavior

The planner is intentionally stateless. If a new battery target arrives while an animation is partway through, the UI can plan again from the integer currently being rendered. This prevents a stale transition queue from having to finish before a newer display target can take over.

The planner produces at most 100 frames because normalized display SoC is restricted to `0...100`.

## Validation

Focused deterministic Swift 6.2.1 tests cover:

- descending integer traversal;
- ascending correction traversal;
- one-point changes;
- unchanged values;
- unknown/invalid current display values;
- unknown/invalid target display values;
- valid `0%` and `100%` boundaries;
- the bounded `100 -> 0` full-scale correction;
- interruption/replanning from the currently rendered integer.

This is software presentation behavior only. It does not verify any physical AOVOPRO ES80 battery source, resolution, cadence, voltage behavior, charging semantics, or Tuya data point.
