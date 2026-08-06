# Adaptive Range Persistence Envelope

This document describes the software-only persistence envelope for Nembra's learned adaptive battery/range state.

## Dependency

This slice depends on the adaptive range core in PR #10. The parent model already validates its own decoded scalar/sample invariants and validates Codable restoration of normalized SoC readings, learning windows, and estimator policy. This slice does not duplicate or replace that logic.

## Why the envelope exists

Learned range state needs to survive app launches without allowing old, shape-compatible, or corrupted persistence to silently become battery/range truth.

`AdaptiveBatteryRangePersistedState` adds persistence-level guarantees above the model decoder:

1. explicit schema versioning for future migrations;
2. cumulative cross-field bounds that must be true for any state produced by the public ingest path;
3. complete-history reconstruction checks when every accepted sample is still present in the retained recent window set.

Higher layers should persist and restore the envelope instead of relying on unversioned raw model JSON as a durable storage contract.

## Cumulative invariants

The envelope rejects state when:

- cumulative historical battery consumption is non-finite or negative;
- learned state lacks accepted windows/history;
- retained recent samples outnumber accepted windows;
- historical consumption exceeds `acceptedWindowCount × 100`, which is impossible when every normalized SoC anchor is constrained to `0...100`;
- retained recent sample consumption exceeds cumulative accepted historical consumption;
- every accepted sample is still retained but those samples do not reconstruct the stored cumulative consumption;
- every accepted sample is still retained but their weighted efficiency does not reconstruct the stored historical efficiency;
- the schema version is unsupported.

If older accepted samples have legitimately been truncated by `recentWindowCapacity`, the envelope does not pretend it can reconstruct unavailable history. In that case it enforces only the invariants that remain provable from the retained subset.

These checks intentionally avoid policy-specific assumptions such as minimum learning-window size or ES80 field thresholds because those values are not part of the persisted model state.

## Physical scooter scoping

The envelope deliberately does not invent a physical-scooter identifier. Nembra's current generic vehicle domain has model/profile identity, but real ES80 protocol work has not yet established which identity is stable and appropriate for durable per-scooter learning storage.

When application persistence wiring is added, each envelope must be scoped to the actual physical scooter using a legitimate stable identity source. Until that source is verified, learned history must not be silently shared between different scooters merely because they use the same `VehicleProfile`.

Simulation/test identities remain simulation/test evidence and must not be promoted into a claim about real ES80 identity semantics.

## Failure behavior

If the envelope cannot be decoded or validated, higher layers should treat learned range history as unavailable and recover conservatively. Invalid values must not be coerced into plausible-looking range, measured SoC, or telemetry.

## Truth boundary

This layer validates software persistence integrity only. It does **not** prove or infer:

- AOVOPRO ES80 battery packet source;
- one-percent SoC resolution;
- battery update cadence or latency;
- voltage or charging-state availability;
- stable physical-scooter identity semantics;
- battery chemistry, sag, reserve, or cutoff behavior;
- physical-scooter range accuracy.

Those remain separate hardware/field-validation requirements.
