# Propulsion Gauge Source Session

## Purpose

`PropulsionGaugeDisplayModel` owns accepted propulsion measurements, measurement chronology, render-only interpolation, stale presentation, and its local active-generation retirement. A production asynchronous source has one additional responsibility: lifecycle callbacks such as disconnects, subscription loss, or source-session interruptions can arrive late relative to newer accepted measurements.

`PropulsionGaugeSourceSession` is the integration owner for that race. It binds source-owned `(authority, continuityGeneration)` interruption evidence to the existing display model without inventing a power measurement.

## Why the fence exists

An unscoped `markUnavailable()` is correct only when the caller already knows the callback belongs to the presentation model's current source generation. That assumption is unsafe at a transport/application boundary where asynchronous callbacks may be delayed or reordered.

Example:

1. Simulator/source generation 4 publishes accepted power.
2. The source reconnects and generation 5 publishes accepted power.
3. A delayed generation-4 interruption callback arrives.

Forwarding step 3 directly to an unscoped presentation interruption would hide fresh generation-5 evidence. `PropulsionGaugeSourceSession` instead records generation 4 as retired and leaves generation 5 live.

The opposite case also matters: an interruption may be known before a generation ever publishes its first accepted power sample. That generation is still over. The source session records the retirement floor so a delayed sample from that already-ended generation cannot later become live.

## Authority isolation

Retirement floors are independent per `PropulsionPowerSampleAuthority`.

An interruption for an inactive authority:
- fences that authority/generation against delayed replay;
- does not hide the currently presented authority;
- does not borrow or compare numeric generation values across authority domains.

A later sample from the interrupted authority must belong to a genuinely newer generation before it can be accepted.

## Active-authority rules

For the same authority as the latest accepted sample:
- older interruption generation -> record the old retirement and keep newer accepted evidence live;
- equal interruption generation -> mark live presentation unavailable and retire the active generation;
- newer interruption generation -> mark presentation unavailable and fence through that failed/newer generation, requiring a later generation to resume.

A newer interruption is useful for a reconnect/session attempt that becomes unavailable before yielding an accepted measurement. The last numeric measurement remains metadata only; disconnect is never converted into measured zero watts.

## Measurement truth

The source session does **not**:
- construct verified physical samples;
- derive watts from cached `VehicleState`;
- treat a state replay as a fresh measurement;
- invent receipt order or continuity generation;
- choose ES80 GATT/Tuya/DP identity;
- establish scaling, units, signedness, cadence, regen, throttle position, or rated maximum;
- persist render frames as evidence.

`accept(_:)` receives an already-authoritative `PropulsionPowerSample`. The existing package-sealed physical factory remains the authority boundary.

## Presentation and accessibility

`frame(...)` forwards the existing render-only model. `accessibilitySnapshot(...)` forwards the accepted-value accessibility projection. Interruption keeps the last accepted watts available as retained/unavailable metadata where the underlying model already does so, but neither visual nor assistive presentation reports a fabricated zero-power measurement.

## Integration direction

When a verified read-only ES80 power source eventually exists, its source owner should provide:
- exact `PropulsionPowerSampleAuthority`;
- exact source-owned receipt order;
- receive uptime;
- exact source-owned continuity generation;
- scoped lifecycle interruption callbacks carrying that same authority/generation namespace.

The app/runtime bridge can then own one `PropulsionGaugeSourceSession` for the exact vehicle/mode presentation identity and feed the accepted gauge/observed-envelope path without allowing stale disconnect callbacks to invalidate newer evidence.

Simulator QA can use the same source-session lifecycle with `.simulator` samples and explicit synthetic generations. Simulator evidence remains Simulator-only and is not physical ES80 proof.

## Hardware truth boundary

This slice is software/source-lifecycle correctness only. It verifies no physical AOVOPRO ES80 power/current field, voltage field, GATT characteristic, Tuya framing, DP ID/type, scale, unit, signedness, cadence, full-power ceiling, throttle signal, regen behavior, or hardware acknowledgement.
