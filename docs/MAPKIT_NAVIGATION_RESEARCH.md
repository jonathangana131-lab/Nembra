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

`MKDirections` requests route information from Apple servers. Apple warns that clients can receive a throttling error when making too many requests in a short period, so Nembra must not continuously recompute routes at display-frame or raw-GPS cadence.

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
- serialize/reduce repeated reroute requests so GPS jitter cannot trigger request storms.

The route planner should not own ride distance, battery evidence, or route-recording truth.

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

### 3. Guidance progress model

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

### 4. Rerouting policy

Do not reroute from one noisy coordinate.

A production reroute policy should require evidence such as:
- multiple accepted location samples showing sustained separation from the route;
- a meaningful distance threshold from the active route corridor;
- forward-progress logic that avoids bouncing between nearby parallel segments;
- a cooldown after a route request;
- immediate reset/re-evaluation after a known location continuity gap.

Exact thresholds should remain injected/testable until real iPhone/ride traces justify them.

### 5. Dashboard integration

When navigation is active, the landscape Dashboard can truthfully show:
- current speed from the existing authoritative speed/display pipeline;
- current maneuver instruction from the selected MapKit route step;
- distance to the maneuver derived from route/location guidance state;
- route overview or local map crop;
- battery percentage or adaptive estimated range from the battery domain;
- ride duration/trip context from the ride domain.

The navigation UI must not make display animation or map snapping a source for ride distance, speed, battery, or completed-history evidence.

## Offline and network behavior

`MKDirections` is server-backed, so Nembra should design for route-request failure or unavailable network rather than promise offline route generation.

If a route was already obtained, Nembra may continue displaying the immutable route geometry/steps it already holds while being explicit that a new reroute may be unavailable. Do not claim durable offline navigation until Apple/API behavior and app lifecycle storage are deliberately tested.

## Search/request cadence

Apple documents that excessive `MKDirections` request frequency can be throttled. Nembra should therefore:
- request only when the user asks for a destination/route or when a meaningful reroute condition is met;
- debounce destination/search changes;
- cancel superseded calculations;
- keep render cadence completely separate from route-request cadence;
- avoid rerouting from normal GPS noise.

## Accessibility and motion

Navigation presentation should support:
- VoiceOver announcing the current meaningful maneuver, not every map-camera animation frame;
- stable text equivalents for maneuver/distance state;
- Reduce Motion behavior that removes decorative cockpit/map transitions without changing route truth;
- large text behavior that keeps the primary maneuver readable without hiding critical speed/battery state.

## Minimum deterministic test matrix before app wiring

1. cycling request configuration is selected for the ES80 route-planning profile;
2. alternate-route preference maps correctly without inventing availability;
3. route snapshots preserve route/step distance, instructions, notices, and provenance;
4. a missing/empty route response fails closed;
5. cancelled/superseded requests cannot publish stale routes;
6. route-request throttling/network errors become explicit unavailable/retryable states;
7. one noisy off-route point cannot reroute;
8. sustained accepted deviation can request one reroute after policy thresholds;
9. reroute cooldown prevents request storms;
10. a location continuity gap invalidates progress confidence until new accepted evidence arrives;
11. presentation-only map snapping never alters ride GPS distance evidence;
12. route steps remain localized strings from MapKit rather than reclassified telemetry;
13. advisory/step notices survive the projection layer;
14. `.cycling` provenance is never surfaced as "scooter legal".

## Suggested implementation order

1. isolated MapKit route-planner protocol + request/result types;
2. immutable Nembra route/step projection and deterministic tests;
3. Simulator route-request fixture so tests do not depend on live Apple servers;
4. guidance-progress geometry/state engine fed by accepted location evidence;
5. reroute policy and deterministic off-route scenarios;
6. lightweight route preview UI;
7. landscape Dashboard navigation composition;
8. real Simulator interaction and screenshot critique;
9. physical iPhone outdoor validation before production claims.

## Explicit non-goals for this research lane

- no production route planner implemented here;
- no legal-routing database;
- no claim that cycling directions are scooter-safe;
- no physical ES80 validation;
- no location quality thresholds selected;
- no ride-distance behavior changed;
- no battery/range behavior changed;
- no app bootstrap/project wiring changed;
- no motorized-hardware writes.

## Apple sources

- `MKDirectionsTransportType.cycling`: https://developer.apple.com/documentation/mapkit/mkdirectionstransporttype/cycling
- `MKDirectionsTransportType`: https://developer.apple.com/documentation/mapkit/mkdirectionstransporttype
- `MKDirections.Request.transportType`: https://developer.apple.com/documentation/mapkit/mkdirections/request/transporttype
- `MKDirections`: https://developer.apple.com/documentation/mapkit/mkdirections
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
