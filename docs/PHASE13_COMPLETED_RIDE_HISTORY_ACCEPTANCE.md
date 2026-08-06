# Phase 13 Acceptance — Truthful Completed Ride History

Date: 2026-08-06

## Scope

Phase 13 exposes Nembra's existing durable completed-ride ledger through the production portrait application without creating a second persistence or ride-history truth model.

Accepted implementation head:
`5e2e4b93cdc41af148dc7e029f6da88465dea7ff`

Active PR at acceptance:
`#6 — Expose truthful completed ride history`

## Implemented product behavior

- `RideHistoryPresentationStore` is root-owned and reads the existing SwiftData history adapter.
- Portrait shell provides native Home/Rides tabs; landscape remains the dedicated Dashboard.
- Home receives bottom safe-area room for the iOS 27 floating tab bar.
- completed records are displayed newest-first.
- ride rows explicitly label scooter ODO evidence and GPS evidence independently.
- ride detail shows timestamp/continuity evidence without inventing elapsed duration.
- odometer evidence is explicitly labeled `Scooter odometer delta`.
- no real stored route coordinates produces `No route geometry recorded`; no map polyline is fabricated.
- history loading and persistence failures have explicit unavailable/error states.
- Simulator QA can opt into `NEMBRA_SIMULATION_AUTOCOMPLETE_RIDE=1`, which drives the production service/ride/persistence/history path instead of directly inserting a row.

## Truth boundaries

Phase 13 does **not** claim:
- a reconciled final ride distance where source coverage has not been reconciled.
- route geometry when no coordinates were stored.
- an evidence-backed ride duration merely because start/end formatted wall-clock timestamps exist.
- production MAXSHOT automatic ride detection readiness.
- real MAXSHOT BLE/protocol validation.

## Exact Xcode 27 / iOS 27 evidence

GitHub Actions workflow: **Xcode 27 Simulator QA**

- run: `31073268597`
- job: `92525538715`
- artifact: `8956630995` (`nembra-xcode27-simulator-197-1`)
- head SHA: `5e2e4b93cdc41af148dc7e029f6da88465dea7ff`
- conclusion: **success**
- environment recorded by artifact:
  - macOS 26.5.2
  - Xcode 27.0 build `27A5228h`
  - iOS 27.0 runtime build `24A5390f`
  - iPhone 12 simulator device type is available and used by the workflow's app/UI gate

Workflow stages passed:
- project structure validation
- core package validation
- full Xcode app/test/UI Simulator stage
- QA artifact upload

XCTest result evidence:
- app/core Xcode test session: **21/21**, zero failures
  - `NembraAppTests`: 14
  - additional core suite: 7
- UI test session: **7/7**, zero failures
  - `NembraUITests`: 5
  - `RideUITests`: 2

End-to-end history test:
`RideUITests/testCompletedRideAppearsInHistoryThroughRealRidePipeline()`

Observed test path:
1. launch explicit isolated Simulator ride scenario.
2. allow the Simulator-only fixture to drive real ride completion/history persistence.
3. open the Rides tab.
4. observe `rides.completed-row`.
5. capture **Completed Ride History**.
6. open the row.
7. observe `rides.detail`.
8. verify `rides.evidence.odometer` exists and contains a nonzero value.
9. verify `rides.route-unavailable` exists.
10. capture **Completed Ride Details**.

The prior crash/relaunch continuity UI test also remained green and preserved its kept attachments **Automatic Ride Active Home** and **Automatic Ride Recovered Home**.

## Screenshot self-critique

### Completed Ride History
Accepted for this systems slice because:
- the single ride row is legible and clearly labeled `ODO 0.2 mi`.
- the value is presented as a source-specific odometer delta rather than generic final distance.
- the explicit footer reinforces source separation.
- the floating tab bar does not cover the row/footer.
- there is no clipping or unsafe-area overlap.

Known non-final product-design limitations:
- large unused space with only one record.
- generic native list/card treatment rather than the final premium ride-history visual language.
- the explanatory footer is intentionally verbose for truthfulness during systems development and may be redesigned later without weakening semantics.

### Completed Ride Details
Accepted for this systems slice because:
- timeline, distance evidence, and route availability have clear separate hierarchy.
- odometer delta is explicit and nonzero.
- route absence is explicit; no fake map or reconstructed geometry is shown.
- no content is obscured by the floating tab bar.
- no clipping/overlap was observed.

Known non-final product-design limitations:
- layout remains information-first and visually conservative.
- timeline rows and route-unavailable treatment are not the final premium EV-style product design.
- these screenshots do not satisfy the future Production Visual Overhaul release gate.

## Acceptance decision

The Phase 13 **implementation head** is functionally/runtime accepted. The branch still requires a final Xcode 27 gate on the exact project-memory documentation head before PR #6 may be marked ready and squash merged.

After merge, fresh `main` state—not this document—determines the next vertical slice.