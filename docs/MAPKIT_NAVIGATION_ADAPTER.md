# Apple MapKit navigation adapter

Date: 2026-08-06
Worker: `chat-j9r2w`
Lane: `mapkit-navigation-adapter`
Parent: PR #41 exact head `90e28f72587bdc7f18827f89a2dcb4faead4666d`

## Scope

This dependent lane introduces an isolated `NembraMapKitNavigation` Swift package above NembraCore. It does not wire MapKit into the production app, Xcode project, Dashboard, Home, ride persistence, or hardware service.

Current implementation now has three layers:

1. **MapKit projection**
   - projects `NavigationRoutePlanRequest` into current `MKDirections.Request` values;
   - creates endpoints with current `MKMapItem(location:address:)` instead of deprecated placemark APIs;
   - maps documented MapKit error codes into Nembra's stable route-plan failures;
   - extracts `MKPolyline` coordinates in order;
   - projects `MKRoute` and `MKRoute.Step` facts into immutable Nembra route/step snapshots;
   - preserves requested versus returned transport provenance;
   - leaves unknown/combined future returned transport as `.unknown` rather than guessing.

2. **Provider-neutral async operation coordinator**
   - runs any injected directions operation under an already-generated Nembra request token;
   - removes operation identity before calling transport cancellation;
   - rejects late success/error after cancellation as `.cancelled`;
   - rejects duplicate active use of one token without replacing the original operation;
   - permits independent request tokens to run concurrently;
   - fails closed on empty provider routes;
   - supports cancel-one and cancel-all without trusting provider callback timing for correctness.

3. **Concrete MapKit operation wrapper**
   - creates `MKDirections(request:)` from the projection layer;
   - awaits `MKDirections.calculate()`;
   - projects returned routes through `AppleMapKitRouteProjection`;
   - forwards `cancel()` to MapKit;
   - deliberately carries no generation state because race correctness remains in the provider-neutral coordinator.

The concrete wrapper is server-capable code, but this lane does not call Apple routing servers during deterministic tests.

## Current Apple API facts checked

Current Apple Developer documentation was rechecked on 2026-08-06 before implementation:
- `MKDirections.Request` exposes source, destination, transport type, alternate-route request, highway preference, and toll preference;
- `MKDirections.RoutePreference` currently exposes `.any` and `.avoid`;
- `MKDirectionsTransportType` includes cycling;
- `MKMapItem(location:address:)` and `MKMapItem.location` are current, while `MKMapItem(placemark:)` / `placemark` are deprecated;
- `MKDirections(request:)`, asynchronous `calculate()`, and `cancel()` provide the concrete directions operation surface;
- `MKRoute` exposes polyline, steps, name, distance, expected travel time, highway/toll flags, advisory notices, and overall transport type;
- `MKRoute.Step` exposes polyline, instructions, optional notice, distance, and transport type;
- step transport may differ from route transport;
- `MKMultiPoint.getCoordinates(_:range:)` and `pointCount` provide polyline coordinate extraction;
- MapKit documents `directionsNotFound`, `placemarkNotFound`, `loadingThrottled`, `serverFailure`, `decodingFailed`, and `unknown` error codes.

## Truth boundaries

- MapKit cycling remains a cycling-route suggestion, never scooter-legality or ES80-safety proof.
- Provider route geometry/distance/ETA is navigation information only and cannot become ride GPS distance, measured speed, or battery evidence.
- Provider localized instruction/notice/advisory strings are preserved as provider strings.
- Returned transport combinations that do not exactly match one known Nembra mode remain `.unknown`.
- An `.unknown` request transport fails closed instead of silently becoming `.any`.
- MapKit decoding/projection-domain failure maps to invalid provider response; undocumented/future platform errors map to unknown.
- `MKDirections.cancel()` is not treated as the correctness mechanism. Nembra removes/invalidates operation identity first; any racing late provider callback is rejected afterward.
- This package is Apple-platform infrastructure, not physical AOVOPRO ES80 evidence.

## Verification — provider-neutral async layer

The provider-neutral operation coordinator is compiled and tested with the real Swift 6.2.1 toolchain on Linux against the actual NembraCore request/token/domain types used by this dependent branch.

**Current deterministic async result: 9/9 tests passed.**

Coverage:
1. successful route completion;
2. empty route arrays fail closed;
3. provider failures use injected stable mapping;
4. factory failures are mapped before active state is installed;
5. cancellation removes identity before a late successful completion can publish;
6. a late provider error after cancellation still resolves as cancelled;
7. independent request tokens can be in flight concurrently;
8. duplicate use of one active token is rejected without replacing the original operation;
9. cancel-all invalidates every in-flight operation.

Adding the concrete `#if canImport(MapKit)` wrapper leaves this Linux suite **9/9 green**.

Exact GitHub-verified coordinator blobs:
- coordinator source: `ae46524259422ef33443af78920abed3a97be771`
- coordinator tests: `756631f9724c4af0fe4e40534505ad17d437fccb`

## Verification — Apple-specific projection/wrapper without Apple SDK

The current chat execution environment does not expose the real MapKit SDK/Xcode toolchain. Apple-specific evidence is therefore deliberately weaker and classified separately:

1. repository-layout SwiftPM manifest parses/resolves its local NembraCore dependency shape;
2. exact projection, concrete wrapper, and Xcode-only test source pass Swift 6.2.1 parsing;
3. projection + provider-neutral coordinator + concrete MapKit wrapper type-check together against synthetic `MapKit`, `CoreLocation`, and `NembraCore` modules shaped to the current Apple-documented signatures listed above;
4. synthetic type-check is contract/API-shape evidence only and is **not** claimed as Apple SDK compilation.

Exact GitHub-verified blob identities:
- manifest: `a6823e0cde290448b4b0b736aa93c758a2d2b1ff`
- projection source: `25e29475d51a7061e59f626f6478e05577d0cc9c`
- projection tests: `9bec65a75836b732c01e67f849a54c48040c9857`
- concrete MapKit operation: `c65b83c081787ecb6681b090ac32bc3a35da9a3a`

## Xcode-only deterministic tests prepared

When this package is compiled with MapKit/CoreLocation available, the focused projection tests cover:
- cycling endpoint/request preference projection;
- current `MKMapItem.location` endpoint round-trip;
- unknown request transport rejection;
- documented MapKit error mapping;
- future/combined returned transport remaining unknown;
- `MKPolyline` coordinate order preservation;
- provider route and step fact projection through a server-independent fake route reader;
- route and step provider totals remaining independent;
- exact instruction/notice/advisory preservation.

The async cancellation/race semantics do not require MapKit and are already covered by the 9 Linux tests above. Xcode CI therefore does not need live Apple route-server access to prove those semantics.

## Required next gate

Before this adapter is accepted or wired into the app:
1. compile `NembraMapKitNavigation` with the real Xcode 27/iOS 27 SDK;
2. run its focused projection tests on the Xcode runner;
3. inspect/fix real SDK API, availability, or Swift concurrency failures rather than treating synthetic type-check as proof;
4. keep CI independent of live Apple directions servers;
5. after parent PR #41 is accepted, reconcile/retarget this dependent lane onto fresh main and rerun its exact final-head package gate.

## Hardware status

**PUBLIC API RESEARCH + SOFTWARE IMPLEMENTATION ONLY.** The async coordination layer is deterministically tested in software; the MapKit-specific layer still awaits real Apple-SDK compilation. No physical ES80, outdoor GPS, route-quality, legality, or physical iPhone behavior is verified by this package.
