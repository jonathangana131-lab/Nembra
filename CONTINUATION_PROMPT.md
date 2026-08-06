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

## Expected live handoff when this checkpoint lands
- Stable base before Phase 14: `main` at `c79dec497bee7bc7047601963204b568acec8d5e`.
- Active branch: `feature/durable-ride-routes`.
- Active PR: **#7 — Persist and present truthful completed-ride route geometry**.
- Accepted implementation head before memory-only commits: `088c849757a1a688255acc1538c96aa725b24a12`.
- Resolve the exact current branch SHA from GitHub; documentation commits after that implementation head intentionally require a fresh exact-head CI gate.

## Phase 14 accepted implementation
The branch adds truthful durable route geometry while keeping production Core Location capture disabled until its real permission/quality/background/energy policy is implemented and field-tested.

Preserve these boundaries:
- route chunks/manifests are immutable and idempotent by exact identity; conflicting evidence never overwrites prior geometry.
- persisted indexed identity and decoded payload identity must agree.
- corrupt/missing/reordered chunks fail closed rather than producing a plausible map.
- process recovery and known route gaps create explicit geometry segment boundaries; presentation never draws across them.
- a route with a known gap/recovery cannot claim complete coverage.
- route storage is isolated from completed history/recovery so an additive route-store failure cannot erase ride history.
- no stored coordinates means **No route geometry recorded**; corrupt/unavailable storage is an error, not successful emptiness.
- MapKit draws only validated stored coordinates.
- map geometry never becomes final distance evidence by itself.
- Simulator route coordinates are deterministic QA-only, isolated from production, classified partial, and do not fabricate `qualityScreenedGPSDistanceMeters`.
- production automatic ride detection and production Core Location route recording remain hardware/field-gated.

Implementation-head Xcode evidence already accepted:
- head `088c849757a1a688255acc1538c96aa725b24a12`
- workflow run `31082309937`
- job `92553689585`
- artifact `8960225545` / `nembra-xcode27-simulator-222-1`
- conclusion **success**
- app/core Xcode tests **27/27**, zero failures
- UI tests **7/7**, zero failures
- inspected iPhone 12 attachments: **Completed Ride History** and **Completed Ride Details With Route**.
- Route detail visibly shows real MapKit rendering from stored simulated coordinates and **Partial recorded coverage** while keeping `ODO 0.2 mi` separate.

Those captures are functional systems evidence only. The Rides/Route visual treatment remains subject to the mandatory Production Visual Overhaul.

## Exact unfinished action after this checkpoint
1. Resolve the newest exact `feature/durable-ride-routes` head after `PROJECT_STATE.md` and this file are committed.
2. Wait for **Xcode 27 Simulator QA** on that exact head while doing only safe read/review work; do not mutate the branch unless a real issue is discovered.
3. Verify all jobs green and preserve exact run/job/artifact identifiers.
4. Verify PR #7 has no unresolved review threads/comments and is mergeable.
5. Mark PR #7 ready for review.
6. Squash merge PR #7 with `expected_head_sha` set to the exact green head.
7. Verify merged PR and fresh `main` SHA.
8. Re-inspect fresh `main`, open PRs, branches, newest commits, Actions, and project-memory files.
9. Determine the next substantial vertical slice from fresh repository state, create its branch, and immediately begin implementation. Do not stop at the Phase 14 merge boundary.

## Systems that must not be casually rebuilt
- capability-based `VehicleProfile` / `ScooterService` boundary.
- explicit `SimulatedScooterService` and hardware-gated `UnverifiedScooterService`.
- typed connection failures plus live/retained/unavailable state semantics.
- serialized pessimistic confirmed commands with connection-generation invalidation.
- raw authoritative speed evidence separate from state/display interpolation.
- fixed-slot rolling speed model and confirmed-mode-only Dashboard personality.
- automatic `RideEngine` with disconnect continuity.
- two-slot crash-recovery journal and `completedPendingCommit` handoff.
- exact SwiftData completed-history adapter and readback-verified idempotent commit contract.
- independent ODO/GPS/live-distance coverage and reconciliation architecture.
- root-owned history and route presentation stores.
- immutable route chunk/manifest persistence and explicit route-gap topology.

## Hardware/field truth still unresolved
Real MAXSHOT advertisement identity, BLE services/characteristics/properties, notification cadence/latency/jitter/resolution, packet framing/checksum, read/write acknowledgements, firmware differences, DP101/102/103 semantics, AccessorySetupKit descriptors, real iOS 27 Core Location authorization/background behavior, outdoor GPS quality policy, energy behavior, and physical iPhone 12 profiling.

Do not send unknown motorized-vehicle writes or expose fake VESC/tuning controls.

## Execution reminder
A progress update, passing build, screenshot, commit, PR, merge, or phase boundary is not a conversation stop. While another safe tool action can advance Nembra, keep executing. If the platform forcibly ends the run, GitHub is the recovery memory.
