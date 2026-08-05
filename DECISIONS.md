# DECISIONS

## D-001 — Working product name: Nembra
**Status:** accepted for development, preliminary clearance only.

Why: short, calm, credible as a multi-vehicle platform, and materially less conflicted in the initial software/App Store/GitHub sweep than alternatives reviewed. It avoids “control,” “scooter,” and a specific OEM in the brand itself.

Not a legal conclusion: Nembra is also a place name in Asturias, Spain. Formal trademark/domain clearance remains a release milestone.

## D-002 — MAXSHOT first, capability model from day one
The code models capabilities rather than scattering model-name conditionals. Only the MAXSHOT V1S Pro profile is currently populated.

## D-003 — Real commands are pessimistic/confirmed, not optimistic
A UI tap becomes pending intent. State changes only after the service reports success/current state. This prevents the UI from lying when a command times out or the scooter rejects a value.

## D-004 — Simulation is a first-class service, not fake production state
Simulation conforms to the same domain contract as future real Bluetooth. Simulated records must be clearly isolated from real ride data when persistence arrives.

## D-005 — Observation-first Bluetooth integration
No unknown writes to a motorized vehicle. Real BLE work begins with discovery, service/characteristic inventory, notifications, reads, packet logging, and parser tests.

## D-006 — Liquid Glass belongs to controls/chrome, not every content surface
Use current native iOS glass APIs for interactive chrome where they clarify hierarchy. Vehicle content and metrics remain visually grounded rather than stacked translucent cards.

## D-007 — Route mode is never labeled “scooter-safe”
MapKit exposes automobile, cycling, walking, transit, and any transport modes—not a dedicated e-scooter routing guarantee. Routing UI must communicate this honestly.

## D-008 — Measured telemetry and display interpolation are distinct
Future rolling-speed rendering may interpolate visually, but raw BLE/GPS samples remain separately timestamped and authoritative.

## D-009 — Device trip is not “Today” mileage
The scooter-reported trip counter and Nembra's future daily ride ledger are separate concepts. Until a daily ledger is derived from persisted ride sessions, the UI labels the device value **Scooter Trip** and never implies it resets at midnight.

## D-010 — AccessorySetupKit must be evaluated before finalizing onboarding/background BLE
Apple's current iOS relaunch guidance makes AccessorySetupKit strategically relevant for Bluetooth accessories. Nembra should prefer it if the MAXSHOT advertisement/service identity can be described correctly and hardware testing confirms the flow. We will not invent discovery descriptors before observing the real scooter.


## D-011 — Unknown vehicle state stays unknown
A state field is optional when the app can legitimately lack evidence for it. In particular, ride mode is not defaulted to Sport while disconnected/launching. UI placeholders show an unknown value until the scooter service reports one.


## D-012 — Do not expose unfinished navigation destinations
The production shell shows only completed vertical slices. Placeholder Rides/Stats tabs were removed; those destinations return only when their real engines and polished UI are ready for end-to-end QA.

## D-013 — Protocol slots before convenience mappings
The MAXSHOT audit verifies DP101, DP102, and DP103 as three writable speed-limit slots with distinct ranges, but does not verify which slot corresponds to Walk/Eco/Normal/Sport. Nembra models the slots directly and leaves the ride-mode mapping empty. Normal user UI must not expose a mode-specific limiter until hardware/protocol evidence establishes that relationship. Generic YouFS material saying each gear speed can be adjusted increases plausibility, but does not prove the exact MAXSHOT mapping.

## D-014 — Serialize commands and bind them to one connection generation
Until real MAXSHOT acknowledgement/transaction behavior is captured, Nembra allows only one state-changing scooter command at a time. A command captures the current connection generation before waiting for acknowledgement; any disconnect, reconnect, or replacement connection invalidates that generation. A fast reconnect must never resurrect a write that started on the previous link. Competing controls remain unavailable while confirmation is pending, and unknown lock/headlight state is never treated as confirmed “off.”

## D-015 — Connection failures are typed, not one generic “offline” state
Bluetooth powered off, Bluetooth permission denied, scooter unavailable, and unsupported hardware/firmware have different recovery actions. Domain state preserves those distinctions so the UI can offer Settings only for permission denial, retry only when retry can help, and never fake a successful reconnect while iOS or compatibility checks are blocking the connection.

## D-016 — Raw telemetry is immutable evidence; render interpolation is a separate layer
BLE/GPS/motion evidence is timestamped before UI treatment. Benchmarking consumes only those raw samples. Future display interpolation may render at the screen refresh rate, but interpolated frames never become ride measurements, acceleration-test samples, odometer evidence, or telemetry benchmark input. BLE and GPS are tagged as absolute measurements; motion-assisted speed is structurally limited to a short-horizon estimate and cannot masquerade as authoritative speed.

