# MapKit navigation research for Nembra

Date: 2026-08-06
Worker: `chat-j9r2w`
Lane: `mapkit-navigation-research`

## Purpose

Define what Nembra can truthfully build with current Apple MapKit APIs before the production navigation cockpit is wired into the app. This document separates verified public API facts, product inference, software-only domain behavior, and physical/outdoor evidence that does not exist yet.

Nothing in this lane proves that an Apple cycling route is legal, permitted, accessible, safe, or appropriate for an AOVOPRO ES80.

## Verified public MapKit surface

Current MapKit directions transport types include:
- `any`
- `automobile`
- `walking`
- `cycling`
- `transit`

Apple documents `MKDirectionsTransportType.cycling` as requesting directions suitable for cycling. The documented directions transport surface does not expose a scooter/e-scooter mode.

`MKDirections.Request` supports source/destination map items, transport type, alternate-route requests, highway preference, toll preference, and applicable departure/arrival dates.

`MKDirections` is server-backed. Apple documents asynchronous throwing `calculate()`, `isCalculating`, and `cancel()`. Apple also documents request failure states including `loadingThrottled`, `directionsNotFound`, `serverFailure`, and `unknown`.

A returned `MKRoute` provides route geometry, steps, distance, expected travel time, transport type, highway/toll flags, and advisory notices. `MKRoute.Step` provides step geometry, localized `instructions`, optional `notice`, distance, and transport type.

Apple can also launch Maps in cycling-directions mode through `MKLaunchOptionsDirectionsModeCycling`.

Apple's separate default-navigation-app program/entitlement is not required merely to render and follow an in-app MapKit route.

## Product inference — not an Apple guarantee

Because current MapKit provides cycling but no scooter transport mode, `.cycling` is the closest current first-party route category for Nembra's scooter experience.

Nembra may truthfully describe this as an Apple cycling route or cycling-based route suggestion. Nembra must not silently relabel it as:
- scooter legal;
- ES80 approved;
- bike-lane guaranteed;
- safe for scooters;
- legal on every segment.

Any future jurisdiction rules, path restrictions, grade/surface data, hazard reports, or other scooter-specific evidence must remain separately sourced and must not rewrite MapKit's meaning.

## Permanent navigation truth boundaries

- Provider route geometry/distance/ETA is routing information, not ride telemetry.
- Navigation/map snapping never becomes recorded GPS distance.
- Navigation progress never becomes measured speed.
- Route ETA never becomes battery/range evidence.
- Provider localized instruction/notice strings remain provider strings; NembraCore does not parse them to invent maneuver semantics.
- Unknown/future provider transport semantics remain `unknown` instead of being guessed into a known mode.
- Raw Core Location callbacks do not enter route-progress or reroute policy directly. Location evidence must first pass the existing ride-location quality boundary.
- Simulator/software-generated route or location evidence is QA evidence only.
- No production reroute corridor/cooldown threshold is selected until real iPhone/outdoor traces justify it.

## Implemented isolated NembraCore foundation

### 1. Immutable route projection — `NavigationRouteDomain.swift`

Implemented:
- validated platform-neutral coordinates;
- explicit provider/requested/returned transport provenance;
- `appleMapKitCycling` provenance without scooter-legality claims;
- immutable route and step snapshots;
- route/step geometry preservation;
- exact provider instruction/notice preservation;
- provider route/step distance preservation;
- expected travel time, advisory notices, highway/toll facts;
- explicit `unknown` transport fallback;
- fail-closed invalid coordinates/distances/time and empty route/step geometry;
- no Codable/persistence promise yet.

### 2. Route request planning/race safety — `NavigationRoutePlanning.swift`

Implemented:
- provider-neutral source/destination request intent;
- cycling/alternate/highway/toll preferences;
- stable product-facing failure states;
- monotonic request-generation tokens;
- explicit supersession token for provider cancellation;
- stale success/failure callback rejection;
- cancellation invalidation before transport cancellation races;
- empty provider-route response rejection;
- atomic token-exhaustion failure.

The coordinator performs no network request and imports no MapKit.

### 3. Reroute evidence policy — `NavigationReroutePolicy.swift`

Implemented:
- injected route-deviation threshold;
- injected required consecutive accepted samples;
- domain invariant requiring at least two accepted samples, so one noisy point cannot reroute;
- injected reroute cooldown;
- no production default threshold/cooldown;
- ambiguous progress assignment clears deviation evidence instead of guessing;
- on-route evidence clears accumulated deviation;
- known continuity gaps clear accumulated deviation;
- process-local monotonic ordering retained across gaps to reject older callbacks;
- non-monotonic rejection is atomic;
- cooldown suppresses request storms;
- newly selected route clears route-specific deviation/cooldown state.

