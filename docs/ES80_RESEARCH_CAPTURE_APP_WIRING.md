# ES80 Research Capture App Wiring

Status: **dependent app-integration slice; software/Simulator only until physical execution**

Worker lane: `parallel/es80-research-capture-app/chat-x5n7q`

Dependency: passive-capture recovery PR #239 / `parallel/recover-es80-passive-capture-runtime/chat-c7m2q`.

## Product outcome

Nembra now has an explicit app launch path for the existing `ES80PassiveCaptureResearchView` instead of leaving the physical-capture capability stranded inside a Swift package.

This is research tooling, not production scooter control. The normal app launch remains the default and starts the existing `AppRuntime` exactly as before. The research launch deliberately does **not** start that runtime.

In Debug builds, either of these selects the passive capture shell:

- launch argument: `--es80-passive-capture`
- environment: `NEMBRA_ES80_PASSIVE_CAPTURE=1`

Release builds ignore those selectors and use the standard app path.

## Safety / truth boundary

The app wiring does not add a Bluetooth characteristic write path and does not reinterpret the parent package's passive acquisition semantics.

The research controller:

- performs broad foreground discovery without assuming a service family;
- requires explicit peripheral selection before target-labelled evidence exists;
- reads only where CoreBluetooth reports `.read`;
- subscribes only where CoreBluetooth reports notify/indicate capability;
- records raw attribution, timing, topology, reads, subscriptions, and notifications;
- fails closed when a finite acquisition is incomplete;
- keeps stock-app values as correlation markers rather than protocol truth;
- never turns a CoreBluetooth UUID or the app's `VehicleIdentity` label into proof of physical ES80 identity.

The app-supplied identity (`AOVOPRO ES80 research target`, protocol family `unverified-passive-research`) is an operator/research label only.

## App lifetime separation

Research capture is intentionally a separate launch mode rather than a hidden button inside Home or Dashboard. This avoids:

- starting normal scooter service and ride persistence alongside the research central;
- presenting vehicle controls next to unverified protocol acquisition;
- accidentally suggesting captured fields are already production telemetry;
- adding conflict-heavy Home/Dashboard/AppRoot edits before physical evidence exists.

The `ForegroundCoreBluetoothCaptureController` is created once for the app launch and retained for the research surface's lifetime.

## Simulator acceptance

Simulator QA proves only that:

- the local capture package is actually linked into `Nembra.app`;
- the explicit launch selector resolves to the ES80 capture navigation surface;
- the passive-only warning remains visible;
- the scan control exists;
- the normal `Vehicle controls` surface is absent;
- the app can render the research shell without claiming any physical Bluetooth result.

The UI test does not tap **Start scan**, connect to a peripheral, manufacture CoreBluetooth callbacks, or convert Simulator behavior into physical evidence.

## First physical experiment after combined build acceptance

Use the parent runbook's smallest first action; do not jump directly to field decoding:

1. install the accepted Debug build on the iPhone 12 / iOS 27 target;
2. launch Nembra with `--es80-passive-capture`;
3. keep the ES80 powered on, stationary, charger state noted, and do not enable any unknown command path;
4. tap **Start scan** with duplicate-advertisement capture off;
5. physically correlate the likely scooter candidate, then explicitly choose **Select & connect** for that candidate;
6. let service / included-service / characteristic / descriptor discovery and permitted read/subscription acquisition drain completely;
7. keep the stationary session running for about 60 seconds;
8. export JSON only if the UI reports healthy complete target evidence;
9. stop and inspect the immutable artifact before proposing any Tuya framing or field mapping.

Expected evidence is real advertisement identity, real GATT topology/properties, passive value streams, provenance, raw cadence, and continuity boundaries. It is **not** yet battery/current/power/speed semantics.

## Dependency / merge rule

This branch is intentionally based on PR #239's exact recovery head and should target that branch while #239 remains unmerged. It must not duplicate or rewrite the parent package. After the passive-capture parent lands, reconcile this app-wiring slice onto the accepted descendant and rerun exact-head Xcode 27 / iPhone 12 / iOS 27 acceptance before main integration.
