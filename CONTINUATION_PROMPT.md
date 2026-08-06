# CONTINUATION PROMPT

Continue the existing Nembra production iOS project in `jonathangana131-lab/Nembra`. Do not create another repository/app, restart accepted architecture, or ask the user to summarize previous work.

Permanent product/execution requirements live in `MASTER_CONTINUATION_DIRECTIVE.md`. This file is intentionally only the exact resume handoff.

## Fresh resume sequence
1. Inspect repository/default `main` head.
2. Inspect open PRs, branches, newest commits, and newest GitHub Actions/Xcode runs.
3. Determine the actual active branch/PR/head from GitHub before trusting milestone prose.
4. Read `PROJECT_STATE.md` and this file from that active head.
5. Read only the relevant sections of `DECISIONS.md`, `PROTOCOL_NOTES.md`, `DESIGN_SYSTEM.md`, and `docs/` needed for the active slice.
6. Immediately continue the exact unfinished action. Do not stop at a status update while another safe tool action can advance the project.

## Expected live handoff when this checkpoint first lands
- Stable base before Phase 13: `main` at `ea0dfd64f7cb0a6af64d14612c594f141ae1d2d0`.
- Active branch: `feature/completed-ride-history`.
- Active PR: **#6 — Expose truthful completed ride history**.
- Accepted implementation head: `5e2e4b93cdc41af148dc7e029f6da88465dea7ff`.
- This documentation checkpoint is a descendant of that implementation head; resolve its exact SHA from GitHub rather than assuming one from this prose.

## Phase 13 accepted implementation
The branch exposes the existing exact SwiftData completed-ride ledger through a native portrait Rides surface using a root-owned `RideHistoryPresentationStore`.

Preserve these truth boundaries:
- completed records remain immutable exact ride evidence.
- ODO and GPS distances are labeled separately; neither is silently called final distance without reconciliation/coverage evidence.
- no stored coordinates means **No route geometry recorded** and no fake map.
- do not fabricate duration from formatted wall-clock timestamps.
- production automatic ride detection remains disabled pending real MAXSHOT cadence/latency/reconnect validation.
- `NEMBRA_SIMULATION_AUTOCOMPLETE_RIDE=1` is explicit Simulator-only QA and drives the real ride engine/persistence/history path rather than inserting fake rows.
- simulation persistence remains isolated from production.

Implementation-head Xcode evidence is already accepted:
- run `31073268597`
- job `92525538715`
- artifact `8956630995`
- macOS 26.5.2 / Xcode 27.0 (`27A5228h`) / iOS 27.0 (`24A5390f`)
- app/core tests: **21/21**, zero failures
- UI tests: **7/7**, zero failures
- end-to-end history UI test verifies completed row, detail, nonzero odometer evidence, and explicit unavailable route geometry.
- inspected iPhone 12 attachments: **Completed Ride History** and **Completed Ride Details**.

Those captures are accepted as Phase 13 functional systems evidence only. The Rides presentation is not final product-design acceptance and remains subject to the mandatory Production Visual Overhaul.

## Exact unfinished action after this memory checkpoint
1. Resolve the newest exact `feature/completed-ride-history` head.
2. Inspect the **Xcode 27 Simulator QA** run for that exact docs head.
3. Freeze the branch while the exact-head gate runs. Do not reopen accepted Phase 13 architecture unless the gate exposes a real regression.
4. If green, mark PR #6 ready for review.
5. Squash merge PR #6 with `expected_head_sha` set to that exact green head.
6. Verify the merged PR and fresh `main` head.
7. Re-inspect fresh `main`, open PRs, branches, newest commits, Actions, and project-memory files.
8. Determine the next substantial vertical slice from fresh repository state. Do not infer it from old phase numbering.
9. Create the next branch from fresh `main` and immediately begin the slice.

## Systems that must not be casually rebuilt
- capability-based `VehicleProfile` / `ScooterService` boundary.
- explicit `SimulatedScooterService` and hardware-gated `UnverifiedScooterService`.
- typed connection failures plus live/retained/unavailable state semantics.
- serialized pessimistic confirmed commands with connection-generation invalidation.
- raw authoritative speed evidence separate from state and display interpolation.
- fixed-slot rolling-number model and localized Dashboard speed rendering.
- confirmed-mode-only Dashboard personality.
- automatic `RideEngine` with disconnect continuity.
- two-slot crash-recovery journal and `completedPendingCommit` handoff.
- root-owned ride application coordinator.
- exact SwiftData completed-history adapter and idempotent readback-verified commit contract.
- independent ODO/GPS/live-distance coverage and reconciliation architecture.
- root-owned completed-history presentation store.

## Hardware truth still unresolved
Real MAXSHOT advertisement identity, services/characteristics/properties, notification cadence/latency/jitter/resolution, packet framing/checksum, read/write acknowledgements, firmware differences, DP101/102/103 user-facing semantics, and AccessorySetupKit descriptors.

Do not send unknown writes or expose fake VESC/tuning controls.

## Execution reminder
A progress update, passing build, screenshot, commit, merge, or phase boundary is not a conversation stop. While another safe tool action can advance Nembra, keep executing. If the platform forcibly ends the run, GitHub is the recovery memory.