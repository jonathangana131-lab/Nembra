# Ride Route Evidence Summary

Worker: `chat-m4v8z`

Lane: `ride-route-evidence-summary`

## Purpose

Completed-ride route storage already preserves real accepted coordinates as explicit segments, coverage classification, point count, and known-gap count. `RideRouteManifest` and `RideRouteGeometry` already own the fail-closed persistence/topology invariants.

The production UI can render those facts, but it needs a small semantic projection that prevents presentation code from quietly turning sparse or incomplete topology into stronger route claims.

`RideRouteEvidenceSummary` is that projection. It accepts only an already-validated `RideRouteGeometry` and exposes a compact presentation shape. It does not create a second route validator, calculate route distance, reconstruct missing geometry, or decide whether a route is suitable for a scooter.

This is also an implementation foundation for the source-backed ride-history accessibility finding that Nembra needs a stable app-owned semantic description of recorded route coverage/points/known gaps. User-facing wording and localization remain an app-layer responsibility rather than being embedded in NembraCore.

## Authority and inputs

`RideRouteGeometry` remains authoritative for:

- session-consistent persisted route chunks;
- contiguous segment/chunk topology;
- global point ordering;
- manifest point/segment count agreement;
- `.complete`, `.partial`, or `.unknown` coverage supplied by the recording layer;
- explicit known-gap count.

The summary takes one validated `RideRouteGeometry` and projects:

- coverage without reinterpretation;
- exact segment count;
- exact point count;
- exact known-gap count;
- whether any route geometry exists;
- whether any one continuous recorded segment contains enough points to draw a path.

It deliberately performs no independent coverage/gap validation. If accepted geometry says coverage is `.unknown` while explicit segment gaps exist, the summary remains `.unknown`; it must not strengthen or rewrite upstream truth.

## Shape semantics

`RideRouteEvidenceShape` deliberately has only three states:

- `noRecordedGeometry` — the validated geometry contains no persisted route points.
- `recordedPointsOnly` — real route points exist, but no single recorded continuous segment has two points, so drawing an edge would fabricate geometry.
- `drawablePath` — at least one continuous recorded segment has two or more real points. Only those persisted segment edges may be drawn; the state does not authorize drawing across gaps.

A drawable path is not the same as complete ride coverage. `.partial` and `.unknown` coverage may both contain drawable recorded segments.

## Why the projection does not revalidate

An earlier draft constructor accepted raw counts and applied its own stricter coverage/gap rules. Static audit against the existing `RideRouteManifest` / `RideRouteGeometry` contract showed that approach could reject geometry that Nembra already accepts truthfully, specifically `.unknown` coverage with explicit persisted gaps.

That duplicate validator was removed before acceptance. The current API consumes `RideRouteGeometry` directly so there is one topology authority rather than two subtly diverging truth models.

Partial coverage with zero materialized interior gaps also remains valid. Current recording can truthfully be partial because capture started after an unobserved interval, ended with a pending gap, or was otherwise explicitly forced partial without producing a second persisted segment.

## Truth boundaries

This domain does **not**:

- infer final ride distance from route geometry;
- bridge route gaps with straight lines or guessed coordinates;
- convert ODO, speed integration, or other evidence into route points;
- claim a recorded path covers the whole ride unless upstream evidence says coverage is complete;
- turn unknown coverage into partial/complete merely because gaps are or are not visible;
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

Focused deterministic Swift Testing projects real validated `RideRouteGeometry` fixtures and covers:

- empty unknown geometry;
- one-point points-only geometry;
- complete drawable no-gap geometry;
- partial multi-segment geometry with exact counts/gaps;
- unknown multi-segment geometry with an explicit persisted gap, proving the summary does not strengthen coverage;
- partial geometry without an interior gap;
- multiple separated single points remaining points-only.

A supplemental Swift 6.2.1 projection harness is used for fast syntax/behavior checks. Repository-wide NembraCore and Xcode 27/iPhone 12 Simulator acceptance is still required on the exact final branch head before merge.
