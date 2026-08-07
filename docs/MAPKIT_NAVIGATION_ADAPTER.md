# Apple MapKit navigation adapter

Date: 2026-08-06
Worker: `chat-j9r2w`
Lane: `mapkit-navigation-adapter`
Parent: PR #41 current head `a12a2be087825676915a6f9df94b0ddb7690267a`

## Scope

This dependent lane builds the Apple directions bridge and UI-neutral navigation workflow above the platform-neutral NembraCore navigation domain. It remains isolated in SwiftPM and does **not** wire MapKit into the production app, Xcode project, Dashboard, Home, ride persistence, battery/range, BLE, or motorized-hardware control.

Current package products:
- `NembraMapKitNavigation` — production-facing adapter/domain composition;
- `NembraMapKitNavigationSimulation` — explicitly separate server-free Simulator/QA provider.

## Implemented production-facing layers

### Current MapKit projection
- projects `NavigationRoutePlanRequest` into current `MKDirections.Request` values;
- uses current `MKMapItem(location:address:)` / `location`, not deprecated placemark APIs;
- maps cycling, alternate-route, highway, and toll request facts without changing meaning;
- extracts `MKPolyline` coordinates in provider order;
- projects `MKRoute` / `MKRoute.Step` geometry, localized instructions/notices, distance, ETA, transport, highway/toll facts, and advisories into immutable Nembra snapshots;
- documented MapKit errors map into stable Nembra planning failures;
- unknown request transport fails closed;
- combined/future returned transport remains `.unknown`.

### Provider-operation race safety
`NavigationDirectionsOperationCoordinator` runs injected provider operations under Nembra's existing monotonic request token.

It:
- removes operation identity before transport cancellation;
- rejects late success/error after cancellation as `.cancelled`;
- prevents duplicate active use of one token from replacing the original operation;
- permits independent request tokens concurrently;
- fails closed on empty routes;
- supports cancel-one and cancel-all without trusting callback timing.

### Concrete `MKDirections` operation
`AppleMapKitDirectionsOperationFactory` builds `MKDirections(request:)`; its thin operation awaits `calculate()`, projects routes, and forwards `cancel()`.

It deliberately carries no request-generation state. Nembra's provider-neutral coordinator owns correctness if `cancel()` races a late completion.

### Planning-service composition
`NavigationRoutePlanningService` composes NembraCore planning state with provider lifetime:
- supersession invalidates the old planning token before cancelling provider work;
- late first-request completion cannot overwrite the newer planning state;
- explicit cancel publishes cancelled before transport cancellation can race;
- reset cancels active provider work and returns planning state to idle.

### Explicit route selection
`NavigationRouteSelectionState` preserves provider route order but starts **unselected**.

Nembra does not silently promote provider index 0 into "best", safest, legal, or preferred. Only an explicit valid index creates selection; replacing the exact provider result array clears prior index identity.

### App-facing experience coordinator
`NavigationExperienceCoordinator` composes planning, route alternatives, explicit selection, and the parent navigation session.

Important behavior:
- a new plan may run while the current selected route remains active;
- fresh alternatives arrive unselected and do not replace active navigation automatically;
- failed replanning can leave current guidance intact;
- a workflow-generation guard prevents a late superseded `plan()` return from resetting a newer explicitly selected route;
- cancelling planning preserves current navigation while rejecting late result publication;
- only already-screened `QualityScreenedRideLocation` reaches the selected navigation session.

### Semantic presentation projection
`NavigationPresentationProjector` turns the experience snapshot into UI-neutral semantics:
- planning/failed/alternatives state;
- route options with provider order, distance, ETA, toll/highway/advisory facts and transport provenance;
- exact selected-route identity;
- active/unavailable guidance with exact provider current/next instruction and notice strings;
- unit-neutral remaining distances.

It deliberately does **not** infer maneuver icons from localized text, choose a preferred route, hard-code user units, or convert navigation estimates into ride telemetry.

## Deterministic simulation product

`NembraMapKitNavigationSimulation` is a separate SwiftPM product so production MapKit transport does not silently acquire fixture behavior.

