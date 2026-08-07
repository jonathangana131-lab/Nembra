# Battery Evidence Live Truth

Status: software-only projection from battery freshness + provenance into explicit live-truth states. No physical AOVOPRO ES80 telemetry field or cadence is verified by this slice.

## Purpose

`fresh` and `verified` answer different questions:

- freshness asks whether an observation is recent enough under an evidence-backed injected policy;
- verification asks whether the normalized value is actually proven to represent the target scooter field.

Nembra must require both before a field is allowed to appear as **verified live vehicle evidence**.

A stock-app number can be very recent and still be only a correlation anchor. A verified value can be real but stale. Collapsing those axes into one `isLive` Boolean would create false confidence.

## Construction boundary follows both Nembra build graphs

`BatteryEvidenceLiveTruthSnapshot` is public as a read-only output type, but production raw state-dictionary construction is **file-scoped**.

The field-level availability→live-truth projection is also file-scoped in direct app-source compilation. `BatteryEvidenceFieldAvailability` is intentionally descriptive/public; if an arbitrary app source could call a same-module field resolver, it could hand-construct `.fresh(...)` and obtain `verifiedLive` without the aggregate uptime/policy path.

This must account for Nembra's current iOS build graph, where selected package-domain source files may be manually compiled directly into the `Nembra` app target. Plain `internal` would therefore be insufficient as a production trust boundary.

The source uses two explicit paths:

- direct app-source compilation: raw live-truth snapshot construction and field-level projection remain file-scoped;
- real Swift-package compilation (`SWIFT_PACKAGE`): internal fixture seams remain available to focused NembraCore/dependent package tests, while external package clients remain blocked.

The production live-truth path remains:

`BatteryEvidenceSnapshotAccumulator.currentSnapshot`
→ `BatteryEvidenceAvailabilityEvaluator.snapshot(...)`
→ `BatteryEvidenceLiveTruthResolver.resolve(availabilitySnapshot)`

A direct same-module compile probe without `SWIFT_PACKAGE` fails to construct current-segment, availability, or live-truth aggregates and fails to call the field-level resolver. The same package fixture spellings compile with `SWIFT_PACKAGE`. This is supplemental software evidence, not hosted acceptance or physical ES80 proof.

## Live-truth states

`BatteryEvidenceLiveTruthResolver` projects field availability into:

- `unavailable` — no current-segment evidence exists;
- `freshnessUnclassified` — evidence exists, but no legitimate maximum age is configured;
- `stale` — evidence exists but is older than its injected freshness policy;
- `freshNonAuthoritative` — evidence is fresh but its role is not `verifiedVehicleMeasurement`;
- `verifiedLive` — and only here, evidence is both fresh and already physically verified in provenance.

The original observation is preserved in every non-unavailable state so diagnostics or a detailed UI can explain why a value is not promoted.

The enum cases themselves are descriptive values. Downstream trusted code must consume a sealed `BatteryEvidenceLiveTruthSnapshot`, not treat a caller-constructed enum case as proof that the production resolver ran.

## What can become verified live

A SoC, voltage, current, power, or charging-state observation may become `verifiedLive` only if:

1. upstream semantic validation accepted the value;
2. upstream stream/snapshot logic kept it inside the current uninterrupted evidence segment;
3. upstream freshness evaluation classified it `fresh` using an injected field policy;
4. its existing role is `verifiedVehicleMeasurement`.

This means future physical ES80 validation can enable individual fields independently without rewriting the live-truth model.

## Fresh but nonauthoritative evidence

The following roles never become `verifiedLive` merely because their timestamps are recent:

- `stockAppCorrelationAnchor`;
- `simulationFixture`;
- `derivedEstimate`;
- `presentationOnly`.

They become `freshNonAuthoritative` instead.

## Stale verified evidence

A stale observation keeps its original verified provenance but is not currently live.

This prevents two opposite mistakes:

- deleting the fact that a field was legitimately measured;
- presenting an old measurement as current vehicle state.

Retained-history UI policy belongs above this domain boundary.

## Unknown freshness

`freshnessUnclassified` is also not live. Until physical field cadence supports a threshold, Nembra refuses to guess whether a value is still current.

This is especially important for the ES80 because battery %, voltage, current, and power may prove to have different native update behavior.

## Snapshot resolution

`BatteryEvidenceLiveTruthSnapshot` resolves every semantic field independently and exposes `verifiedLiveObservation(for:)` as the narrow safe consumer path for later production integrations.

A mixed snapshot can therefore truthfully contain, for example:

- verified-live SoC;
- stale verified voltage;
- fresh but stock-app-only current;
- freshness-unclassified verified power;
- unavailable charging state.

## Not included

This slice does not:

- verify any physical ES80 battery field;
- choose freshness thresholds;
- infer continuity gaps from age;
- derive SoC, energy, or Wh/mi;
- decide final Home/Dashboard visual treatment;
- permit simulated evidence to masquerade as physical data;
- wire adaptive range;
- persist process-local availability state;
- authorize any motorized-hardware write.
