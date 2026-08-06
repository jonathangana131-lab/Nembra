# Navigation reroute policy

Date: 2026-08-06
Worker: `chat-k8x5d`
Lane: `navigation-reroute-policy`

## Purpose

Provide a small platform-neutral evidence gate that prevents one noisy accepted location from causing a MapKit reroute request.

This slice is intentionally dependent on the navigation route foundation in PR #41, but it owns separate files and does not change that worker's route-domain types. It implements only route-adherence/reroute policy over an already-derived distance-from-route observation.

## Input truth boundary

`NavigationRerouteTracker.ingest(distanceFromRouteMeters:receiptUptime:)` does **not** accept raw Core Location callbacks.

The distance value must already have been derived by a future navigation geometry layer from location evidence that passed the existing location-quality boundary. It is navigation-derived state only.

It must never be used to:
- replace the original accepted phone coordinate;
- add or subtract ride GPS distance;
- reconstruct a missing route segment;
- become measured scooter telemetry;
- modify speed, battery, range, ODO, or completed-history evidence.

Map matching/snap-to-route can help guidance presentation, but it remains one-way derivation from accepted location evidence.

## Policy

`NavigationReroutePolicy` keeps all thresholds injected and validated:
- `offRouteEnterDistanceMeters`: a sample at or beyond this distance may count toward off-route evidence;
- `onRouteExitDistanceMeters`: a sample at or inside this lower threshold clears the current off-route episode;
- `minimumOffRouteSamples`: at least two accepted deviation observations are required;
- `minimumOffRouteDurationSeconds`: sample count alone is insufficient; the deviation must also persist for meaningful monotonic time;
- `rerouteCooldownSeconds`: a second episode cannot immediately create another route request.

The exit threshold must be lower than the enter threshold. The band between them provides hysteresis so normal location jitter does not rapidly flip the state.

No numerical values in the focused tests are production GPS/reroute thresholds. Production values remain unknown until real iPhone outdoor traces justify them.

## State behavior

`NavigationRouteAdherence` is explicit:
- `unknown`: no current continuity-backed adherence conclusion;
- `onRoute`: the latest accepted deviation is inside the exit threshold;
- `suspectedOffRoute(sampleCount:)`: some evidence is outside the enter threshold, but the multi-sample/time gate is not yet satisfied;
- `offRoute`: sustained accepted deviation satisfied the active policy.

A reroute recommendation is emitted only when:
1. sustained off-route evidence satisfies both sample-count and duration requirements;
2. the cooldown permits another request;
3. no reroute has already been issued for the current episode.

Repeated far samples after one recommendation do not create request storms. Returning inside the lower threshold clears the episode. A later separate episode still respects the global cooldown.

## Monotonic ordering

Receipt uptime is process-local ordering evidence.

Each ingested deviation sample must have a strictly greater uptime than the prior observation. Equal uptime is rejected deliberately so the same accepted location fix cannot be replayed and counted multiple times toward the minimum sample requirement.

Invalid/nonfinite/negative deviation values, invalid uptime, and backwards/equal uptime fail before state mutation.

## Continuity gaps

`markContinuityInterrupted(receiptUptime:)` handles a known interval where navigation location evidence was not observed.

A gap:
- moves adherence to `unknown`;
- discards in-flight suspected/off-route evidence for the old observed segment;
- emits no reroute recommendation;
- preserves prior reroute-request cooldown history.

The first far observation after a gap starts a fresh suspected-off-route evidence span. Nembra does not pretend the missing interval proved continuous deviation.

## Replacement routes

`markReplacementRouteAccepted()` moves adherence back to `unknown` because evidence against the old geometry cannot establish adherence to the replacement route.

Cooldown history is deliberately preserved across replacement routes so a sequence of route recalculations cannot create an immediate request loop.

## Deterministic verification

The focused Swift 6.2.1 harness passed:
- **13/13 debug tests**;
- **13/13 release tests**.

Coverage includes:
- one noisy point cannot reroute;
- sample count without minimum duration cannot reroute;
- sustained accepted deviation emits exactly one recommendation;
- hysteresis-band samples do not manufacture another far-deviation sample;
- return inside the exit threshold clears the episode;
- cooldown suppresses a second episode and allows the exact boundary;
- a continuity gap invalidates in-flight confidence;
- replacement-route acceptance resets adherence while preserving cooldown;
- equal/backwards uptime fails atomically;
- invalid deviation and uptime fail atomically;
- invalid policy combinations fail closed.

These are software-domain checks only. The repository's exact-head Xcode 27 gate is still required on the final reconciled head before acceptance.

## Explicit non-goals

This slice does not implement:
- geometry projection or nearest-route-point math;
- current/next maneuver selection;
- MapKit route requests;
- request cancellation/network error handling;
- destination search;
- Dashboard or map UI;
- ride/location persistence;
- background location;
- scooter legality/safety classification;
- any AOVOPRO ES80 command or BLE/Tuya behavior.

## Hardware / field status

Software policy only. Real outdoor iPhone location noise, route-corridor thresholds, reroute latency, MapKit route quality, physical iPhone performance, and physical AOVOPRO ES80 ride behavior remain unverified.
