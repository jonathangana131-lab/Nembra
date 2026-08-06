# Adaptive Range Persistence Boundary

This document describes the software-only persistence integrity boundary for Nembra's learned adaptive battery/range state.

## Dependency

This slice depends on the adaptive range core introduced by PR #10. It does not replace or reinterpret the estimator.

## Why validation is required

`AdaptiveBatteryRangeModel` is `Codable` so learning can survive launches, but synthesized decoding can reconstruct values that the public ingest path could never produce if persisted JSON is truncated, edited, migrated incorrectly, or otherwise corrupted.

A decoded payload must never silently become learned scooter truth merely because its JSON shape is valid.

Higher layers that persist adaptive range learning should therefore restore through `AdaptiveBatteryRangePersistedState`, not trust a raw decoded `AdaptiveBatteryRangeModel` directly.

## Fail-closed invariants

The persistence envelope rejects state when any of these durable invariants are violated:

- historical consumed percentage is non-finite or negative;
- a learned efficiency exists without positive historical evidence, accepted windows, or retained recent evidence;
- a no-history model contains partial learned state;
- retained recent samples outnumber accepted windows;
- cumulative historical consumption exceeds the maximum possible normalized 0...100 consumption across accepted windows;
- a retained sample has non-finite/non-positive distance, consumption, or efficiency;
- a retained sample's stored efficiency no longer matches its own distance divided by consumed percentage;
- retained recent battery consumption exceeds cumulative accepted historical battery consumption;
- the persisted schema version is unknown.

These checks deliberately avoid inventing policy-specific thresholds that are not stored in the model.

## Truth boundary

This layer validates persistence integrity only.

It does **not** prove or infer:

- AOVOPRO ES80 battery percentage packet source;
- one-percent SoC resolution;
- update cadence or latency;
- voltage or charging-state availability;
- battery chemistry or usable-energy behavior;
- physical-scooter range accuracy.

Those remain separate hardware/field-validation requirements.

## Integration rule

When application persistence wiring is added, treat an invalid or unsupported persisted envelope as unavailable learned history and recover conservatively. Do not coerce invalid values into a plausible-looking estimate and do not rewrite them as measured telemetry.