The ordinary vehicle-state stream may replay cached state to initialize UI, but the raw speed telemetry stream does not replay cached speed as a fresh measurement. Doing so would create a fake packet arrival and corrupt cadence, jitter, and latency evidence.

## D-017 — Production launch never defaults to simulation
Simulation is an explicit QA backend selected only by a documented launch argument or environment variable. Until a real MAXSHOT Bluetooth configuration is verified, an ordinary Nembra launch uses `UnverifiedScooterService`: disconnected, unsupported configuration, no fabricated telemetry, no automatic connection, and no state-changing commands. A developer forgetting to set a simulation scenario must see an honest blocked state rather than a convincing fake scooter.

## D-018 — Display speed interpolation is render-only and non-predictive
`SpeedDisplayInterpolator` accepts only authoritative absolute measurements and emits a distinct `SpeedDisplayFrame`, never telemetry. It transitions from the exact currently rendered value toward the newest measurement, can be interrupted safely by a newer packet, never overshoots or predicts beyond the newest evidence, and rejects motion-assisted short-horizon estimates. Equal consecutive measurements complete immediately instead of creating fake motion. Transition duration remains caller-injected until real MAXSHOT cadence and iPhone 12 runtime QA justify tuning. Visual frames can never become ride, acceleration-test, odometer, benchmark, or persistence evidence.
## D-019 — Transport loss never manufactures zero telemetry
A disconnect, Bluetooth failure, or out-of-range event is a transport-state change, not a speed/power measurement. Nembra preserves the last confirmed vehicle readings and marks them stale/read-only through connection state rather than overwriting speed, power, or current with zero. Only a real authoritative sample may establish a new measured zero. The same rule must be preserved by the future real Bluetooth implementation.

## D-020 — Vehicle data availability is explicit
Vehicle values have three presentation states: `unavailable` when nothing has ever been confirmed, `live` when confirmed values belong to the current connected session, and `retained` when confirmed values survive a transport loss and must be shown read-only. UI code should consume this domain distinction instead of guessing freshness from optional fields alone.

## D-021 — Rolling instrumentation uses fixed slots and value-direction motion
Rolling numeric UI is driven by `RollingNumberModel`, a render-only fixed-slot plan independent of telemetry. Integer/fraction geometry stays reserved so 9→10 or 99→100 cannot resize the dashboard. When the overall value rises, affected digits roll upward through carries; when it falls, they roll downward through borrows. Hidden leading digits use reserved zero placeholders only for geometry and are never presented as measured zeroes. The model stores no timing and cannot become ride evidence. Layout precision is capped at 15 decimal digit slots because the public input is `Double`; this avoids pretending to preserve integer precision beyond what the type can reliably represent.

## D-022 — Simulated reconnect hydrates missing state without replacing retained evidence
The explicit QA simulator models a successful handshake by filling only vehicle fields that were previously unknown. Retained confirmed values survive reconnect unchanged. This makes `cold-disconnected` useful for reconnect UI QA without turning a reconnect into a reset. These values are simulation fixtures only; the future Bluetooth service must populate state from actual reads/notifications rather than copying simulator defaults.

## D-023 — Simulation launch configuration fails closed
Simulation is opt-in QA infrastructure. A present-but-invalid environment value, malformed launch argument, or duplicate simulation launch arguments are treated as invalid configuration rather than guessed or allowed to fall through to a lower-priority source. `AppBootstrap` responds by using the hardware-gated unverified production service. This makes launch mistakes obvious and prevents a typo from silently selecting a convincing but unintended scooter state.

## D-024 — Ride continuity is domain state and disconnect alone never ends a confirmed ride
`RideEngine` owns automatic ride continuity outside SwiftUI. Detection policy values are injected rather than presented as MAXSHOT truths before field calibration. Motion is candidate-only evidence; authoritative BLE/GPS speed, quality-screened cumulative GPS distance, or scooter ODO growth can confirm a ride. Once confirmed, a transport loss moves the same session to `temporarilyDisconnected` and cannot finalize it by itself. Reconnection either resumes the same session or begins stop confirmation. The crash-recovery journal now preserves this session identity across process lifetime; reconciliation and completed-history storage remain separate later layers.

## D-025 — Ride evidence freshness and accumulation are explicit
`RideEngine` accepts speed only when it is an authoritative BLE/GPS measurement whose arrival age is within an injected policy limit. The limit is not a MAXSHOT constant until hardware traces measure real cadence. GPS route evidence enters as quality-screened incremental distance and is accumulated by the engine; callers cannot present one location update as a whole-route total. Odometer evidence establishes its baseline only when the first value is actually observed, regressions cannot reduce confirmed evidence, and invalid/overflowing evidence is rejected transactionally without advancing phase or the monotonic observation clock. Session-ID generation is injected so replay and crash-recovery tests can preserve deterministic identity.

