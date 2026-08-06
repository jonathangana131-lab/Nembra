# CONTINUATION PROMPT

Continue the existing Nembra production iOS project in `jonathangana131-lab/Nembra`. Do not create another repository/app, restart accepted architecture, or ask the user to summarize previous work.

Permanent product/execution requirements live in `MASTER_CONTINUATION_DIRECTIVE.md`. GitHub live state wins over this prose if they differ.

## Fresh resume sequence
1. Inspect `main`, open PRs, active branches, newest commits, and newest Xcode/Actions runs.
2. Identify the real active branch/PR/head before trusting milestone text.
3. Read `PROJECT_STATE.md` and this file from that active head.
4. Read `docs/RIDE_LOCATION_CAPTURE.md` plus only the relevant durable decisions/protocol/design notes.
5. Resume the exact unfinished action; do not stop at a status report while another safe tool action can advance Nembra.

## Expected live handoff
- Stable `main` before the active slice: `e0d584ec35e6c6eab2b0789c4d2fe74f5c82e213`, containing merged PR #7 durable completed-ride route geometry.
- Active branch: `feature/ride-location-capture`.
- Active PR: **#8 — Add truthful ride-scoped phone location evidence**.
- Resolve the exact branch SHA from GitHub; recent implementation/test/doc commits intentionally require a fresh exact-head gate.

## Active slice
The branch adds the phone-location evidence boundary needed before Nembra can safely enable real ride routes/GPS distance.

Preserve these boundaries:
- raw Core Location updates are not automatically ride evidence.
- quality thresholds are injected; there is no production outdoor policy until field traces justify one.
- reduced/approximate location is rejected as precise route evidence.
- software-simulated locations require explicit QA policy permission.
- ordering uses process-local receipt uptime; wall-clock dates do not repair sequence.
- only continuous adjacent accepted points may produce GPS-distance deltas.
- known interruptions/continuity gaps start new route segments and do not invent distance across the gap.
- coordinates persist through the existing immutable `RideRouteRecorder`; screened distance feeds the existing `RideApplicationStore`/`RideEngine` GPS input.
- route geometry and GPS distance remain separate evidence domains even when they originate from the same screened sample stream.
- additive route-store failure must not erase valid screened distance evidence.
- production automatic ride detection remains MAXSHOT-hardware-gated.
- the Core Location adapter is software-implemented but production outdoor/background recording is not yet field validated or enabled as a completed feature.
- no motorized-vehicle write semantics change in this slice.

## Exact unfinished action
1. Resolve the newest exact `feature/ride-location-capture` head after the current project-memory checkpoint.
2. Inspect the newest **Xcode 27 Simulator QA** run for that exact head.
3. If it fails, inspect the failing job/log and fix the real issue; do not merge around it.
4. If green, preserve run/job/artifact identifiers and confirm PR #8 has no unresolved review threads/comments and is mergeable.
5. Mark PR #8 ready and squash merge using `expected_head_sha` equal to the exact green head.
6. Verify fresh `main`.
7. Immediately create/start the next location branch. Do not stop at the merge boundary.

## Next substantial slice after merge
Exercise the new location capture through the real application ride lifecycle rather than only direct integration tests:
- replace/bypass the old Simulator-only direct route-recorder fixture with an injected Simulator location source feeding `RideLocationCaptureCoordinator`,
- make screened GPS distance travel through `RideEngine` into completed ride history while keeping ODO and GPS explicitly separate,
- begin/end capture from authoritative root-owned ride state, not a SwiftUI view,
- use real iPhone 12/iOS 27 Simulator UI evidence to verify route + GPS evidence,
- then implement foreground/background lifecycle ownership using current iOS 27 location APIs before any real production activation.

## Systems not to casually rebuild
- capability-driven `VehicleProfile`/`ScooterService` boundary and hardware-gated production service.
- typed connection failures and live/retained/unavailable state semantics.
- serialized pessimistic confirmed commands with connection-generation invalidation.
- raw authoritative speed separate from display interpolation.
- dedicated Dashboard speed/mode presentation architecture.
- automatic `RideEngine`, crash-recovery journal, and completed-history commit handoff.
- exact SwiftData history ledger.
- independent ODO/GPS/live-distance reconciliation architecture.
- immutable route chunks/manifests and explicit gap topology.
- root-owned history/route presentation stores.

## Still unresolved outside software-only validation
MAXSHOT advertisement/GATT/protocol/acknowledgement facts; DP101/102/103 semantics; AccessorySetupKit descriptors; production location quality policy; real iOS background location behavior; outdoor GPS continuity; energy impact; physical iPhone 12 performance; real MAXSHOT ride validation.

## Execution reminder
A build, commit, PR, screenshot, green gate, merge, or phase boundary is not a conversation stop. Keep executing while another safe tool action can advance Nembra. GitHub is the recovery memory if the platform terminates the run.