`NavigationSimulationDirectionsOperationFactory`:
- consumes explicitly scripted route/failure responses in order;
- records route requests for deterministic QA assertions;
- allows responses to be enqueued;
- fails `.directionsUnavailable` when no response is scripted instead of inventing a route;
- preserves scripted product failure reasons;
- composes through the same planning / route-selection / navigation experience paths used by the adapter.

It performs no network access and is intended for future Simulator/product QA only.

## Truth boundaries

- MapKit cycling is a cycling-route suggestion, never scooter legality, safety, access, or ES80 approval.
- Provider route geometry/distance/ETA is navigation information, not recorded ride GPS distance, measured speed, battery evidence, or completed-history truth.
- Provider localized instruction/notice/advisory strings are preserved as provider strings.
- No maneuver type/icon is invented by parsing localized text.
- No provider route is automatically labeled best/preferred.
- `MKDirections.cancel()` is not the correctness mechanism; Nembra token identity is.
- Simulation responses are QA fixtures and never physical ES80/outdoor evidence.
- No live Apple directions-server traffic is required for deterministic CI.

## Server-independent verification

The repo-layout package was tested cleanly with sibling dependency `../NembraCore` under Swift 6.2.1.

**Current server-independent result: 45/45 tests passed across six suites.**

Covered suites:
- provider operation coordinator: 9;
- planning-service composition: 7;
- explicit route selection: 6;
- experience coordinator: 10;
- semantic presentation: 7;
- simulation directions provider: 6.

The exact GitHub manifest/simulation identities from that clean run are:
- package manifest `ff8183944502b198f503f7885c4e4f5750322cc5`;
- simulation source `c2d06f79143e41bcc558cec5df0a11d1da294192`;
- simulation tests `47d11adb5d0939a32829ec417da153a8244f18fe`.

Other previously verified exact async/UI-neutral blobs remain recorded in PR #77 history/body.

## Apple-specific preflight

The local chat runtime lacks the real MapKit SDK. Before real Xcode execution:
- projection + concrete MapKit operation + real provider-neutral coordinator type-check against synthetic modules shaped to current Apple documentation;
- a stronger synthetic type-check of the Xcode-only projection test suite found a real Swift Testing compile problem (`try` nested inside `#expect` equality);
- that test was corrected by evaluating expected coordinates first;
- the exact authoritative corrected test blob `7bb831c6d6ed616b171a6da4cc96bf5d2a9b9a42` type-checks cleanly in the synthetic testable module.

Synthetic type-check is API-shape evidence only, not Apple-SDK proof.

## Real Xcode evidence path

A CI-only `feature/mapkit-navigation-adapter-chat-j9r2w` mirror preserves adapter source while adding one workflow step to run `swift test` in `Packages/NembraMapKitNavigation` on the repository's `xcode-27` runner.

Latest successfully emitted mirror run before the simulation-target addition:
- run `31133522624`;
- mirror head `50e44bf99453ffb3dbd0f1bc1bfc8b2bc3efb922`;
- latest observed state: queued.

That run covers the MapKit projection/concrete operation and the 39-test package state through semantic presentation. The later simulation target is independently 45/45 green on the real Swift toolchain. An attempted low-level mirror-tree refresh for the simulation target was blocked by the connector write-safety layer, so no alternate mutation path was used to force it.

Parent #41 has its own exact-SHA Xcode run `31132870331` on `a12a2be087825676915a6f9df94b0ddb7690267a`; latest observed state was also waiting for the self-hosted runner.

## Required acceptance sequence

1. Inspect/fix the real Xcode adapter run when the self-hosted runner executes it.
2. Compile/run the Xcode-only projection tests against the real MapKit/CoreLocation SDK.
3. Keep deterministic CI independent of live Apple directions servers.
4. After parent #41 is accepted/merged, reconcile/retarget this lane onto fresh main.
5. Run a final current-head MapKit package gate after that reconciliation.
6. Only then begin production app/SwiftUI wiring.

## Hardware status

**PUBLIC API RESEARCH + SOFTWARE IMPLEMENTATION ONLY.** Server-independent planning, selection, workflow, presentation, and simulation behavior is deterministically tested. MapKit-specific real-SDK validation is still waiting on the Xcode runner. No physical AOVOPRO ES80 routing legality, outdoor GPS behavior, route quality, production thresholds, or physical iPhone behavior is verified here.