## D-026 — Ride recovery uses a two-stage durable journal; monotonic uptime never crosses a process boundary
A confirmed ride is checkpointed through `RideCheckpointCoordinator` into a two-slot generation journal. Stable telemetry writes only at an injected cadence, while confirmed-ride transitions write immediately. Process-local monotonic uptime is never persisted. After process recovery, the same durable session/evidence returns conservatively as `temporarilyDisconnected` with historical uptime unknown and must reacquire fresh movement/stop evidence.

Ride completion uses a second durable state, `completedPendingCommit`, before the active journal can be cleared. New ride input remains blocked until the future permanent history ledger durably commits the matching session ID and acknowledges the handoff. If save/clear fails, in-memory state remains retryable rather than silently dropping the ride. The journal's two atomic slots provide fallback against ordinary process interruption/corrupt files, but Nembra does not claim stronger sudden-power-loss durability than the underlying filesystem/Foundation write semantics.

## D-027 — Completed ride history handoff is idempotent and verified before recovery evidence is cleared
The recovery journal and completed history database are separate durability domains. `RideHistoryCommitCoordinator` first commits the exact raw `RideHistoryRecord`, then reads it back and verifies exact session evidence before acknowledging `completedPendingCommit`. Repeating an equivalent session is success (`alreadyPresent`); the same UUID with different evidence is a conflict and must never overwrite history. If commit, readback, or recovery-journal clear fails, the pending journal remains retryable. This makes a crash after the history write but before journal clear converge without creating a duplicate ride. The storage contract is implemented; the concrete production SwiftData adapter remains an iOS/Xcode task.

## D-028 — Distance coverage is complete, partial, or unknown; absence of a gap flag is not proof of completeness
ODO, GPS-route, and future live-integrated distances stay as independent evidence with explicit coverage. Reconciliation policy and source priority are injected and have no MAXSHOT production defaults before field validation. The reconciler never averages sources. ODO may recover mileage across a lower source only when ODO coverage is explicitly complete, the lower source is explicitly partial, the lower distance is actually smaller, and policy enables recovery. Partial/unknown ODO and unknown secondary coverage can never be used to explain away disagreement. Recovered mileage does not reconstruct missing route geometry.

## D-029 — Live trip distance integrates raw authoritative samples in process-local segments
Display interpolation, rolling digits, and motion-assisted estimates never add mileage. `LiveDistanceSegmentAccumulator` integrates one explicitly selected absolute speed source with an injected maximum packet interval and explicit trapezoidal method. It never crosses an oversized sample gap, and invalid/out-of-order/overflow evidence is transactional. In-progress snapshots deliberately do not carry completed coverage; only a finalized monotonic segment may be `complete`, `partial`, or `unknown`. Monotonic uptime is not persisted across process/reboot recovery, so a recovered ride starts a new segment and future ride-level aggregation/reconciliation must account for the gap honestly. There is no MAXSHOT production source/gap threshold until hardware telemetry is measured.
## 2026-08-05 — Public GitHub remote + Xcode 27 hosted Simulator gate

**Decision:** Publish Nembra as `jonathangana131-lab/Nembra` with public visibility per explicit user direction. Use GitHub's `xcode-27` hosted macOS runner as a real iOS 27 build/test/Simulator screenshot gate whenever direct interactive Xcode tooling is unavailable in the active chat.

**Why:** The product still requires real Xcode/iOS runtime proof before Home can be called complete. GitHub announced an `xcode-27` preview runner with Xcode 27 beta and iOS 27 SDK/runtime. A committed CI workflow can therefore produce real `xcodebuild` output and `simctl` screenshots rather than generated mockups or Linux-only claims. Public visibility also makes the repository reachable to the connected @GitHub tool once created.

**Safety/truth boundary:** GitHub-hosted Simulator proof is real runtime evidence, but it is not physical MAXSHOT BLE validation and it is not a substitute for interactive performance profiling on an iPhone 12. The runner is preview infrastructure, so its Xcode/runtime metadata must be archived with screenshots.


## D-030 — Use the official GitHub `xcode-27` preview runner as an additional iOS gate, never as fake local proof
GitHub officially exposes `xcode-27`/`xcode-27-xlarge` hosted runner labels in public preview. Nembra therefore keeps a shared Xcode scheme plus a workflow that runs SwiftPM tests, Xcode Simulator tests, launches explicit QA simulation states, verifies the app process remains alive, captures actual Simulator PNGs, and uploads logs/environment metadata. The workflow is only an additional repeatable gate: it has not run until a remote exists, preview infrastructure may change, and passing CI does not replace interactive iPhone 12 Simulator inspection with @Build iOS Apps.
