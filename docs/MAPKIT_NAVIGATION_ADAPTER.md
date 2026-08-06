# Apple MapKit navigation adapter

Date: 2026-08-06
Worker: `chat-j9r2w`
Lane: `mapkit-navigation-adapter`
Parent: PR #41 exact head `90e28f72587bdc7f18827f89a2dcb4faead4666d`

## Scope

This dependent lane introduces an isolated `NembraMapKitNavigation` Swift package above NembraCore. It does not wire MapKit into the production app, Xcode project, Dashboard, Home, ride persistence, or hardware service.

Current slice:
- projects `NavigationRoutePlanRequest` into current `MKDirections.Request` values;
- creates endpoints with current `MKMapItem(location:address:)` instead of the deprecated placemark initializer/property surface;
- maps current documented MapKit error codes into Nembra's stable route-plan failures;
- extracts `MKPolyline` coordinates in order;
- projects `MKRoute` and `MKRoute.Step` facts into immutable Nembra route/step snapshots;
- preserves requested versus returned transport provenance;
- leaves unknown/combined future returned transport as `.unknown` rather than guessing.

No live Apple-server request is executed by this slice yet.

## Current Apple API facts checked

Current Apple Developer documentation was rechecked on 2026-08-06 before implementation:
- `MKDirections.Request` exposes source, destination, transport type, alternate-route request, highway preference, and toll preference;
- `MKDirections.RoutePreference` currently exposes `.any` and `.avoid`;
- `MKDirectionsTransportType` includes cycling;
- `MKMapItem(location:address:)` and `MKMapItem.location` are current, while `MKMapItem(placemark:)` / `placemark` are deprecated;
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
- MapKit decoding failure maps to invalid provider response; undocumented/future error codes map to unknown.
- This package is Apple-platform infrastructure, not physical AOVOPRO ES80 evidence.

## Verification completed without Apple SDK

The execution environment in this chat does not expose the real MapKit SDK/Xcode toolchain. The current checkpoint therefore uses explicitly limited pre-Xcode evidence:

1. repository-layout SwiftPM manifest successfully parses/resolves its local NembraCore dependency shape;
2. exact adapter source and exact Xcode-only test source pass `swiftc -parse` under Swift 6.2.1;
3. exact adapter source type-checks against synthetic `MapKit`, `CoreLocation`, and `NembraCore` modules whose signatures were shaped from the current Apple documentation listed above;
4. synthetic type-check is contract/syntax evidence only and is **not** claimed as Apple SDK compilation.

Local tested blob identities before GitHub checkpoint:
- adapter source: `25e29475d51a7061e59f626f6478e05577d0cc9c`
- Xcode-only tests: `9bec65a75836b732c01e67f849a54c48040c9857`
- repository-layout manifest: `a6823e0cde290448b4b0b736aa93c758a2d2b1ff`

## Xcode-only deterministic tests prepared

When this package is compiled with MapKit/CoreLocation available, focused tests cover:
- cycling endpoint/request preference projection;
- current `MKMapItem.location` endpoint round-trip;
- unknown request transport rejection;
- documented MapKit error mapping;
- future/combined returned transport remaining unknown;
- `MKPolyline` coordinate order preservation;
- provider route and step fact projection through a server-independent fake route reader;
- route and step provider totals remaining independent;
- exact instruction/notice/advisory preservation.

These tests deliberately do not call Apple routing servers.

## Required next gate

Before this adapter is accepted or wired into the app:
1. compile `NembraMapKitNavigation` with the real Xcode 27/iOS 27 SDK;
2. run its focused MapKit tests on the Xcode runner;
3. fix real SDK/API/concurrency failures rather than treating the synthetic type-check as proof;
4. then implement the async `MKDirections.calculate()` operation/cancellation layer behind Nembra's already-accepted request-generation semantics;
5. keep that operation testable with a deterministic provider fixture rather than making CI depend on live Apple servers.

## Hardware status

**PUBLIC API RESEARCH + PRE-XCODE SOFTWARE IMPLEMENTATION ONLY.** No physical ES80, outdoor GPS, route-quality, legality, or physical iPhone behavior is verified by this package.
