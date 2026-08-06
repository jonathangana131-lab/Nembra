# Battery Evidence Availability and Freshness

Status: software-only current-process availability policy. No AOVOPRO ES80 battery cadence, latency, staleness threshold, or protocol field is physically verified by this slice.

## Purpose

A value can be truthfully classified and still be too old to present as current live information.

Nembra therefore needs a separate freshness/availability layer after:

1. battery semantic-value validation;
2. truth-role classification;
3. stream ordering/continuity validation;
4. current-segment snapshot assembly.

Freshness must not be hidden inside any of those earlier layers because age does not change what the evidence *is*.

## No guessed ES80 thresholds

`BatteryEvidenceFreshnessPolicy` contains injected per-field maximum ages.

There are deliberately no production ES80 defaults in NembraCore. Physical capture must establish useful cadence/latency behavior before the app chooses thresholds for SoC, voltage, current, power, or charging state.

A field with no configured maximum age is `unclassified`, not assumed fresh and not assumed stale. This lets software preserve evidence without pretending the real scooter updates at a cadence that has not been measured.

A configured maximum age must be greater than zero.

## Availability states

For one current-segment observation:

- `unavailable` — there is no current-segment observation for that field;
- `unclassified` — evidence exists, but no evidence-backed freshness threshold is configured;
- `fresh` — process-local age is at or below the injected maximum age;
- `stale` — process-local age is above the injected maximum age.

Stale evidence is retained in the availability value rather than erased. A higher presentation/service layer may decide whether to show a retained/stale treatment, but it must not label stale evidence as live.

## Uptime only

Freshness uses `receivedAtUptimeNanoseconds` and a caller-supplied current uptime from the same process/boot epoch.

Wall-clock `Date` is metadata only and does not influence freshness. The system clock can move while the process is alive.

An observation whose receipt uptime is later than the supplied current uptime fails closed as `observationFromFutureUptime`.

The parent current-segment accumulator is intentionally process-local and clears across explicit continuity gaps, so this evaluator does not persist or compare uptime values across launches.

## Independent field cadence

Each field has an independent injected limit. A future physical ES80 capture may show, for example, that voltage updates much faster than battery percentage or vice versa. NembraCore does not assume they share one cadence.

The evaluator can therefore classify a single current snapshot with mixed results such as:

- SoC fresh;
- voltage stale;
- current unavailable;
- power unclassified.

That is more truthful than collapsing the whole battery subsystem into one Boolean `isLive` flag.

## Truth-role independence

Freshness never promotes evidence.

A stock-app correlation anchor can be fresh relative to a correlation/testing policy and still remain only a stock-app correlation anchor. It does not become verified electrical telemetry.

Likewise, a verified vehicle measurement can become stale without losing its provenance as a previously verified measurement. Provenance and current availability are separate axes.

## Not included

This slice does not:

- choose real ES80 freshness thresholds;
- infer Bluetooth/transport gaps from age alone;
- decode battery fields;
- establish packet grouping or cadence;
- convert voltage to SoC;
- calculate energy or Wh/mi;
- train adaptive range;
- persist process uptime freshness state;
- decide final UI labels/animation;
- enable motorized-hardware writes.

Production thresholds remain field-validation work and should be injected only when measured evidence supports them.
