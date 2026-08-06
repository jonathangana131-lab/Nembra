# MapKit navigation research for Nembra

Date: 2026-08-06
Worker: `chat-j9r2w`
Lane: `mapkit-navigation-research`

## Purpose

Define what Nembra can truthfully build with current Apple MapKit APIs before the production navigation cockpit is implemented. This is a public-API research artifact, not a claim that any route is legally or physically safe for an AOVOPRO ES80.

## Evidence classification

### VERIFIED PUBLIC — Apple documentation

Current MapKit exposes these native directions transport types:
- `any`
- `automobile`
- `walking`
- `cycling`
- `transit`

Apple explicitly documents `MKDirectionsTransportType.cycling` as requesting directions suitable for cycling. There is no scooter/e-scooter transport type in the documented `MKDirectionsTransportType` surface.

`MKDirections.Request` supports:
- source and destination map items;
- transport type;
- optional alternate-route requests;
- highway preference;
- toll preference;
- departure/arrival dates where applicable.

`MKDirections` requests route information from Apple servers. Apple documents an async throwing `calculate()` API, an `isCalculating` state, and `cancel()` for a pending request. A directions object handles one calculation at a time; multiple independent directions objects can be used when parallel calculations are genuinely required.

Apple warns that clients can receive `MKError.Code.loadingThrottled` when making too many requests in a short period. The documented directions error surface also includes `directionsNotFound`, `serverFailure`, and `unknown`. Nembra must therefore treat route requests as explicit asynchronous work, not continuously recompute them at display-frame or raw-GPS cadence.

A returned `MKRoute` provides:
- detailed route geometry via `polyline`;
- `steps`;
- route distance;
- expected travel time;
- overall transport type;
- highway/toll flags;
- advisory notices.

Each `MKRoute.Step` provides:
- detailed step geometry via its own polyline;
- localized written `instructions` suitable for presentation;
- an optional `notice`;
- step distance;
- step transport type.

Apple also exposes launch options that can hand a destination to the Maps app in cycling mode through `MKLaunchOptionsDirectionsModeCycling`.

Apple documents a separate default-navigation-app program in specific regions. As of the current documentation, users can choose a third-party default navigation app in the EU on iOS/iPadOS 18.4+ and in Japan on iOS 26.2+. That program requires the navigation-app entitlement and the `geo-navigation://` URL scheme. This is not required merely to render or follow an in-app MapKit route.

### PRODUCT INFERENCE — not an Apple guarantee

Because current MapKit publishes cycling but no scooter-specific transport mode, `.cycling` is the closest first-party route category for a small electric scooter. It must remain classified as a cycling-route suggestion, not as proof that a road/path is legal, permitted, accessible, or safe for the ES80.

MapKit returns route geometry and step instructions, but the public `MKDirections`/`MKRoute` API does not itself establish Nembra's live ride-progress truth. Nembra must own the state machine that correlates accepted location evidence with the selected route, determines which maneuver is current, detects meaningful off-route behavior, and decides when to request a new route.

The CarPlay `CPNavigationSession` API demonstrates the same responsibility split for navigation apps: the app supplies maneuvers and regularly updates estimates/state. That is additional public evidence that route-guidance state is an app responsibility rather than a magical MapKit telemetry source. Nembra does not need CarPlay for the scooter product and should not add it merely to obtain navigation state.

## Product truth boundary

Nembra must never label an Apple cycling route as:
- "scooter legal";
- "ES80 approved";
- "bike-lane guaranteed";
- "safe for scooters";
- "legal on every segment".

A route can truthfully be described as an Apple cycling route or cycling-based route suggestion.

Legal/accessibility/surface restrictions are a separate evidence problem. If Nembra later adds jurisdiction rules, path restrictions, grade/surface evidence, or user-reported hazards, those sources must remain explicit and cannot silently rewrite MapKit's semantics.

## Recommended first production architecture

### 1. Route planning boundary

Create a route-planning service around `MKDirections` rather than calling it directly from SwiftUI views.

