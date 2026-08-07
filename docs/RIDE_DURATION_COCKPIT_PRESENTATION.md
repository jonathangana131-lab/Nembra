# Ride Duration Cockpit Presentation

Worker lane: `parallel/ride-duration-cockpit/chat-q7m5v`

## Product purpose

V13 requires observed ride duration to become useful cockpit context without turning wall-clock elapsed time, app suspension, reconnect gaps, or display animation into ride evidence.

`RideDurationCockpitState` is the product-facing projection from the already accepted `RideSessionDurationEvidenceSnapshot` truth domain. It is intentionally pure and clockless. It does not start, stop, persist, or advance a ride. It only describes what an accepted duration snapshot is safe to mean on a primary riding surface.

## Truth states

### Unavailable

No monotonic observation segment means duration is unavailable. The cockpit must not substitute `0:00`.

Structurally contradictory snapshots also fail closed to unavailable rather than exposing a plausible-looking number.

### Elapsed observed

A complete snapshot with exactly one contiguous observation segment may be presented as observed elapsed ride duration. A real zero-duration segment remains a legitimate `0` value and is distinct from unavailable.

### Partial observed

If any interval before or between accepted observation segments was not observed, the numeric value is still useful but it is only **observed time**. Product UI must qualify it accordingly instead of presenting it as the complete elapsed ride duration.

This includes conservative recovery that begins after an already-unobserved interval.

## Measurement clock versus display clock

The projection does not contain `Date`, a timer, a display timestamp, or a method that advances duration.

A newer numeric value may appear only after the authoritative ride lifecycle produces a newer accepted `RideSessionDurationEvidenceSnapshot`. A future 1 Hz text refresh or 60 Hz cockpit render may re-render the latest value, but it must not increment the underlying observed duration on its own.

This protects these gaps from being silently filled:
- app suspension;
- process interruption/relaunch;
- an explicit evidence discontinuity;
- reconnect periods not covered by accepted duration observation;
- stale UI frames.

## Numeric projection

The exact accepted `observedDurationNanoseconds` remains attached to the presentation value. `wholeObservedSeconds` is a render convenience computed by integer division and therefore rounds down. It cannot exceed the accepted evidence and cannot overflow, including at `UInt64.max`.

UI formatting such as `12:34` stays above this domain so localization and visual design do not become evidence semantics.

### Stable clock fields

`RideDurationCockpitClockComponents` decomposes the already-accepted `wholeObservedSeconds` into integer `hours`, `minutes`, and `seconds` fields. It exists so a future fixed-geometry cockpit readout can render `MM:SS` or `H:MM:SS` without introducing `Date`, floating-point conversion, or a display-owned timer.

The decomposition is intentionally one-way presentation arithmetic:
- seconds are never rounded up from subsecond evidence;
- minutes and seconds remain bounded to `0...59`;
- hours remain `UInt64`, so very large accepted durations do not overflow merely because presentation crosses an hour boundary;
- `usesHourField` is layout guidance only and carries no evidence meaning;
- the original `RideDurationCockpitValue.role` remains beside the components, so partial observed time cannot become unqualified elapsed time through formatting.

Clock components are not persisted telemetry, are not a new measurement, and must never be fed back into ride-duration evidence.

## Integration boundary

This lane deliberately does not modify:
- `RideApplicationStore` or ride-lifecycle ownership;
- `DashboardView.swift` or its active battery/readout ownership;
- `Nembra.xcodeproj/project.pbxproj`;
- completed-ride persistence/statistics;
- battery/range, propulsion, navigation, Bluetooth, or vehicle commands.

The next legitimate integration step is for the root-owned ride lifecycle to expose accepted duration snapshots from its single observation authority. The Dashboard may then consume this projection and render:
- complete observed duration as normal ride context;
- partial observed duration with a concise visible/accessibility qualifier;
- unavailable duration as unavailable, never fake zero.

That integration must not create a second duration accumulator in SwiftUI view lifetime.

## Hardware boundary

Software product-truth projection only. It does not establish physical AOVOPRO ES80 timing, background-execution continuity, reconnect timing, or any scooter protocol behavior. Simulator/Xcode success remains software evidence only.
