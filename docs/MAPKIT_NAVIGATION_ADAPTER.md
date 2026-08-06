# Apple MapKit navigation adapter

Date: 2026-08-06
Worker: `chat-j9r2w`
Lane: `mapkit-navigation-adapter`
Parent: PR #41 exact head `90e28f72587bdc7f18827f89a2dcb4faead4666d`

## Scope

This dependent lane introduces an isolated `NembraMapKitNavigation` Swift package above NembraCore. It does not wire MapKit into the production app, Xcode project, Dashboard, Home, ride persistence, or hardware service.

Current implementation has four layers:

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

4. **Planning service composition**
   - composes NembraCore's `NavigationRoutePlanningCoordinator` with provider-operation lifetime;
   - superseding a request invalidates the old planning token before cancelling the old provider operation;
   - late first-request completion cannot overwrite a newer available route;
   - explicit cancellation publishes `.cancelled` before transport cancellation can race;
   - reset cancels active provider work and returns product planning state to idle without resetting NembraCore's monotonic request identity.

The concrete wrapper is server-capable code, but deterministic tests do not call Apple routing servers.

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
- Product planning state and provider-operation lifetime use the same Nembra token identity but remain separately fail-closed.
- This package is Apple-platform infrastructure, not physical AOVOPRO ES80 evidence.

## Verification — server-independent async layers

The provider-neutral operation coordinator and planning-service composition compile and run with the real Swift 6.2.1 toolchain on Linux against the actual NembraCore request/token/domain types used by this dependent branch.

**Current combined deterministic async result: 16/16 tests passed.**

Operation-coordinator coverage:
1. successful route completion;
2. empty route arrays fail closed;
3. provider failures use injected stable mapping;
4. factory failures are mapped before active state is installed;
5. cancellation removes identity before a late successful completion can publish;
6. a late provider error after cancellation still resolves as cancelled;
7. independent request tokens can be in flight concurrently;
8. duplicate use of one active token is rejected without replacing the original operation;
9. cancel-all invalidates every in-flight operation.

Planning-service coverage:
10. successful provider result becomes NembraCore `.available` state;
11. provider failure becomes stable `.failed` state;
12. empty provider routes become `.invalidProviderResponse`;
13. superseding a request cancels prior provider work and late first completion cannot overwrite the second state;
14. explicit cancellation wins a late provider success;
15. completed requests cannot be spuriously cancelled;
16. reset cancels active provider work and returns planning state to idle.

Adding the concrete `#if canImport(MapKit)` wrapper leaves the combined Linux suite **16/16 green**.

Exact GitHub-verified async blobs:
- operation coordinator source: `ae46524259422ef33443af78920abed3a97be771`
- operation coordinator tests: `756631f9724c4af0fe4e40534505ad17d437fccb`
- planning service source: `b36bf70105ec08d72a0c73d7c0954338edf9ff01`
- planning service tests: `d7900f1ddef3dcd226ec1294d1ac0dee6d7a8f0c`

## Verification — Apple-specific projection/wrapper before Xcode result

The chat's local execution environment does not expose the real MapKit SDK/Xcode toolchain. Before remote Xcode execution, Apple-specific evidence was deliberately classified separately:

1. repository-layout SwiftPM manifest parses/resolves its local NembraCore dependency shape;
2. exact projection, concrete wrapper, and Xcode-only test source pass Swift 6.2.1 parsing;
3. projection + real async coordinator + concrete MapKit wrapper type-check together against synthetic `MapKit`, `CoreLocation`, and `NembraCore` modules shaped to the current Apple-documented signatures listed above;
4. synthetic type-check is contract/API-shape evidence only and is **not** claimed as Apple SDK compilation.

Exact GitHub-verified Apple-specific blob identities:
- manifest: `a6823e0cde290448b4b0b736aa93c758a2d2b1ff`
- projection source: `25e29475d51a7061e59f626f6478e05577d0cc9c`
- projection tests: `9bec65a75836b732c01e67f849a54c48040c9857`
- concrete MapKit operation: `c65b83c081787ecb6681b090ac32bc3a35da9a3a`

## Real Xcode 27 CI mirror

The repository's default Xcode workflow triggers only `main` and `feature/**` and normally tests only NembraCore. To obtain real Apple-SDK evidence without modifying main or the authoritative PR #77 source diff, this worker created CI-only mirror branch:

`feature/mapkit-navigation-adapter-chat-j9r2w`

The mirror started from authoritative adapter head `6ef144c2e3d1242a620c56921e830a0513046f0b` and adds only a CI workflow edit that runs:

`swift test` in `Packages/NembraMapKitNavigation`

Real GitHub Actions run **31132110302** was emitted for exact CI-mirror head `9d741d65e83eaa1e017ff9b949777b472dcf7f07` on the `xcode-27` runner. At the latest recorded checkpoint the job was queued; no pass/fail claim is made until its steps/logs are inspected.

The mirror is diagnostic/acceptance infrastructure only. Its workflow edit is not part of PR #77's effective source diff.

## Xcode-only deterministic tests prepared

With MapKit/CoreLocation available, projection tests cover:
- cycling endpoint/request preference projection;
- current `MKMapItem.location` endpoint round-trip;
- unknown request transport rejection;
- documented MapKit error mapping;
- future/combined returned transport remaining unknown;
- `MKPolyline` coordinate order preservation;
- provider route and step fact projection through a server-independent fake route reader;
- route and step provider totals remaining independent;
- exact instruction/notice/advisory preservation.

Async cancellation/race semantics do not require MapKit and are already covered by the 16 Linux tests above. Xcode CI therefore does not need live Apple route-server access to prove those semantics.

## Required next gate

Before this adapter is accepted or wired into the app:
1. inspect run 31132110302 and fix any real SDK API, availability, concurrency, package, or test failure;
2. preserve server-independent CI;
3. after parent #41 is accepted, reconcile/retarget this dependent lane onto fresh main;
4. run an exact final-head package gate again after that reconciliation;
5. only then consider production app/UI wiring.

## Hardware status

**PUBLIC API RESEARCH + SOFTWARE IMPLEMENTATION ONLY.** The async operation/planning layers are deterministically tested in software. Real Apple-SDK evidence is being obtained through the CI mirror. No physical ES80, outdoor GPS, route-quality, legality, or physical iPhone behavior is verified by this package.
