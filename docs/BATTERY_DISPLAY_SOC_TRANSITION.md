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

The transition/frame types are intentionally not `Codable`; NembraCore does not provide a default persistence path for visual intermediate frames.

## Interruption behavior

The planner is intentionally stateless. If a new battery target arrives while an animation is partway through, the UI can plan again from the integer currently being rendered. This prevents a stale transition queue from having to finish before a newer display target can take over.

The planner produces at most 100 frames because normalized display SoC is restricted to `0...100`.

## Accessibility and motion execution

The planner describes a truth-preserving path, not an obligation to spatially animate every frame. The SwiftUI presentation layer owns pacing and accessibility policy.

- With normal motion enabled, percentage text and battery fill should advance from the same selected frame so they cannot visually disagree about the displayed SoC.
- If the primary numeric readout is estimated range, SoC frames remain charge/fill presentation state; they must never be used to roll or synthesize the numeric range value.
- With Reduce Motion enabled, the UI may snap or use a restrained non-spatial transition directly to the target display value instead of traversing every intermediate integer on screen.
- VoiceOver should announce the current authoritative/selected battery readout target, not transient `presentationIntermediate` frames.
- If a newer target arrives mid-transition, cancel/replan from the currently rendered integer; do not force a stale queue to finish first.
- Presentation pacing, haptics, timers/tasks, and view animation state intentionally stay outside NembraCore so render policy cannot be mistaken for battery evidence.

These rules preserve the visual one-percent experience where appropriate while keeping accessibility behavior and telemetry truth independent.

## App-target visibility

The Xcode app target currently compiles selected NembraCore source files through explicit `project.pbxproj` entries rather than automatically compiling every package source. The transition planner therefore lives in `BatteryPrimaryReadoutState.swift`, the same battery presentation source that the active Dashboard readout integration already wires into the app target. This avoids creating a second manual project-file entry and prevents a package-green/app-target-missing-source failure mode.

The transition types remain a package-domain boundary. This co-location is build integration only; it does not merge presentation frames with battery evidence or give the planner permission to mutate readout state.

## Rolling-number relationship

`RollingNumberModel` remains complementary. It describes per-digit movement between numeric display snapshots; this planner describes whole battery-percent presentation frames so a future battery UI can keep percent text and battery fill synchronized while preserving the distinction between rendered intermediates and source evidence.

## Validation

Focused deterministic Swift 6.2.1 tests cover:

- descending integer traversal;
- ascending correction traversal;
- one-point changes;
- unchanged values;
- unknown/invalid current display values;
- unknown/invalid target display values;
- extreme invalid `Int.min` / `Int.max` endpoints failing closed before arithmetic;
- valid `0%` and `100%` boundaries;
- the bounded `100 -> 0` full-scale correction;
- interruption/replanning from the currently rendered integer;
- every changed valid `0...100` endpoint pair, exhaustively checking bounded sequential frames and final target-role termination.

The transition suite passes 11/11 tests in both debug and release configurations. The combined exact-source-shape `BatteryPrimaryReadoutState` + transition harness passes 23/23 tests in both configurations with warnings treated as errors.

This is software presentation behavior only. It does not verify any physical AOVOPRO ES80 battery source, resolution, cadence, voltage behavior, charging semantics, or Tuya data point.
