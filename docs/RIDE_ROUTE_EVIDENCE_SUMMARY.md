# Ride Route Evidence Summary

Worker: `chat-m4v8z`

Lane: `ride-route-evidence-summary`

## Purpose

Completed-ride route storage already preserves real accepted coordinates as explicit segments, coverage classification, point count, and known-gap count. The production UI can render those facts, but it needs a small semantic boundary that prevents presentation code from quietly turning sparse or incomplete topology into stronger route claims.

`RideRouteEvidenceSummary` is that boundary. It summarizes only persisted route topology that a caller has already validated. It does not calculate route distance, reconstruct missing geometry, or decide whether a route is suitable for a scooter.

This is also an implementation foundation for the source-backed ride-history accessibility finding that Nembra needs a stable app-owned semantic description of recorded route coverage/points/known gaps. User-facing wording and localization remain an app-layer responsibility rather than being embedded in NembraCore.

## Inputs

The summary accepts:

- `RideDistanceCoverage` — `.complete`, `.partial`, or `.unknown`;
- per-segment persisted point counts;
- the persisted known-gap count.

It derives:

- total segment count;
- total point count with overflow protection;
- whether any route geometry exists;
- whether any one continuous recorded segment contains enough points to draw a path;
- whether explicit interior gaps are known.

## Shape semantics

`RideRouteEvidenceShape` deliberately has only three states:

- `noRecordedGeometry` — no persisted route points exist. This state is accepted only with unknown coverage and zero known gaps.
- `recordedPointsOnly` — real route points exist, but no single recorded continuous segment has two points, so drawing a path would fabricate an edge.
- `drawablePath` — at least one continuous recorded segment has two or more real points. Only those persisted segment edges may be drawn; the state does not authorize drawing across gaps.

A drawable path is not the same as complete ride coverage. `.partial` and `.unknown` coverage may both contain drawable recorded segments.

## Fail-closed invariants

The constructor rejects evidence that would create contradictory presentation state:

- negative gap counts;
- empty/zero-length persisted segments;
- point-count integer overflow;
- no recorded geometry paired with complete/partial coverage or known gaps;
- more known interior gaps than segment topology can contain;
- known gaps paired with complete or unknown coverage.

Partial coverage with zero materialized interior gaps remains valid. Current route recording can truthfully be partial because capture started after an unobserved interval, ended with a pending gap, or was otherwise explicitly forced partial without producing a second persisted segment.

Unknown coverage with recorded geometry also remains valid. The presence of coordinates does not prove whole-ride completeness.

## Truth boundaries

This domain does **not**:

- infer final ride distance from route geometry;
- bridge route gaps with straight lines or guessed coordinates;
- convert ODO, speed integration, or other evidence into route points;
- claim a recorded path covers the whole ride unless upstream evidence says coverage is complete;
- infer place names, streets, destinations, route purpose, legality, or safety;
- infer scooter-specific routing suitability;
- alter ride persistence, MapKit geometry, GPS screening, adaptive range, battery truth, or BLE behavior;
- provide physical AOVOPRO ES80 or outdoor-GPS validation.

Simulation and deterministic tests remain software evidence only.

## Integration boundary

This lane is package-only. It intentionally does not modify `AppRootView.swift`, ride UI tests, SwiftData persistence, the Xcode project, or shared app wiring while those surfaces are owned by other workers.

A later Rides UI/accessibility integration may consume this semantic state to produce concise localized output such as coverage, recorded points, and known gaps. The app must preserve the distinction between:

- no route recorded;
- real points recorded but no drawable continuous path;
- drawable recorded segments;
- complete, partial, and unknown coverage;
- zero known interior gaps versus an affirmative claim of complete coverage.

## Verification

Focused deterministic Swift Testing covers:

- no-geometry behavior;
- points-only topology;
- drawable continuous segments;
- complete no-gap topology;
- partial topology with and without explicit interior gaps;
- unknown coverage with real geometry;
- contradictory coverage/gap combinations;
- invalid segment/gap counts;
- total point-count overflow.

A supplemental Swift 6.2.1 harness using the same source semantics passed the focused suite. Repository-wide NembraCore and Xcode 27/iPhone 12 Simulator acceptance is still required on the exact final branch head before merge.
