# Adaptive Range Persistence Envelope

This document describes the software-only persistence envelope for Nembra's learned adaptive battery/range state.

## Dependency

This slice depends on the adaptive range core in PR #10. The parent model validates its decoded scalar/sample invariants, rejects an exhausted accepted-window counter at restore and live-ingest boundaries, and validates Codable restoration of normalized SoC readings, learning windows, estimator policy, and range-estimate outputs. This slice does not duplicate or replace that logic.

## Why the envelope exists

Learned range state needs to survive app launches without allowing old, shape-compatible, or cross-field-corrupted persistence to silently become battery/range truth.

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

The envelope deliberately does not invent a device-specific identifier. Nembra's current generic vehicle domain has model/profile identity, but the project has not yet established which ES80 identity is stable and appropriate for durable per-scooter learning storage.

That uncertainty is **not permission to wait for user-supplied hardware evidence before researching it**. Follow the repository's public-first ES80 protocol policy: exhaust reasonable official/public evidence, cross-correlate likely module/protocol identity sources, and preserve the distinction between `DIRECT PHYSICAL / APP OBSERVATION`, `VERIFIED PUBLIC`, `CORROBORATED / PROBABLE`, `GENERIC TUYA / FAMILY FACT`, and `UNKNOWN / PHYSICAL VERIFICATION REQUIRED`. Public evidence may narrow or establish the storage-key architecture without being mislabeled as device validation, while stock-app observations remain correlation anchors until their raw source is mapped.

Current direct app observation on the 2025-generation target includes live battery percentage, voltage, current, and power. Those values prove the current stock stack exposes useful electrical telemetry, but they do **not** establish raw BLE/Tuya DP identifiers, units/scaling, cadence, signedness, derivation, or a stable per-device persistence key. Local-name strings alone are not safe identity keys.

The inherited Tuya transport research also shows that some local protocol families use sensitive device identity/encryption material such as a local key and session key. A future learned-range storage key must not embed, log, export, or use raw secret credentials as its durable identity value. If legitimate pairing/binding evidence is needed to resolve identity, secrets belong in an appropriate local secure-storage path and exported persistence/evidence should use a non-secret stable identifier or opaque derived handle whose semantics are explicitly documented.

When application persistence wiring is added, each envelope must be scoped to one scooter using a legitimate stable identity source whose evidence class is recorded. If public evidence is enough to define a safe candidate identity mechanism, implement/test that mechanism while retaining the appropriate confidence classification; use an ES80 capture only for the remaining device-specific or final verification step. Until identity semantics are sufficiently established, learned history must not be silently shared between different scooters merely because they use the same `VehicleProfile`.

Simulation/test identities remain simulation/test evidence and must not be promoted into a claim about real ES80 identity semantics.

Schema versioning also leaves room for a future verified energy-based estimator without relabeling today's percent-based learned history as current, power, energy, or `Wh/mi`. Those stronger metrics require verified raw semantics and timing first.

## Failure behavior

If the envelope cannot be decoded or validated, higher layers should treat learned range history as unavailable and recover conservatively. Invalid values must not be coerced into plausible-looking range, measured SoC, or telemetry.

## Truth boundary

This layer validates software persistence integrity only. It does **not** prove or infer:

- AOVOPRO ES80 raw battery BLE/Tuya DP source;
- one-percent SoC resolution;
- battery update cadence or latency;
- raw voltage/current/power source, units, scale, signedness, cadence, or whether displayed power is derived;
- charging-state source;
- stable per-device identity semantics;
- battery chemistry, sag, reserve, or cutoff behavior;
- physical-scooter range accuracy.

Those remain separate protocol/public-evidence/field-validation requirements according to their evidence tier.
