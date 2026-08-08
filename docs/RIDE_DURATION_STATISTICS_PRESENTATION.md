# Ride Duration Statistics Presentation

## Purpose

`RideDurationStatisticsSummary` already aggregates the monotonic elapsed-time evidence Nembra actually observed for completed rides. Product UI still needs a stronger boundary than `UInt64?`: a real observed subtotal can exist even when some ride intervals are missing, and that subtotal must never be promoted into generic total ride time.

`RideDurationStatisticsPresentation` is the product-safe disclosure contract for that boundary.

It keeps four states explicit:

- `noCompletedRides` — the selected period contains no completed rides;
- `durationUnavailable` — rides exist, but none has accepted monotonic duration evidence;
- `partialObservedDuration` — a real accepted observed subtotal exists, but at least one ride is unavailable or has partial observation coverage;
- `completeObservedDuration` — every selected ride has complete accepted monotonic duration coverage.

## Truth contract

The numeric value remains `totalObservedDurationNanoseconds` because that is what the evidence proves.

It is never silently relabeled as:

- moving time;
- motor-on time;
- throttle-on time;
- time reconstructed from `endedAtDate - beganAtDate`;
- time filled across process, connection, or observation gaps;
- physical AOVOPRO ES80 telemetry.

Calendar dates remain period-attribution metadata only.

A legitimate accepted zero-duration observation remains `0`. Missing duration evidence remains `nil`; the presenter never converts unknown duration into zero.

## Partial disclosure

`partialObservedDuration` means the subtotal itself is real accepted monotonic evidence, but it is not the complete period duration. A future UI may show the subtotal only with incomplete-observation disclosure.

`requiresIncompleteDurationDisclosure` is therefore true only when a numeric subtotal is being exposed in the partial state. It intentionally remains false for `durationUnavailable`, where there is no numeric subtotal and the state already says duration is unavailable.

## Complete wording

`permitsCompletePeriodObservedDurationWording` is true only when every selected ride has complete duration coverage and a real observed subtotal exists.

Even then, wording should remain scoped to **observed duration** or equivalent. Complete observation coverage does not turn elapsed session duration into moving time or any physical motor metric.

## Defensive summary validation

The presenter treats `RideDurationStatisticsSummary` as a trust boundary rather than assuming future persistence/adapters will always preserve aggregator invariants.

Before returning product state it revalidates:

- all counts are nonnegative;
- complete + partial count addition cannot overflow;
- observed + unavailable count addition cannot overflow;
- reconciled counts exactly equal `rideCount`;
- a subtotal exists if and only if at least one ride has observed duration evidence;
- `noRides`, `unavailable`, `partial`, and `complete` availability agree with their count topology;
- a complete period cannot contain partial or unavailable duration coverage;
- a partial period cannot masquerade as an actually complete period.

Malformed or hostile summaries fail closed with `invalidSummary` instead of yielding confident product wording.

## Parallel / integration boundary

This slice is additive NembraCore package work. It does not edit `RideDurationStatistics.swift`, so it does not compete with the active history-duration attachment/join lane that owns the trusted history-to-statistics bridge.

Once that join is accepted, a future Stats/History product owner can feed its normal `RideDurationStatisticsSummary` into this presenter without rebuilding duration semantics in SwiftUI.

This slice does not modify:

- Ride History persistence or attachment storage;
- AppRoot / Ride Details / Home / Dashboard;
- Xcode project wiring;
- ride lifecycle or location capture;
- Bluetooth/Tuya acquisition;
- battery/range;
- navigation;
- vehicle commands.

The current iOS app manually compiles selected Core sources, so package acceptance does **not** imply this new source is app-visible. Production app wiring remains a later non-conflicting integration step.

## Hardware boundary

SOFTWARE PRESENTATION SEMANTICS ONLY.

No physical AOVOPRO ES80 timing source, BLE/GATT/Tuya field, reconnect behavior, background execution guarantee, speed/current/power signal, motor state, or physical ride duration is verified by this projection. Simulator/package evidence remains software evidence.