# Apple MapKit navigation adapter

## Purpose

`Packages/NembraMapKitNavigation` is Nembra's Apple-provider bridge above the platform-neutral navigation domain in `NembraCore`.

It owns provider request/response projection, provider-operation lifetime, route alternatives, explicit route selection, navigation experience composition, semantic presentation, and accessibility-worthy guidance announcements.

`NembraMapKitNavigationSimulation` is a separate server-free SwiftPM product for deterministic Simulator/QA composition.

This package is intentionally **not** production app wiring. Adding the package does not by itself place MapKit navigation in Home, Dashboard, ride history, battery/range, Bluetooth, or vehicle-control surfaces.

## Truth boundaries

These boundaries are permanent product rules:

- MapKit cycling directions are **cycling-route suggestions**, never proof that a route is legal, safe, accessible, or appropriate for an AOVOPRO ES80.
- Provider route geometry, distance, ETA, highway/toll flags, advisories, instructions, and notices remain **provider navigation facts**.
- Provider route distance/ETA never becomes measured ride distance, speed, odometer, battery/range evidence, or completed-ride truth.
- Provider instruction/notice strings are preserved rather than parsed into invented maneuver semantics.
- No provider route is automatically called "best", safest, preferred, or scooter-approved.
- `MKDirections.cancel()` is not an acknowledgement and is not the correctness mechanism for stale-result rejection.
- Process-local receipt chronology is delivery-order evidence only. It is not GPS measurement time, route progress, ride duration, or physical vehicle telemetry.
- Simulation responses are QA fixtures and never physical/outdoor/ES80 evidence.

## Package products

### `NembraMapKitNavigation`

Production-facing, UI-neutral composition containing:

- current Apple MapKit request projection;
- current Apple MapKit route/step projection;
- stable MapKit error projection into Nembra failure semantics;
- token-owned provider-operation lifetime;
- route-planning service composition;
- explicit route-alternative selection;
- navigation experience composition;
- semantic presentation projection;
- guidance-announcement deduplication;
- destination-search state.

### `NembraMapKitNavigationSimulation`

Server-free scripted directions provider used only for deterministic development/QA. It consumes explicit route/failure responses in order and never invents a route when no response was configured.

## Apple MapKit projection

`AppleMapKitRequestProjection` converts `NavigationRoutePlanRequest` into current `MKDirections.Request` values.

The adapter:

- uses `MKMapItem(location:address:)` rather than deprecated placemark construction;
- preserves requested transport, alternate-route preference, highway preference, and toll preference;
- supports current MapKit cycling requests without relabeling them as scooter routing;
- rejects `.unknown` request transport instead of guessing;
- preserves provider polyline order;
- projects route and step distance, ETA, transport, notices, advisories, highway/toll facts, and localized instruction strings;
- maps future/combined returned transport values to `.unknown` rather than guessing a known mode;
- fails closed when provider facts cannot satisfy Nembra's immutable route-domain invariants.

The package platform floors are intentionally compatible with this current MapKit surface (`iOS 26+` and `macOS 26+`) and with Nembra's iOS 27 product baseline.

## Provider-operation lifetime

`NavigationDirectionsOperationCoordinator` runs injected provider operations under Nembra's existing monotonic route-request token.

Correctness does not depend on provider cancellation winning a race. The coordinator:

- rejects duplicate active use of one token;
- removes operation identity before cancellation;
- rejects late completion after removal as cancelled/stale;
- permits independent request tokens concurrently;
- fails closed on empty provider route arrays;
- supports single-token and all-operation cancellation.

The concrete `AppleMapKitDirectionsOperation` deliberately carries no generation state. It only executes `MKDirections.calculate()`, projects returned routes, and forwards `cancel()`.

## Planning-service composition

`NavigationRoutePlanningService` composes NembraCore planning state with provider lifetime.

Important ordering rules:

- supersession invalidates the old planning generation before cancelling its provider operation;
- a late superseded completion cannot publish into the newer planning state;
- explicit cancellation invalidates product state before provider cancellation;
- reset uses `NavigationRoutePlanningCoordinator.reset()` as the single product-state transition, receives the exact active token if one existed, then cancels that provider operation;
- provider cancellation therefore never exposes a transient product state that can be mistaken for accepted route truth.

