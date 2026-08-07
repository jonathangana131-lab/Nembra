# MapKit navigation research for Nembra

Date: 2026-08-06  
Worker: `chat-j9r2w`  
Lane: `mapkit-navigation-research`

## Purpose

This document defines the truth and acceptance boundary for Nembra's platform-neutral navigation core before Apple MapKit transport and product UI are wired into the app.

It separates:
- public Apple routing facts;
- Nembra product inference;
- deterministic software behavior;
- Simulator evidence;
- physical/outdoor evidence that does not exist yet.

Nothing in this lane proves that an Apple cycling route is legal, permitted, accessible, safe, or appropriate for an AOVOPRO ES80.

## Public MapKit facts used by this architecture

Current MapKit directions transport types include `any`, `automobile`, `walking`, `cycling`, and `transit`. Apple documents `MKDirectionsTransportType.cycling` as requesting directions suitable for cycling. The public directions transport surface does not expose a scooter/e-scooter mode.

`MKDirections.Request` supports source/destination map items, transport type, alternate-route requests, highway preference, toll preference, and applicable departure/arrival dates.

`MKDirections` is server-backed and exposes asynchronous calculation plus cancellation. Returned `MKRoute` / `MKRoute.Step` values carry geometry, distance, travel-time/transport facts, instructions/notices, and other provider route metadata.

Apple can also launch Maps in cycling-directions mode through `MKLaunchOptionsDirectionsModeCycling`. Nembra does not need to pretend to be a default navigation app merely to render and follow an in-app route.

## Product inference — not an Apple guarantee

Because MapKit currently exposes cycling but no scooter transport mode, cycling is the closest current first-party routing category for the initial Nembra navigation profile.

Nembra may truthfully describe the result as an Apple cycling route or cycling-based route suggestion. It must not silently relabel it as:
- scooter legal;
- ES80 approved;
- bike-lane guaranteed;
- safe for scooters;
- legal on every segment.

Any future jurisdiction rules, path restrictions, grade/surface data, hazard reports, or scooter-specific evidence must remain separately sourced and must not rewrite MapKit's meaning.

## Permanent navigation truth boundaries

- Provider route geometry, distance, and ETA are routing information, not ride telemetry.
- Navigation/map snapping never becomes recorded GPS distance.
- Navigation progress never becomes measured speed.
- Route ETA never becomes battery/range evidence.
- Provider localized instruction/notice strings remain provider strings; NembraCore does not parse them to invent maneuver semantics.
- Unknown/future provider transport semantics remain `unknown` instead of being guessed into a known mode.
- Raw Core Location callbacks do not enter guidance or reroute logic directly. Location evidence first passes the existing ride-location quality boundary.
- Simulator/software-generated route/location evidence is QA evidence only.
- No production route corridor, ambiguity threshold, reroute duration, or reroute cooldown is selected until real iPhone/outdoor traces justify it.
- Route-progress confidence and distance-from-route deviation confidence are separate facts.
- A route can remain renderable while current progress becomes unavailable after ambiguity or a continuity gap.
- Navigation state never repairs or rewrites the independent ride-evidence domains.

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
- fail-closed invalid coordinates/distances/time and empty route/step geometry.

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
- active-request provenance validation: every accepted route must report the same requested transport mode as the active request generation;
- returned transport mode remains independent provider truth and may legitimately differ from requested transport;
- atomic token-exhaustion failure.

The coordinator performs no network request and imports no MapKit.

### 3. Reroute evidence policy — `NavigationReroutePolicy.swift`

Implemented:
- injected route-deviation threshold;
- injected required consecutive accepted samples;
- injected minimum consecutive deviation duration;
- at least two accepted samples are required so one noisy point cannot reroute;
- positive elapsed deviation duration is required so callback density cannot masquerade as sustained deviation;
- injected reroute cooldown;
- no production default threshold/duration/cooldown;
- deviation-assessment confidence is separate from route-progress confidence;
- unconfident deviation assessment clears accumulated deviation instead of guessing;
- on-route evidence clears accumulated deviation and duration start;
- known continuity gaps clear accumulated deviation and duration start;
- process-local monotonic ordering is retained across gaps to reject older callbacks;
- non-monotonic rejection is atomic;
- cooldown suppresses request storms;
- newly selected route clears route-specific deviation/duration/cooldown state.

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
- continuity gaps remove current step/distance claims while retaining the selected route for rendering;
- stale callbacks after a known gap remain rejectable;
- selection-sequence exhaustion fails atomically.

This tracker does not compute/snap coordinates, reroute, or write navigation progress into ride-distance history.

### 5. Screened-location geometry matching — `NavigationRouteGeometryMatcher.swift`