Suggested responsibilities:
- accept immutable origin/destination intent;
- request `.cycling` routes by default for the ES80 experience;
- optionally request alternates;
- preserve MapKit route identity/geometry/steps without relabeling them as scooter-safe;
- expose loading, result, cancellation, throttling/network failure, and no-route states explicitly;
- cancel superseded requests;
- reject late callbacks/results from superseded or cancelled request generations;
- serialize/reduce repeated reroute requests so GPS jitter cannot trigger request storms.

The route planner should not own ride distance, battery evidence, or route-recording truth.

The first platform-neutral part of this boundary is now implemented in `NavigationRoutePlanning.swift`: request intent, product-facing failure states, monotonic request tokens, explicit supersession, cancellation invalidation, stale-result rejection, empty-response rejection, and atomic token exhaustion. It deliberately performs no network work and imports no MapKit.

### 2. Selected-route snapshot

Project `MKRoute` into a Nembra-owned immutable snapshot suitable for UI/domain use. Preserve at least:
- route geometry;
- step geometry;
- localized instruction string;
- optional step notice;
- step distance;
- total route distance;
- expected travel time;
- advisory notices;
- highway/toll indicators;
- declared MapKit transport type;
- provenance stating that the route came from Apple MapKit cycling directions.

Do not synthesize a maneuver icon/type from instruction text unless a deterministic parser is separately specified and tested. Text scraping is weaker evidence than the original localized instruction.

This platform-neutral projection is now implemented in `NavigationRouteDomain.swift`. It validates coordinates and numeric route facts, preserves provider strings/metadata, supports an explicit `.unknown` transport fallback, and does not adopt Codable/persistence yet.

### 3. MapKit adapter boundary

A future Apple-platform adapter should:
- build a fresh `MKDirections.Request` from `NavigationRoutePlanRequest`;
- map Nembra's `.cycling` intent to `MKDirectionsTransportType.cycling`;
- map alternate/highway/toll preferences without changing their meaning;
- own the active `MKDirections` instance for each request generation;
- call `cancel()` for a superseded/cancelled generation while still relying on Nembra's generation token to reject a racing late completion;
- map `directionsNotFound` to a stable unavailable-directions state;
- map `loadingThrottled` to an explicit throttled state;
- map `serverFailure` to a server-failure state;
- fail unknown platform errors to a generic unknown state instead of inventing semantics;
- project successful `MKRoute` values into immutable `NavigationRouteSnapshot` values;
- fail closed if the provider returns no usable routes.

Do not infer a specific MapKit error code for Nembra-initiated cancellation unless Apple documents one. Nembra already knows when it initiated cancellation and can classify its own request generation as cancelled before transport cancellation races.

### 4. Guidance progress model

Live navigation should consume the already-screened Core Location evidence path, not raw view-local callbacks.

The guidance model should keep separate concepts for:
- selected route;
- latest accepted location evidence;
- nearest/progress position on the route geometry;
- current and next step;
- remaining distance estimate;
- route-deviation evidence;
- reroute eligibility/cooldown;
- navigation continuity interruptions;
- guidance confidence/availability.

Location smoothing or route snapping used for presentation must never become ride/GPS telemetry evidence. The existing ride-location evidence remains authoritative for ride truth.

### 5. Rerouting policy

Do not reroute from one noisy coordinate.

A production reroute policy should require evidence such as:
- multiple accepted location samples showing sustained separation from the route;
- a meaningful distance threshold from the active route corridor;
- forward-progress logic that avoids bouncing between nearby parallel segments;
- a cooldown after a route request;
- immediate reset/re-evaluation after a known location continuity gap.

Exact thresholds should remain injected/testable until real iPhone/ride traces justify them.

### 6. Dashboard integration

When navigation is active, the landscape Dashboard can truthfully show:
- current speed from the existing authoritative speed/display pipeline;
- current maneuver instruction from the selected MapKit route step;
- distance to the maneuver derived from route/location guidance state;
- route overview or local map crop;
- battery percentage or adaptive estimated range from the battery domain;
- ride duration/trip context from the ride domain.

The navigation UI must not make display animation or map snapping a source for ride distance, speed, battery, or completed-history evidence.

## Request lifecycle and concurrency

Nembra's provider adapter and platform-neutral coordinator must agree on one rule: request identity is owned by Nembra, not inferred from callback timing.

