# App-Target NembraCore Source Visibility Audit — 2026-08-06

## Scope

This is a source/integration audit against `main@909b0c6f74af9744f33558d88185f3917e900c54` plus current in-flight PR evidence. It changes no Xcode project, Swift source, package manifest, app bootstrap, persistence, Bluetooth, battery/range, ride, route, navigation, or hardware behavior.

The purpose is narrow: prevent a NembraCore change from being package-correct but invisible to the iOS app target when an app file begins consuming that type.

## Current build boundary

`Packages/NembraCore/Package.swift` declares a normal `NembraCore` Swift package target with source auto-discovery. Package builds/tests therefore see source files in `Packages/NembraCore/Sources/NembraCore` automatically.

The production iOS target does **not** currently link that package product as a target dependency. Instead, `Nembra.xcodeproj/project.pbxproj` manually references selected NembraCore source files and places those selected files directly in the `Nembra` PBX sources build phase.

At the audited main head, the app target manually includes these 16 NembraCore files:

- `VehicleDomain.swift`
- `ScooterService.swift`
- `SimulatedScooterService.swift`
- `SpeedTelemetry.swift`
- `TelemetryBenchmark.swift`
- `UnverifiedScooterService.swift`
- `SpeedDisplayInterpolation.swift`
- `RollingNumberModel.swift`
- `SimulationConfiguration.swift`
- `RideEngine.swift`
- `RideCheckpointPersistence.swift`
- `RideCheckpointCoordinator.swift`
- `RideHistoryCommit.swift`
- `RideDistanceReconciliation.swift`
- `LiveDistanceIntegration.swift`
- `RideLocationEvidence.swift`

This means the following implication is invalid:

> `swift test` for NembraCore passed, therefore a new NembraCore type is available to Nembra.app.

Package correctness and app-target source visibility are separate acceptance facts in the current project shape.

## Proven failure mode

This is not hypothetical. Recovery PR #28 records a historical exact case: project validation and all 227 NembraCore tests passed, then app compilation failed because standalone `RideTransportGapEvidence.swift` was absent from the manually wired app target. The recovery avoided `project.pbxproj` contention by moving that declaration into an already compiled source file.

The lesson is architectural rather than specific to that type: package-only success must never be promoted to app-integration proof when the app consumes a newly introduced NembraCore declaration.

## Current live integration matrix

| Lane / PR | Core source visibility state | App-consumption state | Integration consequence |
| --- | --- | --- | --- |
| Battery primary readout #57 | `BatteryPrimaryReadoutState.swift` exists on main but is not in main's app-target source list. #57 explicitly adds its PBX file reference, Core group entry, and Sources build-phase entry. | #57's `DashboardView.swift` consumes `BatteryPrimaryReadoutMode` and related readout types. | Correct current pattern. #57 is the Class-A `project.pbxproj` owner; other workers must not race it. |
| Battery presentation transition #45 | Transition logic is intentionally co-located in `BatteryPrimaryReadoutState.swift`. | Future Dashboard use can ride the same source-visibility boundary after #57's wiring is accepted. | No second project entry is required solely for #45's co-located declarations. This reduces Class-A contention without changing truth semantics. |
| Ride route evidence summary #74 | Adds package-only `RideRouteEvidenceSummary.swift`; it is not in the audited main app-target source list. | #75 removed its provisional route-summary consumption and now changes only completed-row accessibility semantics. Future route accessibility still intends to consume #74's boundary. | #74 can remain package/domain work. A future app consumer must obtain explicit app-target visibility from the active/future Class-A project owner before referencing the type. This is **not** a current blocker for narrowed #75. |
| Adaptive range core #40 / assembler #54 / range bridge #38 | Their accepted/recovered work is package-domain work, not part of audited main's manually selected app sources. | Current production Dashboard does not yet have the accepted numeric adaptive-range bridge. | When numeric range integration begins, determine the complete accepted source dependency closure and coordinate one deliberate app-target wiring packet. Do not guess a single file from the top-level type name. |
| Battery evidence chain #34 → #48 → #51 → #52 → #56 | Package-domain chain; none of these active lane files are in the audited main app-target source list. | No current production app path should treat these pending software evidence layers as verified physical ES80 telemetry. | Keep package acceptance separate. Wire only the accepted pieces actually needed by a future app consumer, under one Class-A owner and without promoting software evidence to physical truth. |
| Navigation core #41 / MapKit adapter #77 | Separate package work; audited app target has no NembraCore package-product dependency and no MapKit-navigation package-product dependency. | Production navigation UI wiring remains future work. | Future app integration needs an explicit build-system decision at the integration boundary; package tests alone are not app-target proof. |

## Main-vs-#57 concrete proof

At main, `BatteryPrimaryReadoutState.swift` is a valid NembraCore package source but has no PBX file reference or app Sources build-phase entry.

PR #57 adds exactly the three project-level pieces required by the existing manual-source model:

1. `PBXFileReference` for `Packages/NembraCore/Sources/NembraCore/BatteryPrimaryReadoutState.swift`;
2. inclusion in the Xcode `Core` group;
3. `PBXBuildFile` inclusion in the `Nembra` Sources build phase.

That delta is the current concrete example of app-target visibility being handled intentionally rather than assumed from package membership.

## Integration acceptance rule

Until the project architecture changes deliberately, any PR that makes an app-target Swift file reference a declaration defined in `Packages/NembraCore/Sources/NembraCore` must prove one of the following on its **exact final composition**:

1. the defining source and every required same-module source dependency are already present in the `Nembra` app target; or
2. the responsible Class-A integration owner adds the required project wiring in the same dependency sequence before the app consumer is accepted.

A package-only green run is insufficient for this specific gate. The exact app target must compile under Xcode after the final wiring composition.

Do not make multiple feature workers independently edit `project.pbxproj` to satisfy this rule. The coordination cure for a visibility gap must not create a Class-A merge race.

## Review checklist for new package-domain lanes

Before an app-layer consumer lands:

- identify the exact declaration being consumed and the source file that owns it;
- check current `project.pbxproj`, not just `Package.swift`;
- check whether the declaration's source depends on other NembraCore sources that are also absent from the app target;
- identify the current Class-A project owner in swarm control;
- make the wiring dependency explicit in the producer/consumer PR body;
- require exact final-head Xcode app compilation after wiring;
- keep package-only validation labeled package/software evidence;
- never use a build-system integration success as physical AOVOPRO ES80 validation.

## Structural follow-up, not part of this lane

Linking the app target to the `NembraCore` Swift package product instead of manually compiling selected package sources could remove this entire class of per-file visibility failures. That would be a high-contention project-architecture change, not a cleanup to sneak into an unrelated feature. It should only be evaluated by an explicit Class-A architecture/integration owner after current project-file work clears and with exact-head Xcode/Simulator proof.

This audit does **not** recommend changing that architecture during active #57 ownership.

## Truth / hardware boundary

This audit concerns build graph visibility only. It does not:

- classify any battery value as measured;
- enable adaptive range;
- decode BLE/Tuya payloads;
- alter ride or route evidence;
- add navigation behavior;
- send scooter writes;
- claim physical AOVOPRO ES80 verification;
- claim physical iPhone performance.

Software/package/Xcode build evidence remains separate from real scooter hardware evidence.