Implemented:
- accepts only `QualityScreenedRideLocation`, never raw Core Location callbacks;
- injected maximum spatial-support corridor for confident progress;
- injected minimum separation needed to distinguish competing steps;
- injected minimum along-polyline separation needed to reject two near-equal projection positions on the same geometry;
- no production matching-policy default;
- deterministic projection onto route and step polylines;
- dateline-aware longitude wrapping;
- provider-scaled remaining step and route distance estimates;
- route total remains independent from summed provider step totals;
- nearby/parallel-step ambiguity fails progress confidence closed;
- self-intersections/loops with multiple near-equal projections far apart along one polyline fail progress confidence closed;
- far-from-route evidence remains observable while current progress becomes untrusted;
- far-from-route progress failure does not erase separately valid route-deviation distance evidence;
- non-zero provider distance with degenerate one-point geometry fails trustworthy progress;
- zero-distance one-point provider routes remain representable;
- accepted location continuity-segment flags survive projection;
- one immutable match can project into guidance and reroute observations without changing source evidence.

#### Intentional route + selected-step corridor rule

The current policy exposes one injected `maximumRouteDistanceMeters` progress corridor. For a progress assignment to be confident, **both**:
1. the route projection, and
2. the chosen step projection

must be within that same injected corridor.

This equivalence is intentional and conservative: the current domain does not have outdoor evidence justifying separate route-vs-step assignment radii. Reusing one injected corridor fails closed when provider route geometry is near the rider but all step geometry is spatially unsupported. It does **not** force provider route geometry to equal step geometry, rewrite provider facts, or change route-level deviation evidence. A future separate step-assignment corridor would require evidence and its own explicit policy field rather than a hidden constant.

These geometric distances are navigation estimates. They never become the ride GPS-distance accumulator.

### 6. Composed navigation session — `NavigationSessionCoordinator.swift`

Implemented:
- one platform-neutral entry point from `QualityScreenedRideLocation` into geometry matching, guidance progress, and reroute evaluation;
- selected-route ownership through guidance selection generation;
- one process-local monotonic location gate before either guidance or reroute state mutates;
- stale callbacks cannot partially update one navigation reducer while leaving another behind;
- route selection/clear does not falsely reset the process callback clock;
- known accepted-location segment gaps reset guidance/reroute continuity evidence before the same accepted point is processed;
- one off-route point cannot reroute;
- sustained deviation must satisfy injected sample-count and elapsed-duration evidence;
- sustained deviation beyond the progress-confidence corridor can still request reroute when route-deviation distance evidence remains trustworthy;
- competing-step, within-step/self-intersection, and spatially unsupported selected-step assignments cannot become active guidance;
- clear-route returns guidance to idle without rewriting prior ride evidence.

The session coordinator performs no MapKit request, no Core Location quality screening, no SwiftUI work, no ride-distance mutation, and no scooter-legality inference.

## Current software pipeline

`RideLocationSample`
→ existing `RideLocationQualityScreen`
→ `QualityScreenedRideLocation`
→ `NavigationRouteGeometryMatcher`
→ immutable geometry match
→ `NavigationGuidanceProgressTracker` + `NavigationRerouteEvaluator`
→ `NavigationSessionCoordinator` update

The navigation side consumes already-accepted location evidence. It does not feed snapped/progress coordinates back into the ride-location evidence path.

## Future Apple-platform MapKit adapter

The Apple-platform boundary should:
- build a fresh `MKDirections.Request` from `NavigationRoutePlanRequest`;
- map supported request transport modes without changing meaning;
- own the active `MKDirections` instance per Nembra request generation;
- call `cancel()` when a generation is superseded/cancelled;
- still rely on the Nembra token to reject a racing completion;
- map documented MapKit errors into stable Nembra failure states;
- project successful `MKRoute` / `MKRoute.Step` values into immutable Nembra snapshots;
- preserve active-request provenance consistently;
- fail closed if no usable route is returned.

Do not infer a specific MapKit error code for Nembra-initiated cancellation unless Apple documents one. Nembra already knows when it invalidated its own generation.

## Request lifecycle and concurrency

Request identity belongs to Nembra, not callback timing.

1. `begin` creates a monotonic request token.
2. If another request is active, the old token is returned as superseded.
3. The adapter cancels the old provider operation if it still exists.
4. The new provider calculation begins.
5. Completion publishes only if its Nembra token is still current and projected route provenance agrees with the active requested transport.
6. User cancellation invalidates the current generation before provider cancellation.
7. A racing old callback is ignored.

Transport cancellation is a resource optimization/user-intent signal, not the sole correctness mechanism.

## Offline/network behavior

`MKDirections` is server-backed. Nembra must design for new-route/reroute unavailability rather than claim offline route generation.

An already obtained immutable route may remain renderable while a new calculation is unavailable, but durable offline navigation must not be claimed until lifecycle/storage behavior is deliberately implemented and tested.

## Route-request cadence

Nembra should:
- request when the user explicitly requests a route or a meaningful reroute policy fires;
- debounce destination/search changes;
- cancel superseded calculations;
- keep render cadence separate from route-request cadence;
- never reroute from normal GPS noise or merely from a dense callback burst;
- use explicit sample-count, elapsed-duration, cooldown, and evidence-confidence gates rather than provider throttling as flow control.

