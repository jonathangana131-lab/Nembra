# Verified Battery Electrical Coherence

Status: software-only temporal pairing boundary for future verified-live voltage/current evidence. No physical AOVOPRO ES80 electrical field, cadence, synchronization, signedness convention, or energy behavior is verified by this slice.

## Purpose

Even after voltage and current are individually:

- semantically valid;
- inside the current evidence segment;
- fresh under evidence-backed field policies;
- physically verified in provenance;

they still must not be assumed synchronous.

A future energy/power path must not multiply or integrate arbitrary "latest voltage" and "latest current" observations merely because both happen to exist.

`BatteryVerifiedElectricalPairEvaluator` establishes a narrow temporal-coherence boundary first.

## Injected skew policy

`BatteryElectricalCoherencePolicy.maximumVoltageCurrentSkewNanoseconds` is caller supplied.

There is deliberately no ES80 default. Physical capture must determine whether voltage/current are:

- emitted in one decoded callback;
- emitted separately but near-synchronously;
- updated at materially different cadence;
- or unsuitable for pairing at all.

A maximum skew of `0` means only exact same-receipt-uptime observations are pairable. Any nonzero tolerance must be justified by later physical evidence.

## Pair states

The evaluator considers only `verifiedLiveObservation(for:)` from the parent live-truth snapshot.

It returns:

- `unavailable` — neither verified-live voltage nor verified-live current exists;
- `voltageOnly` — verified-live voltage exists without verified-live current;
- `currentOnly` — verified-live current exists without verified-live voltage;
- `coherent` — both exist and absolute receipt-uptime skew is within the injected policy;
- `incoherent` — both exist but their skew exceeds the injected policy.

The observations and measured skew are preserved so later diagnostics can explain why a pair was accepted or rejected.

## What is excluded before pairing

The evaluator cannot pair:

- stale verified evidence;
- freshness-unclassified evidence;
- stock-app correlation anchors;
- Simulator fixtures;
- derived estimates;
- presentation-only values.

Those states do not expose a `verifiedLiveObservation` through the parent boundary.

## Power remains independent

A separately verified-live `powerWatts` observation does not substitute for missing voltage/current and is not used to prove voltage/current coherence.

Nembra must separately determine whether ES80 wattage is independently transmitted or derived in the stock stack before choosing how that field participates in any energy model.

## Signed current

The pairing layer preserves the current value exactly. It does not assume positive means discharge, negative means regenerative braking/charging, or vice versa.

That convention remains physical protocol validation work.

## No electrical math yet

A coherent pair is only temporal-evidence permission for a future layer to *consider* using the two observations together.

This slice deliberately does **not** calculate:

- `voltage × current` watts;
- watt-hours;
- Wh/mi;
- charge/discharge energy;
- regenerative energy;
- battery health;
- remaining range.

Those require additional raw-source, timing, and semantics evidence.

## Not included

This slice does not:

- verify ES80 voltage/current source or scale;
- choose a real pairing skew;
- establish sampling cadence;
- infer missing samples;
- interpolate electrical telemetry;
- integrate energy;
- change adaptive-range learning;
- wire UI;
- persist process-local pairing state;
- authorize motorized-hardware writes.