Recommended lifecycle:
1. `begin` creates a new monotonic request token.
2. If another request was active, the coordinator returns its token as superseded.
3. The adapter cancels the superseded `MKDirections` instance if it still exists.
4. The new `MKDirections` calculation begins.
5. A completion may publish only if its Nembra token is still current.
6. User cancellation invalidates the token before calling provider cancellation.
7. A racing provider callback after supersession/cancellation is ignored.

This makes transport cancellation a resource optimization and user-intent signal, not the sole correctness mechanism.

## Offline and network behavior

`MKDirections` is server-backed, so Nembra should design for route-request failure or unavailable network rather than promise offline route generation.

If a route was already obtained, Nembra may continue displaying the immutable route geometry/steps it already holds while being explicit that a new reroute may be unavailable. Do not claim durable offline navigation until Apple/API behavior and app lifecycle storage are deliberately tested.

## Search/request cadence

Apple documents that excessive `MKDirections` request frequency can be throttled. Nembra should therefore:
- request only when the user asks for a destination/route or when a meaningful reroute condition is met;
- debounce destination/search changes;
- cancel superseded calculations;
- keep render cadence completely separate from route-request cadence;
- avoid rerouting from normal GPS noise;
- use explicit cooldown/deviation policy rather than treating `loadingThrottled` as normal flow control.

## Accessibility and motion

Navigation presentation should support:
- VoiceOver announcing the current meaningful maneuver, not every map-camera animation frame;
- stable text equivalents for maneuver/distance state;
- Reduce Motion behavior that removes decorative cockpit/map transitions without changing route truth;
- large text behavior that keeps the primary maneuver readable without hiding critical speed/battery state.

## Minimum deterministic test matrix before app wiring

Implemented in the current isolated NembraCore slice:
1. cycling request configuration is selected for the ES80 route-planning profile;
2. alternate/highway/toll request preferences remain explicit;
3. route snapshots preserve route/step distance, instructions, notices, and provenance;
4. a missing/empty route response fails closed;
5. cancelled/superseded requests cannot publish stale routes;
6. provider throttling and other product-facing failures remain explicit;
7. invalid coordinates/distances/expected times fail closed;
8. provider step totals are not forced to equal provider route totals;
9. future/combined transport semantics can remain unknown instead of being guessed.

Still required before production app wiring/acceptance:
10. one noisy off-route point cannot reroute;
11. sustained accepted deviation can request one reroute after injected policy thresholds;
12. reroute cooldown prevents request storms;
13. a location continuity gap invalidates progress confidence until new accepted evidence arrives;
14. presentation-only map snapping never alters ride GPS distance evidence;
15. a real MapKit adapter maps current Apple request/result/error semantics correctly on Xcode/iOS;
16. route steps remain localized strings from MapKit rather than reclassified telemetry;
17. advisory/step notices survive the real MapKit projection layer;
18. `.cycling` provenance is never surfaced as "scooter legal".

## Suggested implementation order

Completed software foundation in this lane:
1. provider-neutral request/result/failure state and request-generation race safety;
2. immutable Nembra route/step projection and deterministic tests.

Next safe implementation sequence:
3. Apple-platform MapKit adapter with focused Xcode tests/fixtures;
4. Simulator route-request fixture so deterministic app tests do not depend on live Apple servers;
5. guidance-progress geometry/state engine fed by accepted location evidence;
6. injected reroute policy and deterministic off-route scenarios;
7. lightweight route preview UI;
8. landscape Dashboard navigation composition;
9. real Simulator interaction and screenshot critique;
10. physical iPhone outdoor validation before production claims.

## Current verification

The exact platform-neutral source/test content for the two NembraCore foundations passed 26/26 focused tests with Swift 6.2.1 in a supplemental package matching NembraCore's Swift package shape.

A stronger attempt to clone this exact GitHub branch and execute the complete real NembraCore package from the sandbox could not start because the sandbox could not resolve `github.com`. That is a tooling/network limitation, not a repository-wide green result. Full exact-head Xcode 27/NembraCore acceptance remains required before merge.

## Explicit non-goals for this lane

- no live Apple-server route request is made by Nembra yet;
- no production MapKit adapter is claimed compiled or accepted yet;
- no legal-routing database;
- no claim that cycling directions are scooter-safe;
- no physical ES80 validation;
- no location quality or reroute thresholds selected;
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