## Explicit route selection

Route alternatives always start unselected.

`NavigationRouteSelectionID` binds a visible option to:

1. the exact planning request token;
2. the exact route index in that immutable result set;
3. the immutable route facts themselves.

A delayed selection from a replaced planning generation therefore fails closed instead of retargeting the same numeric index in a newer result array.

## Navigation experience composition

`NavigationExperienceCoordinator` composes planning, route alternatives, explicit selection, and `NavigationSessionCoordinator`.

Important behavior:

- a new plan can run while an already selected route remains active;
- returned alternatives never replace active navigation until the user explicitly selects one;
- failed replanning can leave current guidance intact;
- workflow generation rejects a late superseded `plan()` return;
- cancelling planning does not silently clear an already selected route;
- only `QualityScreenedRideLocation` reaches navigation guidance/reroute logic.

### Route-selection receipt fence

For callers whose route-selection event can race with already-screened asynchronous location delivery, use:

`selectRoute(_:receiptFence:)`

The fence must use the same monotonic receipt clock as `RideLocationSample.receivedAtUptimeNanoseconds`.

The session accepts the route/fence **before** presentation selection is committed. If the fence regresses or otherwise fails current session chronology, the call fails transactionally: the previous selected route/presentation remains intact.

The legacy `selectRoute(_:)` overload remains source-compatible for strictly serialized callers. It does not erase a stronger receipt floor already proven inside the navigation session.

## Presentation and accessibility semantics

`NavigationPresentationProjector` emits UI-neutral semantic state:

- planning/requesting/failed/alternatives state;
- generation-bound route-option identity;
- provider distance/ETA/highway/toll/advisory facts;
- requested and returned transport provenance;
- selected-route identity;
- active/unavailable guidance;
- provider current/next instruction and notice strings;
- unit-neutral remaining distances.

It does not choose a route, infer maneuver icons from localized text, choose user units, or reinterpret provider estimates as ride telemetry.

`NavigationGuidanceAnnouncementTracker` deduplicates accessibility-worthy maneuver/unavailable changes independently from GPS/render cadence. Changing remaining-distance estimates alone does not create repeated announcements.

## Deterministic verification model

Acceptance is layered because the package contains both provider-neutral logic and Apple-SDK-specific code.

### Provider-neutral logic

Run the package tests with Swift warnings treated as errors. Adversarial coverage should include at least:

- cancellation and late-callback rejection;
- request supersession;
- route-generation identity;
- transactional route selection;
- reset ordering;
- receipt-fenced route selection;
- presentation projection;
- announcement deduplication;
- simulation-provider behavior.

### Real Apple SDK

A real Xcode 27 / MapKit compile is required for Apple-facing acceptance. Documentation-shaped synthetic modules or Linux `canImport(MapKit) == false` builds are useful supporting evidence but do **not** prove the current Apple SDK surface.

The real-SDK gate must compile and execute the MapKit projection tests without live directions-server dependence. Live Apple routing responses are not required for deterministic CI.

## Production integration boundary

Merging this package is not the same as shipping navigation UI.

Production app wiring should happen only after the package is accepted against current NembraCore and the real Apple SDK, then proceed through normal Nembra app-visible acceptance:

1. explicit app composition and lifecycle ownership;
2. destination/route-selection UX;
3. Dashboard cockpit integration while keeping speed primary;
4. quality-screened location delivery using the strong receipt-fence path where asynchronous delivery can race selection;
5. reroute/arrival integration without turning provider routes into ride measurement;
6. Simulator interaction/screenshots and accessibility review;
7. iPhone 12 performance validation;
8. outdoor/physical validation kept clearly separate from Simulator/software evidence.

## Hardware status

**SOFTWARE + PUBLIC APPLE API ONLY.**

This adapter does not verify AOVOPRO ES80 protocol semantics, physical route legality, outdoor route quality, GPS field behavior, or physical iPhone performance. Those remain separate evidence domains.