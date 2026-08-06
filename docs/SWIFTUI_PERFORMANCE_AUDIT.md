# SwiftUI performance audit — Dashboard speed instrument

Date: 2026-08-06
Worker: `chat-p7w3k`
Lane: `swiftui-performance-audit`
Baseline: iPhone 12 / iOS 27

This note records a code-first performance pass over Nembra's current systems-era SwiftUI surfaces. It is intentionally narrow: the implementation change in this lane addresses one concrete high-frequency invalidation cost in the landscape Dashboard without changing telemetry truth, ride behavior, vehicle commands, or hardware assumptions.

## Evidence level

### Code-proven finding

Before this lane, `DashboardSpeedInstrumentView` wrapped its complete central instrument composition in a 60 Hz animation `TimelineView` while interpolation was active. Each animation tick therefore rebuilt more than the rolling visual number: the unit label, vertical layout, status label selection, status styling, and accessibility value formatting were all inside the timeline closure.

The accepted architecture already intended the animation clock to remain local to presentation-only speed smoothing. The view boundary was simply broader than required.

### Implemented remediation

The 60 Hz timeline now owns only the visual speed readout. The surrounding composition is evaluated at ordinary SwiftUI state-change cadence:

- status text and state selection stay outside the animation timeline;
- VoiceOver value formatting stays outside the animation timeline;
- the measurement-system lookup is resolved outside the per-frame closure;
- the newest accepted authoritative speed is exposed directly by `SpeedInstrumentModel` for the accessibility anchor;
- visual interpolation frames still never enter `VehicleState`, ride history, distance, stats, persistence, or protocol evidence;
- Reduce Motion still snaps presentation to the newest authoritative measurement.

The result is a smaller high-frequency render subtree with the same truth and interaction semantics.

A separate active worker owns rolling-number allocation hardening in PR #31. This lane deliberately does not modify `RollingSpeedValueView` or `RollingNumberModel`; the two performance slices remain isolated and can be integrated independently.

## Truth and safety invariants

The optimization must not turn presentation state into vehicle evidence.

- `SpeedTelemetrySample` remains the raw speed-evidence boundary.
- `SpeedInstrumentModel` accepts only authoritative measurements into its measured anchor.
- Stale or estimated samples cannot update the authoritative accessibility anchor.
- Interpolated midpoints remain render-only.
- Production interpolation remains disabled until real AOVOPRO ES80 cadence is measured.
- This lane authorizes no Bluetooth writes and makes no physical ES80 claim.

## Verification in this lane

Focused `NembraAppTests` assertions cover the new authoritative anchor:

- it starts unknown when the instrument is using only confirmed `VehicleState` fallback;
- it follows an accepted authoritative speed sample;
- it stays on the latest authoritative value while a separate visual midpoint is rendered;
- stale absolute samples and short-horizon estimates do not move it.

A Swift 6.2 parser check of the modified `SpeedInstrumentModel.swift` is clean in the available local runtime. That is only syntax evidence; it is not an iOS/SwiftUI build or Simulator result.

The final implementation head still requires the repository's Xcode 27 / iPhone 12 Simulator gate before merge.

## Risks deliberately not refactored from code inspection alone

### Broad `VehicleStore.state` observation

`VehicleStore` publishes a complete `VehicleState` value and replaces that whole value for every service state update. The landscape `DashboardView` root reads nested fields from that state for mode personality, status rails, controls, dialogs, battery, and trip presentation. Because those reads are rooted in the single observable `state` property, a speed-only service update is a plausible cause of broader Dashboard reevaluation even though the separate 60 Hz interpolation clock has now been localized.

This is a stronger code-level performance candidate than the tiny computed arrays elsewhere in the UI, but it is also cross-cutting: ride logic, command state, retained data, and many presentation surfaces rely on the current truth model. Do **not** split, mirror, suppress, or selectively drop `VehicleState` updates from source inspection alone. During the Production Visual + Performance Overhaul, use SwiftUI Instruments / view-update evidence on iPhone 12 to determine whether whole-state replacement is materially invalidating the outer cockpit at measured telemetry cadence. If it is, preserve one authoritative domain state and narrow observation/presentation adapters rather than creating competing telemetry truth.

### Home computed presentation collections

Home derives small arrays such as supported ride modes and vehicle detail rows during body evaluation. Their current cardinality is tiny and there is no trace proving they are a meaningful cost. The Home surface is also actively owned by another parallel lane. No Home code is changed here.

### Completed-route Map geometry

`RideRouteMapView` derives coordinate arrays per segment and computes its initial region by flattening stored route points when its body is evaluated. In the current completed-ride detail flow the geometry is immutable presentation input and is not on a telemetry animation clock, so source inspection alone does not justify caching or introducing another map model. Profile realistic long routes before changing it.

### Maps, ride history, and statistics

The production overhaul explicitly requires profiling long history/statistics lists, route rendering, and live map + telemetry together. Those surfaces need realistic data volume and runtime traces; a source-only guess is not acceptance evidence.

## Required profiling follow-up for the production overhaul

When the underlying systems are sufficiently integrated, capture repeatable iPhone 12 / iOS 27 measurements for at least:

1. landscape Dashboard during sustained simulated/verified telemetry, with SwiftUI view-update inspection focused on whether `DashboardView` rails/gradient redraw on speed-only state updates;
2. Dashboard while navigation/map rendering is active;
3. long completed-ride history and statistics scrolling;
4. long-running ride sessions for main-thread load and memory growth;
5. Reduce Motion and ordinary motion configurations.

Prefer the SwiftUI instrument/view-update evidence plus Time Profiler for unexpected CPU work. Compare the same interaction before and after a change. Do not claim an FPS, CPU, memory, or energy improvement from this code-first patch without trace-backed measurement.

## Acceptance boundary

This lane can establish that an unnecessary 60 Hz invalidation boundary was removed and that truth/accessibility behavior is covered by tests. It cannot establish physical iPhone performance, thermal/energy behavior, broad `VehicleStore` invalidation cost, or real AOVOPRO ES80 cadence. Those remain separate runtime and hardware evidence gates.