## Accessibility and motion

Future navigation UI should:
- announce meaningful maneuver changes through VoiceOver instead of every animation frame;
- preserve stable text equivalents for maneuver/distance state;
- respect Reduce Motion without changing route truth;
- remain legible under large text without hiding critical speed/battery state.

## Deterministic verification state

The exact six navigation suites reconstructed from PR #41 passed **75/75** before review hardening under Swift 6.2.1.

After the first four review repairs, the exact source/test bytes passed **82/82** focused tests across six suites.

After the fifth peer-review repair (route-near / selected-step-far spatial inconsistency), the exact current repository-focused source/test set passed **83/83 focused tests across seven suites**:
- the original six navigation suites, plus
- `NavigationRouteGeometryConsistencyTests` with the contradictory route/step geometry regression.

New regression coverage from the five repairs includes:
- sample count cannot substitute for injected elapsed deviation duration;
- exact duration boundary behavior;
- deviation-duration reset on on-route/unconfident/gap/new-route evidence;
- sustained far-off-route reroute while progress remains unavailable;
- single-step self-intersection ambiguity;
- active-request/requested-transport provenance contradiction rejection;
- returned transport differences remain preservable provider truth;
- route-near but selected-step-far provider geometry fails progress assignment closed while route-level deviation assessment remains separately available.

Additional scratch-only adversarial probes were used during hardening but are not merge evidence. Repository acceptance counts above refer only to committed tests.

This is focused software verification, not repository-wide Xcode 27/iPhone 12 Simulator acceptance.

## Covered deterministic behaviors

Implemented/covered now:
1. cycling request configuration for the first MapKit profile;
2. alternate/highway/toll preferences remain explicit;
3. route/step provider facts and provenance are preserved;
4. invalid/empty provider data fails closed;
5. active request and returned route requested-transport provenance cannot contradict each other;
6. returned transport mode may differ and remains provider truth;
7. superseded/cancelled request generations cannot publish stale routes;
8. throttled/server/unavailable/unknown failures remain explicit;
9. invalid coordinates/distances/time fail closed;
10. provider step totals are not forced to equal route totals;
11. unknown provider transport semantics stay unknown;
12. one noisy deviation sample cannot reroute;
13. callback count alone cannot satisfy sustained deviation;
14. sustained accepted deviation can request reroute only after injected count + duration evidence;
15. reroute cooldown prevents request storms;
16. unconfident deviation and continuity gaps invalidate accumulated reroute evidence;
17. selected-route generations reject stale progress callbacks;
18. competing-step ambiguity removes current progress instead of guessing;
19. within-step/self-intersection ambiguity removes current progress instead of guessing;
20. continuity gaps remove displayed current step/distance until fresh evidence;
21. current/next provider instructions/notices survive guidance state unchanged;
22. final step has no invented next maneuver;
23. accepted quality-screened locations project onto route/step geometry;
24. far-route evidence fails progress confidence without disappearing;
25. far-route distance evidence can still qualify for reroute assessment;
26. parallel-step ambiguity fails closed;
27. dateline-adjacent route geometry uses wrapped longitude math;
28. navigation route remaining-distance math remains separate from provider step totals;
29. one immutable match feeds guidance and reroute domains using separate confidence facts;
30. session-level stale callback rejection occurs before partial navigation mutation;
31. route selection/clear preserves process-local callback ordering truth;
32. a selected step outside the injected spatial-support corridor cannot publish confident progress even when the overall route geometry is near the rider.

Still required before production navigation acceptance:
33. current adapter request/result/error mapping compiles/runs under Xcode/iOS and rejects unsupported request-side semantics;
34. deterministic MapKit adapter fixture independent of live Apple servers;
35. exact-final-head Xcode 27/iPhone 12/iOS 27 Simulator gate on the final integrated head;
36. real Simulator navigation interaction and screenshot critique;
37. physical iPhone outdoor route/progress/reroute validation;
38. product UI never surfaces cycling provenance as scooter legality;
39. production matching/reroute thresholds selected only from real trace evidence.

## Suggested continuation order

1. Accept/merge this platform-neutral parent after current-main verification, peer review, and exact-final-head Xcode/Simulator evidence.
2. Reconcile the dependent Apple-platform MapKit adapter onto the accepted parent and close its API-review blockers.
3. Deterministic Simulator route/search provider fixtures.
4. Lightweight route preview UI after adapter acceptance.
5. Landscape Dashboard navigation composition after current performance/UI ownership is reconciled.
6. Simulator interaction + screenshot critique.
7. Physical iPhone outdoor validation before production claims.

Do not edit high-contention app/project files merely to create visible progress before the adapter/domain is accepted.

## Explicit non-goals of the current lane

- no live Apple-server route request is made by NembraCore;
- no production MapKit adapter is claimed accepted by this parent lane;
- no legal-routing database;
- no claim that cycling directions are scooter-safe;
- no physical ES80 validation;
- no production location/matching/reroute thresholds selected;
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
