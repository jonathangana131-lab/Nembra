# PROJECT STATE

Updated: 2026-08-04

## Product
- Product name: **Nembra** (working production identity; preliminary collision research only, not legal trademark clearance)
- First supported vehicle: **MAXSHOT V1S Pro**
- Product stance: premium native iOS vehicle companion, truthful telemetry, multi-scooter architecture later

## Repository
- Remote: `jonathangana131-lab/Nembra` (**public**, created by the user on 2026-08-04)
- Local working tree: `/mnt/data/nembra-ios`
- Branch: `feature/live-distance-accumulator` (authoritative raw-speed distance integration on top of committed ride recovery/reconciliation/Home/simulation/telemetry checkpoints; Home/runtime visual validation is still pending macOS/Xcode)
- Base branch: `main` (keep stable)
- Remote status: **AVAILABLE**. The connected @GitHub tool has admin/push access. Local `gh` is not installed, so this harness publishes through the GitHub connector rather than authenticated native `git push`. The local Git history remains intact; the remote `feature/live-distance-accumulator` branch is the current backup/review branch.

## Current milestone
Milestone 1 — Identity + verified research + production domain model + first portrait Home vertical slice, with nonblocked ride-reliability/telemetry core work continuing while iOS runtime QA is unavailable.

## Completed in this milestone
- Naming collision sweep and initial brand decision
- MAXSHOT V1S Pro public physical/function research ledger
- Prior verified Tuya/YouFS protocol findings separated from hypotheses
- Current Apple platform research: Core Bluetooth restoration/relaunch rules, AccessorySetupKit relevance, background location, MapKit transport-mode truth, Liquid Glass principles
- Capability-based domain model
- Production `ScooterService` abstraction
- Ordinary production launch is hardware-gated through `UnverifiedScooterService`; simulation is explicit QA configuration only
- `SimulatedScooterService` with acknowledged commands, deterministic scenario controls, protocol-slot speed-limit state, overlapping-command rejection, disconnect-during-command protection, raw speed evidence emission, and unit tests
- Raw speed telemetry evidence/benchmark primitives now distinguish BLE/GPS absolute measurements from bounded motion-assisted estimates, measure cadence/jitter/empirical resolution/delivery latency, and reject out-of-order/source-mismatched samples without fabricating display frames
- Render-only speed display model accepts only authoritative measurements, separates visual frames from telemetry evidence, handles interrupted acceleration/deceleration transitions without overshoot, and leaves timing untuned until hardware/runtime evidence exists
- Fixed-slot rolling number model handles upward carry/downward borrow, stable leading-slot geometry, stable fractional precision, conservative 15-slot `Double` precision limits, and zero-motion repeats without telemetry semantics
- First native portrait Home implementation with truthful scooter-trip labeling, connection recovery, quick lock/light controls, mode selection, human-readable vehicle details, and locale-aware units
- Dedicated Vehicle Controls screen for mode, cruise, and start behavior; normal-user speed-limit editing remains intentionally gated until DP101–103 can be mapped without guessing
- Deterministic launch scenarios for cold-disconnected, reconnecting, connected-stopped, riding, low-battery, Bluetooth-off, permission-denied, scooter-unavailable, and unsupported-configuration Simulator QA; see `docs/SIMULATION.md`
- Successful simulated reconnects hydrate only missing vehicle state while preserving retained confirmed values, so cold-reconnect QA becomes usable without resetting a retained session
- Simulation launch configuration is parsed in testable core code and fails closed on invalid environment values, malformed flags, or duplicate flags instead of silently selecting another QA state
- Automatic `RideEngine` domain state machine covers idle/candidate/active/temporarily-disconnected/ending-candidate continuity, fresh authoritative confirmation, incremental quality-screened GPS accumulation, late-but-honest ODO baselines, disconnect preservation, and stop confirmation; stale speed packets cannot start/sustain a ride and failed observations mutate neither phase nor monotonic clock
- Crash-recovery ride persistence core is implemented: two-slot generation journal, validated in-progress/completed evidence, conservative process recovery with no persisted monotonic uptime, cadence-gated stable writes, immediate confirmed-transition writes, and `completedPendingCommit` crash-gap protection before the future permanent history ledger acknowledges/clears the journal; see `docs/RIDE_PERSISTENCE.md`
- Completed-ride history handoff contract is idempotent and readback-verified before recovery evidence can clear; equivalent retry is safe, conflicting same-session evidence cannot overwrite history. Concrete production SwiftData storage remains pending iOS/Xcode validation
- Distance reconciliation core preserves ODO/GPS/live-integration evidence independently with explicit `complete`/`partial`/`unknown` source coverage. It never averages sources and only allows complete ODO to recover mileage across an explicitly partial lower source under an injected policy; there is no MAXSHOT production priority/tolerance yet. See `docs/RIDE_RECONCILIATION.md`
- Process-local live-distance integration core accepts one injected authoritative speed source, integrates only bounded raw-sample intervals, skips known gaps, rejects motion/render evidence, and separates provisional live snapshots from finalized segment coverage. Recovered rides must start a new monotonic segment; ride-level aggregation/checkpointing is still pending. See `docs/LIVE_DISTANCE_INTEGRATION.md`
- Unfinished Rides/Stats placeholder tabs removed from the production shell
- Pending command intent is visually distinct from confirmed vehicle state
- Unverified DP101–103 ↔ ride-mode speed-limit mapping removed from normal UI; the three verified protocol slots remain modeled independently
- State-changing commands are serialized in the app store and defensively gated in the simulator service; a connection-generation token invalidates any write that spans a disconnect/reconnect boundary
- Quick controls are capability-aware and ambiguous unknown lock/headlight states cannot be toggled as though they were confirmed “off”
- Typed connection issues distinguish Bluetooth-off, denied permission, recoverable scooter-unavailable, and unsupported hardware/firmware states with different recovery actions
- Reconnecting/offline summaries explicitly label retained telemetry as **Last known vehicle data** instead of presenting stale values as live
- Transport loss never fabricates zero speed/power/current: disconnect and connection-error transitions preserve the last confirmed values as stale/read-only evidence until a real new measurement arrives
- `VehicleDataAvailability` distinguishes never-observed (`unavailable`), current-session (`live`), and disconnected/reconnecting retained state (`retained`) so UI freshness is not inferred from non-nil values
- Unknown ride mode remains unknown until reported; launch/disconnected UI no longer fabricates a Sport mode
- New Swift files are wired into `Nembra.xcodeproj`, not left as orphaned source files
- Initial design-system rules
- First generated concept pass was critically reviewed and **rejected** for invented telemetry/protocol details and an incorrect brand; see `docs/CONCEPT_REVIEW.md`. Do not regenerate concepts unless the user later asks; current user explicitly asked to avoid image generation during this work stream.
- Continuation/recovery prompt

