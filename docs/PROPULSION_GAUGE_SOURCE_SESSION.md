# Propulsion Gauge Source Session

## Purpose

`PropulsionGaugeSourceSession` is the source-lifecycle owner between an already-authoritative propulsion sample stream and Nembra's canonical propulsion presentation model.

It exists because asynchronous transport lifecycle callbacks have their own chronology. A delayed disconnect from generation 4 must not hide an accepted generation-5 measurement, while an interruption seen before the first sample must still fence delayed samples from that retired generation.

This layer does **not** identify an ES80 GATT/DP field, derive watts, mint verified measurement authority, infer throttle, infer regen, choose a physical maximum, or convert disconnect into measured zero.

## Generation fencing

Retirement floors are tracked independently per `PropulsionPowerSampleAuthority`.

The session:
- rejects cross-identity samples before consulting retirement history;
- rejects samples from a retired authority/generation;
- ignores older same-authority interruptions for presentation while still remembering their retirement floor;
- records inactive-authority interruptions without hiding the active authority;
- fences an interruption that arrives before any accepted measurement;
- when a newer source generation fails before data, hides older active evidence and requires a genuinely newer generation before resumption.

The source/transport owns `continuityGeneration`. Presentation code must never invent a generation merely to force a UI state change.

## Animation and freshness are independent

Merged propulsion freshness work split:
- `PropulsionGaugeAnimationPolicy`: render-clock response only;
- `PropulsionGaugeFreshnessPolicy`: accepted-measurement currentness only.

The recovered source session exposes a preferred split initializer and read-only split policies. The old combined `PropulsionGaugeMotionPolicy` initializer/property remain only as compatibility adapters.

This prevents Reduce Motion or other visual tuning from accidentally extending or shortening how long accepted physical evidence is presented as live.

## Canonical product projections

The wrapped `PropulsionGaugeDisplayModel` remains private. Instead of making app/UI code reconstruct evidence rules, the session forwards the canonical projections already accepted on main:

- `frame(...)`: low-level accepted + render state; `displayWatts` is still render-only;
- `accessibilitySnapshot(...)`: accepted-only currentness/provenance for accessibility;
- `cockpitSnapshot(...)`: merged cockpit separation between accepted numeric power and render-only band/peak motion;
- `observedScaleRegionSnapshot(...)`: accepted observed-scale semantics and the sealed verified `Near observed max` wording gate.

Forwarding does not create new authority. In particular, Simulator near-edge QA remains Simulator-only and cannot satisfy verified wording permission.

## Product integration direction

A later production read-only vehicle service should feed this session only after ES80 power semantics are physically verified and converted into the package-sealed verified measurement type. SwiftUI should then consume the forwarded product projections rather than owning source chronology, stale policy, accepted-vs-interpolated separation, or near-observed-max authority rules.

The production app target currently compiles only selected NembraCore source files manually. This package/domain slice is therefore not itself proof that the live Dashboard is wired to this source session.

## Truth boundary

**SOFTWARE / SOURCE-LIFECYCLE AND PRESENTATION COMPOSITION ONLY — NOT PHYSICAL AOVOPRO ES80 PROOF.**

No physical ES80 battery, voltage, current, watts, GATT/DP identity, units, scaling, signedness, cadence, throttle, regen, rated maximum, command acknowledgement, or stable learned physical ceiling is established here. Simulator remains Simulator evidence; observed-envelope presentation scale remains distinct from rated hardware maximum.