The evaluator computes no route geometry, accepts no raw GPS callback, changes no ride distance, and makes no legality/safety claim.

### 4. Guidance progress state — `NavigationGuidanceProgress.swift`

Implemented:
- route-selection generation tokens so callbacks from a prior route cannot publish onto a new selection;
- explicit `awaitingEvidence`, `ambiguousProgress`, and `continuityGap` unavailable states;
- process-local monotonic observation ordering;
- current step index plus exact provider current/next step snapshots;
- remaining step/route distance fields bounded by provider step/route facts;
- final-step behavior with no invented next maneuver;
- ambiguous geometry assignment removes active progress instead of selecting a likely path;
- continuity gaps immediately remove current step/distance claims while retaining the selected route for rendering;
- stale callbacks after a known gap remain rejectable;
- selection-sequence exhaustion fails atomically.

This tracker does not compute/snaps coordinates, does not perform rerouting, and never writes navigation progress into ride-distance history.

## Future Apple-platform MapKit adapter

The next Apple-platform boundary should:
- build a fresh `MKDirections.Request` from `NavigationRoutePlanRequest`;
- map `.cycling` to `MKDirectionsTransportType.cycling`;
- map alternate/highway/toll preferences without changing meaning;
- own the active `MKDirections` instance per Nembra request generation;
- call `cancel()` when a generation is superseded/cancelled;
- still rely on the Nembra token to reject a racing completion;
- map documented MapKit errors into stable Nembra failure states;
- project successful `MKRoute`/`MKRoute.Step` values into immutable Nembra snapshots;
- fail closed if no usable route is returned.

Do not infer a specific MapKit error code for Nembra-initiated cancellation unless Apple documents one. Nembra already knows when it invalidated its own generation.

## Future geometry/progress matcher

A future geometry layer must consume only accepted location evidence and produce guidance observations such as:
- selected route generation;
- matched step index;
- remaining distance on current step;
- remaining route distance;
- route-deviation distance;
- whether progress assignment is sufficiently unambiguous.

It must not let map snapping modify the original location evidence or ride GPS-distance pipeline.

Nearby/parallel paths are a first-class ambiguity case. When assignment cannot be made confidently, the correct result is unavailable/ambiguous guidance rather than a guessed maneuver.

## Request lifecycle and concurrency

Request identity belongs to Nembra, not callback timing.

1. `begin` creates a monotonic request token.
2. If another request is active, the old token is returned as superseded.
3. The adapter cancels the old `MKDirections` object if it still exists.
4. The new provider calculation begins.
5. Completion publishes only if its Nembra token is still current.
6. User cancellation invalidates the current generation before provider cancellation.
7. A racing old callback is ignored.

Transport cancellation is therefore a resource optimization/user-intent signal, not the sole correctness mechanism.

## Offline/network behavior

`MKDirections` is server-backed. Nembra must design for new-route/reroute unavailability rather than claim offline route generation.

An already obtained immutable route may remain renderable while a new calculation is unavailable, but durable offline navigation must not be claimed until lifecycle/storage behavior is deliberately implemented and tested.

## Route-request cadence

Nembra should:
- request when the user explicitly requests a route or a meaningful reroute policy fires;
- debounce destination/search changes;
- cancel superseded calculations;
- keep render cadence separate from route-request cadence;
- never reroute from normal GPS noise;
- use explicit cooldown/evidence rather than using provider throttling as flow control.

## Accessibility and motion

Future navigation UI should:
- announce meaningful maneuver changes through VoiceOver instead of every animation frame;
- preserve stable text equivalents for maneuver/distance state;
- respect Reduce Motion without changing route truth;
- remain legible under large text without hiding critical speed/battery state.

## Deterministic verification state

Previously verified isolated suites:
- route snapshot + request planning + reroute policy: **39/39 tests passed** under Swift 6.2.1.

Latest additional focused suite:
- guidance progress state: **13/13 tests passed** under Swift 6.2.1.
- the committed source/test blob SHAs exactly match the locally tested files.

Current accumulated focused navigation evidence: **52 passing tests across four isolated suites**.

This is focused software evidence, not a substitute for the repository-wide Xcode 27/iPhone 12 Simulator gate. A prior sandbox attempt to clone the entire branch and run the complete real NembraCore package could not begin because the sandbox could not resolve `github.com`; that was a tooling/network limitation, not a repository-wide green result.

## Covered deterministic behaviors