## Architecture
- `Packages/NembraCore`: platform-independent vehicle domain + service contract + simulator + telemetry/display models + automatic ride engine + crash-recovery journal/coordinator + completed-history handoff/reconciliation contracts + authoritative live-distance segment integration
- `NembraApp/App`: SwiftUI app composition, formatting, and dependency wiring
- `NembraApp/Features/Home`: first vertical slice + full vehicle controls
- `NembraApp/DesignSystem`: visual primitives, not business logic
- Future diagnostics belong in a developer-only feature and must use the same service boundary
- Future real Core Bluetooth implementation belongs outside views and must conform to the same `ScooterService` contract

## Build / validation status
- Linux core package: **PASS — 156 Swift Testing tests** (`swift test`, 2026-08-04 authoritative live-distance segment checkpoint)
- Strict-concurrency typecheck: **PASS** for NembraCore + `VehicleStore` + vehicle formatting on the current Linux Swift 6.2.1 toolchain
- Swift syntax parse: **PASS** for all current app/core Swift source files
- Xcode project plist syntax: **PASS** (`plutil -lint Nembra.xcodeproj/project.pbxproj`)
- Xcode project PBX object references: **PASS** (`scripts/validate_pbxproj_references.py`; catches dangling hand-authored references but does not replace an actual Xcode build)
- GitHub `xcode-27` Simulator QA workflow/shared scheme: **PREPARED FOR REMOTE RUN** — the public remote now exists. The workflow is intended to build/test the real iOS 27 app, launch deterministic Home states, verify the app process remains alive, and upload real Simulator screenshots/logs after the current branch is fully published. See `docs/GITHUB_XCODE27_CI.md`
- iOS/Xcode runtime build: **NOT YET VALIDATED**. A GitHub Actions `xcode-27` macOS workflow is prepared and can run once the current branch snapshot is fully published to the public remote.
- Simulator screenshot: **workflow prepared, not yet executed**. `.github/workflows/xcode27-simulator.yml` uses the Xcode 27 GitHub-hosted Mac, boots an iOS 27 Simulator, launches deterministic Nembra scenarios, captures real `simctl` PNGs, and uploads them with logs. Never substitute generated mockups.

