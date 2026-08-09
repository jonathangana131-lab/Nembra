# Accepted adaptive-range persistence journal

## Scope

This V14 slice is package-domain persistence authority for accepted learned battery/range history.
It is intentionally **not** app wiring and does not establish any physical AOVOPRO ES80 field,
vehicle identity, distance source, range number, or battery protocol semantic.

The parent lineage is:

1. #1421 receipt/continuity-bound accepted range authority;
2. #1423 accepted battery chronology -> accepted learning-window candidates;
3. this journal -> durable, replay-verifiable, exactly-once accepted model history.

## Why raw model Codable is not enough

`AdaptiveBatteryRangeModel` remains reusable pure math. Generic JSON must not become production
learned-history authority merely because its shape is valid. `AcceptedAdaptiveBatteryRangeModel`
is deliberately non-Codable and exposes only a package-trusted restore hook.

This journal therefore stores the ordered normalized facts of **only candidates that the accepted
model actually learned**. Restore replays every record through the validated raw model inside
NembraCore. Only after the complete journal reproduces accepted history does the package wrap the
result through `AcceptedAdaptiveBatteryRangeModel(trustedRestoredModel:)`.

A decoded checkpoint by itself is data, not live/physical authority.

## Exactly-once identity

Process-local battery receipt identity is unsuitable for crash/relaunch dedupe. Acquisition epochs
exist to prove current callback chronology and deliberately are not Codable.

Every candidate commit therefore requires a separate durable identity:

- durable source session UUID;
- deterministic candidate ordinal inside that durable source;
- explicit identity authority (`verifiedDurableSource` or `simulatorQA`).

The persistence scope separately requires a stable vehicle identity key and optional operating-mode
key. Verified physical scope construction is package-sealed.

The higher layer that eventually wires real rides must bind the source session to durable ride/evidence
history and reproduce candidate ordinals deterministically. This slice does **not** invent that mapping.
Until a verified stable physical ES80 identity exists, production verified scope creation remains an
unfulfilled integration dependency rather than falling back to BLE local name, profile name, or Tuya
family clues.

## Commit semantics

For one durable candidate identity:

- first accepted model result -> journal once;
- deferred result -> do not consume identity; it may later be retried when legitimate plausibility
  evidence exists;
- rejected result -> do not journal;
- exact same committed evidence -> idempotent `alreadyCommitted`, no second model mutation;
- same identity with different SoC/distance/coverage/gap evidence -> fail closed with
  `candidateIdentityConflict`.

Policy/plausibility tuning is retained with the original committed record so restore can reproduce
why the history was accepted. A later exact-evidence replay under different tuning is still the same
already-consumed physical span and is not learned twice.

All throwing journal preconditions are checked before accepted-model mutation. The accepted model and
journal record then advance in one in-memory transition. Durable storage still needs a higher-layer
atomic file/store commit of the returned checkpoint; this package slice does not claim filesystem
atomicity by itself.

## What is intentionally not persisted

The checkpoint never persists these as fresh/live authority:

- `BatteryEvidenceReceiptIdentity`;
- acquisition epoch;
- callback receipt sequence;
- live monotonic receipt uptime;
- `AcceptedBatterySOCAnchor` currentness;
- continuity-segment authority.

Accepted candidate construction already consumed those live proofs before the model learned. Replay
uses deterministic synthetic ordering timestamps only because the pure math window validates
start-before-end ordering; those synthetic values are never telemetry or physical evidence.

## Restore checks

Verified restore requires all of the following:

- exact supported schema;
- exact independently supplied expected vehicle/mode scope;
- candidate identity authority matching the scope authority;
- contiguous journal sequence indices;
- no duplicate durable candidate identities;
- finite, positive, decreasing-SoC learning geometry;
- valid normalized SoC/window construction;
- evidence-backed first-window plausibility ceiling;
- any retained absolute plausibility ceiling still covering that candidate;
- raw-model replay returns `.accepted` for every stored record under its original policy;
- final accepted-window count exactly equals journal record count.

If any check fails, accepted model authority is not restored.

## Non-claims / blockers above this slice

This work does not claim:

- verified ES80 battery percentage or scaling;
- verified voltage/current/watts/Wh/Wh-per-mile semantics;
- a stable physical ES80 identity key;
- a trusted real ride-distance completeness adapter;
- a durable ride -> candidate-ID binding;
- a physical plausibility ceiling;
- app/Home/Dashboard learned-range availability;
- physical validation.

Those remain explicit upstream/integration gates. No manufacturer-range × battery-% fallback is added.

**Hardware status: SOFTWARE FOUNDATION ONLY — PHYSICAL ES80 EXPERIMENT ONE REMAINS NO-GO.**