Implemented/covered now:
1. cycling request configuration for the first MapKit profile;
2. alternate/highway/toll preferences remain explicit;
3. route/step provider facts and provenance are preserved;
4. invalid/empty provider data fails closed;
5. superseded/cancelled request generations cannot publish stale routes;
6. throttled/server/unavailable/unknown failures remain explicit;
7. invalid coordinates/distances/time fail closed;
8. provider step totals are not forced to equal route totals;
9. unknown provider transport semantics stay unknown;
10. one noisy deviation sample cannot reroute;
11. sustained accepted deviation can request one reroute under injected policy;
12. reroute cooldown prevents request storms;
13. ambiguous progress and continuity gaps invalidate accumulated reroute evidence;
14. selected-route generations reject stale progress callbacks;
15. ambiguous route assignment removes current progress instead of guessing;
16. continuity gaps remove displayed current step/distance until fresh evidence;
17. current/next provider instructions/notices survive guidance state unchanged;
18. final step has no invented next maneuver.

Still required before production navigation acceptance:
19. real MapKit request/result/error mapping compiles/runs under Xcode/iOS;
20. deterministic MapKit adapter fixture independent of live Apple servers;
21. accepted-location-to-route geometry matching;
22. presentation-only map snapping is proven isolated from ride GPS distance;
23. real Simulator navigation interaction/screenshot critique;
24. physical iPhone outdoor route/progress/reroute validation;
25. product UI never surfaces cycling provenance as scooter legality.

## Suggested continuation order

1. Apple-platform MapKit adapter + focused Xcode tests/fixtures.
2. Deterministic Simulator route provider fixture.
3. Accepted-location-to-route geometry/progress matcher.
4. Lightweight route preview UI.
5. Landscape Dashboard navigation composition.
6. Simulator interaction + screenshot critique.
7. Physical iPhone outdoor validation before production claims.

Do not wire high-contention app/project files merely to create visible progress before the adapter/domain is accepted.

## Explicit non-goals of the current lane

- no live Apple-server route request is currently made by Nembra;
- no production MapKit adapter is claimed compiled/accepted;
- no legal-routing database;
- no claim that cycling directions are scooter-safe;
- no physical ES80 validation;
- no production location/reroute thresholds selected;
- no ride-distance behavior changed;
- no battery/range behavior changed;
- no app bootstrap/project wiring changed;
- no motorized-hardware writes.

## Apple sources

- `MKDirectionsTransportType.cycling`: https://developer.apple.com/documentation/mapkit/mkdirectionstransporttype/cycling
- `MKDirectionsTransportType`: https://developer.apple.com/documentation/mapkit/mkdirectionstransporttype
- `MKDirections.Request.transportType`: https://developer.apple.com/documentation/mapkit/mkdirections/request/transporttype
- `MKDirections`: https://developer.apple.com/documentation/mapkit/mkdirections
- `MKDirections.calculate()`: https://developer.apple.com/documentation/mapkit/mkdirections/calculate()
- `MKDirections.cancel()`: https://developer.apple.com/documentation/mapkit/mkdirections/cancel()
- `MKDirections.isCalculating`: https://developer.apple.com/documentation/mapkit/mkdirections/iscalculating
- `MKError.Code.loadingThrottled`: https://developer.apple.com/documentation/mapkit/mkerror/code/loadingthrottled
- `MKError.Code.directionsNotFound`: https://developer.apple.com/documentation/mapkit/mkerror/code/directionsnotfound
- `MKError.Code.serverFailure`: https://developer.apple.com/documentation/mapkit/mkerror/code/serverfailure
- `MKRoute`: https://developer.apple.com/documentation/mapkit/mkroute
- `MKRoute.steps`: https://developer.apple.com/documentation/mapkit/mkroute/steps
- `MKRoute.Step`: https://developer.apple.com/documentation/mapkit/mkroute/step
- `MKRoute.Step.instructions`: https://developer.apple.com/documentation/mapkit/mkroute/step/instructions
- `MKDirections.Request.requestsAlternateRoutes`: https://developer.apple.com/documentation/mapkit/mkdirections/request/requestsalternateroutes
- `MKDirections.Request.highwayPreference`: https://developer.apple.com/documentation/mapkit/mkdirections/request/highwaypreference
- `MKDirections.Request.tollPreference`: https://developer.apple.com/documentation/mapkit/mkdirections/request/tollpreference
- `MKLaunchOptionsDirectionsModeCycling`: https://developer.apple.com/documentation/mapkit/mklaunchoptionsdirectionsmodecycling
- Preparing your app to be the default navigation app: https://developer.apple.com/documentation/mapkit/preparing-your-app-to-be-the-default-navigation-app
- WWDC25, “Go further with MapKit”: https://developer.apple.com/videos/play/wwdc2025/204/