## Simulator target
- Required validation target: iPhone 12 / iOS 27 where available
- Secondary visual target: another current iOS 27 iPhone simulator for layout coverage

## Known bugs / risks awaiting actual iOS runtime QA
- SwiftUI/API availability can only be fully typechecked against the iOS 27 SDK on macOS/Xcode.
- Home visual hierarchy, safe areas, Dynamic Type, Reduce Motion, dark/light appearance, and actual Liquid Glass composition have not yet been visually inspected in Simulator.
- The vehicle silhouette is an intentionally generic code-drawn placeholder until exact model artwork is created from verified references; do not claim it is dimensionally exact.

## Known external blockers
1. Direct interactive macOS/XcodeBuildMCP tools are not exposed in this chat, but GitHub currently provides an `xcode-27` hosted runner with Xcode 27 beta and iOS 27 runtime; Nembra now has a CI/Simulator capture workflow ready to use it.
2. @GitHub lacks repository creation/visibility mutation and local `gh` is unavailable, so the new public repository itself cannot yet be created from this host.
3. Real scooter BLE advertisement name, service/characteristic UUIDs, notification cadence, read/write paths, and acknowledgements still require hardware capture/validation.
4. AccessorySetupKit descriptors cannot be finalized until the scooter's advertisement/service identity is observed.

## Protocol status
See `PROTOCOL_NOTES.md`.

## Ride engine / recovery status
See `docs/RIDE_ENGINE.md`, `docs/RIDE_PERSISTENCE.md`, `docs/RIDE_RECONCILIATION.md`, and `docs/LIVE_DISTANCE_INTEGRATION.md`. Idempotent history handoff, conservative reconciliation, and process-local raw-speed segment integration exist; the concrete SwiftData history adapter, route chunks, crash-safe ride-level distance aggregation, app-level coordinator wiring, and calibrated MAXSHOT policies remain pending.

## Design status
See `DESIGN_SYSTEM.md` and `docs/NAMING.md`.

## Current quality gate
Do **not** move the product milestone to landscape Dashboard as “finished Home” until the Home slice has been built/run on iOS 27, interacted with, screenshotted, self-critiqued, fixed, and retested. Work that does not depend on Simulator/hardware may continue, but completed status must remain truthful.

## Next exact actions on a macOS/Codex continuation
1. Locate this existing checkout and inspect `feature/live-distance-accumulator`, `feature/distance-reconciliation`, `feature/ride-history-reconciliation`, `feature/ride-checkpoint-persistence`, `feature/ride-engine-core`, `feature/simulation-config-safety`, `feature/simulation-reconnect-hydration`, `feature/rolling-speed-digits`, `feature/home-stale-state-truth`, `feature/speed-display-model`, `feature/telemetry-benchmark`, and `feature/home-vertical-slice`; do not recreate any branch.
2. Keep the existing public GitHub repo `jonathangana131-lab/Nembra` as the remote source of truth. Publish the current feature branch through the connected GitHub tooling; preserve the local checkpoint history and do not regenerate the project.
3. Open `Nembra.xcodeproj` with Xcode 27 from the current branch and build **before changing product code**; it includes the Home checkpoint, raw telemetry instrumentation, and hardware-gated production bootstrap.
4. Fix any SDK/typecheck/project issues found by the real iOS 27 build.
5. Run on an iPhone 12-class iOS 27 Simulator.
6. Interact with reconnect, light, lock confirmation, every supported mode, All Controls, cruise, and start mode. Verify no mode-specific speed-limit control appears until a mapping is proven.
7. Capture actual connected/disconnected/pending/error Home screenshots and critically inspect hierarchy, safe areas, Dynamic Type, glass stacking, and command-state truthfulness.
8. Fix every issue found; add UI tests where stable.
9. Commit the validated slice, push, open/merge a PR into stable `main` only when green.
