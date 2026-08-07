# Observed Power Envelope Persistence

This is a **dependent persistence layer** above the accepted `ObservedPowerEnvelope` domain originally integrated through PR #225. It does not decode ES80 telemetry, establish watts semantics, change the live learner, or wire the Dashboard.

## Construction authority stays sealed

PR #225 intentionally seals `ObservedPowerEnvelopeCalibration` construction:

- `package` under SwiftPM;
- `fileprivate` when selected Core sources are compiled directly into the app target.

Persistence must not reopen that boundary just to make old state resemble freshly minted live-domain calibration.

Therefore durable restore returns `ObservedPowerEnvelopeRestoredCalibration`, a separate read-only value containing the validated retained scope, authority, observed ceiling, derived gauge scale, and validation counts. It cannot be inserted into `ObservedPowerEnvelopeLearner` as fresh evidence or forged into the parent domain calibration through this layer.

## Public Codable is Simulator-only

`ObservedPowerEnvelopeCalibrationCheckpoint` remains Codable for Simulator/runtime QA and deterministic testing, but ordinary `JSONDecoder` is intentionally **not** a verified-physical import path.

Even a syntactically valid payload with the matched strings:

- `verifiedVehicleIdentity`
- `verifiedVehicleMeasurement`

is rejected by the public decoder with `authorityMismatch`.

Verified physical disk bytes first decode into the journal's non-authoritative `StoredCheckpointWire`. Under SwiftPM only, that wire can be converted through the package-sealed `verifiedStoredFields(...)` boundary and then restored only after exact current physical scope + policy validation.

This distinction matters: Codable bytes are data, not physical provenance.

## Persisted calibration facts

A checkpoint stores only validated calibration facts:

- exact opaque vehicle identity key;
- optional confirmed-mode key;
- identity/evidence authority class;
- exact software learning policy;
- learned observed ceiling watts;
- learning/support counts required to validate that calibration.

The gauge scale is re-derived from the retained observed ceiling and exact headroom policy instead of persisting a second redundant floating-point truth.

A checkpoint never stores:

- observation scope objects as reusable evidence tokens;
- receipt sequence or process uptime chronology;
- the learner's rolling eligible-power window;
- individual physical measurements;
- display-interpolated frames;
- throttle, regen, rated maximum, battery/thermal state, or any unverified ES80 protocol meaning.

A new process/session starts new observation chronology and a new learning window. Old callback ordering cannot become fresh evidence after relaunch.

## Restore boundary

Decode/restore is fail-closed. Schema, identity strings, authority pairing, learning policy, learned ceiling, sample count, support count, and derived scale must validate.

Simulator restore additionally requires the exact current Simulator `ObservedPowerEnvelopeScope` and policy.

Verified-physical snapshot/restore/reconciliation stays package-sealed under SwiftPM and file-local outside it. The trusted journal path is:

verified learner
→ package-sealed checkpoint snapshot
→ non-authoritative stored wire
→ package-sealed stored-wire conversion
→ exact current physical scope/policy restore
→ read-only retained calibration.

No public generic decoder or public durable-store method is part of that chain.

## Relaunch floor and upward hysteresis

A validated retained calibration is a presentation **floor** for the same scope + policy. Lower current-session output cannot silently shrink an already learned observed full-power region.

A fresh learner starts without the retained calibration, so its first newly established scale must not bypass #225's scale-stability policy merely because it is slightly higher. Reconciliation reapplies the exact retained policy's `upwardHysteresisFraction` across the process boundary:

`current scale > retained scale × (1 + upward hysteresis)`

Lower/equal, uncalibrated, non-finite-threshold, and sub-hysteresis cases keep the retained value. Only a strictly qualified same-scope/same-policy/same-authority increase may advance the effective calibration.

The selected result carries explicit provenance:

- `retainedCheckpoint`, or
- `currentSession`.

That is calibration provenance, not telemetry evidence.

## Persistence-write reconciliation

The floor and hysteresis rule apply on writes too. Once a durable checkpoint exists, callers must not create a lower or merely marginally higher fresh checkpoint and overwrite it directly.

Use:

- `reconciledSimulatorQACheckpoint(with:)` for Simulator/runtime QA;
- package-sealed `reconciledVerifiedVehicleMeasurementCheckpoint(with:)` for trusted production integration.

The atomic journal independently re-applies the same final durable-write floor. Equal, lower, or merely sub-hysteresis candidates return `.retainedExisting` without creating a new generation.

## Crash-tolerant two-slot journal

`AtomicObservedPowerEnvelopeCheckpointStore` uses two atomic journal slots instead of a single fragile JSON file or high-frequency preferences write.

Each checkpoint record carries:

- outer journal schema;
- monotonic persistence generation;
- record kind (`checkpoint` or `cleared`);
- non-authoritative stored checkpoint wire when kind is `checkpoint`.

Normal checkpoint saves write to the older/unused slot with Foundation atomic replacement and immediately read/validate the new record before reporting success.

Durability behavior includes:

- corrupt newest slot falls back to an older known-good recognized record;
- both corrupt -> fail closed until explicit clear/recovery;
- unsupported **outer journal schema** -> never silently overwrite during normal load/save;
- unsupported **inner calibration-checkpoint schema** -> independently detected and preserved during normal load/save;
- equal persistence generation with divergent payloads -> conflict;
- semantically invalid current-schema inner checkpoint -> corrupt journal data;
- generation overflow -> fail without replacing retained calibration;
- one corrupt + one unused slot -> normal save uses the unused slot and preserves the sole forensic corrupt copy;
- a live checkpoint progression is bound to exact vehicle/mode identity, authority pair, and learning policy;
- two adjacent checkpoint generations must themselves show legal upward-hysteresis progression.

## Clear is a monotonic tombstone operation

Deleting slot A and slot B sequentially is unsafe. A process death after only one deletion can leave the surviving older checkpoint looking authoritative again after relaunch.

`clear()` therefore does **not** implement logical clear as sequential deletion.

It performs two atomic monotonic writes:

1. **barrier tombstone** — write generation `maxKnown + 1` to an invalid/missing slot when available, otherwise the older recognized slot;
2. **scrub tombstone** — write generation `maxKnown + 2` to the remaining slot.

The first tombstone is the semantic clear commit point. If the process dies immediately afterward:

- any surviving recognized checkpoint has a lower generation, so the clear tombstone wins;
- an unsupported-format survivor keeps normal load fail-closed rather than allowing fallback;
- a corrupt survivor cannot manufacture a retained checkpoint.

Phase two removes the stale checkpoint payload from the other slot by replacing it with an even newer tombstone.

This is tested in both slot parities:

- A older / B newer, interrupted after A becomes the clear barrier;
- B older / A newer, interrupted after B becomes the clear barrier.

Relaunch returns cleared in both cases and a later save may explicitly rebind to a different scooter/mode without resurrecting the pre-clear calibration.

Explicit `clear()` is also the destructive recovery operation for corrupt, conflicting, or unsupported journal contents. Normal load/save remain conservative; clear may intentionally overwrite unknown records, but its first durable barrier is chosen so an interruption never exposes an older recognized checkpoint as cleared-state truth.

## Durable authority APIs

Public store API:

- `saveSimulatorQA(_:)`
- `loadSimulatorQA()`
- `clear()`

The public store cannot durably write or read a verified-physical checkpoint.

SwiftPM package-only physical API:

- `saveVerifiedVehicleMeasurements(from:)` — takes the package-sealed verified learner, snapshots it, then persists the wire;
- `loadVerifiedVehicleMeasurement(expectedScope:expectedPolicy:)` — decodes the wire, performs package-sealed verified conversion, then exact physical scope/policy restore.

This is a compile-time product-authority boundary, **not hostile-device cryptographic attestation**. NembraCore does not invent a filesystem path, hash a BLE local name, choose a secret identity, or claim a stable physical scooter identifier. Production app integration must supply a legitimate directory/identity mapping once ES80 identity semantics are verified.

Calibration writes should remain infrequent and event-driven. No display clock, BLE cadence, interpolation frame, or map/render refresh should cause journal writes.

## Retained calibration -> propulsion presentation

Durable calibration must be usable by the gauge without reconstructing `ObservedPowerEnvelopeCalibration` and pretending retained history is fresh live evidence.

`PropulsionGaugeScale.observedEnvelope(_:)` accepts:

- `ObservedPowerEnvelopeRestoredCalibration`; and
- `ObservedPowerEnvelopeEffectiveCalibration` after relaunch reconciliation.

The bridge carries forward only the validated exact vehicle/mode identity, evidence authority, and already-derived learned gauge scale. It does not copy raw observations, chronology, peaks, display frames, or learning eligibility into presentation.

Simulator-restored calibration produces only a Simulator presentation scale. Under SwiftPM, a verified retained calibration can produce a verified-observed-envelope scale because the physical restore that minted that retained value is already package-sealed. In the direct-source build, the separate-file verified adaptation intentionally fails closed rather than reaching across `fileprivate` authority boundaries.

## Product boundary

This closes the **NembraCore durable calibration -> retained presentation scale** rung only.

The current app target still does not directly compile the complete observed-envelope/persistence/presentation stack. Production wiring still needs:

- a legitimate persistent directory policy;
- stable verified per-scooter identity;
- verified ES80 current/power source, units, scale, signedness, cadence, and provenance;
- safe app/project integration after current high-contention owners permit it.

## Hardware status

**NOT VERIFIED ON PHYSICAL AOVOPRO ES80.** No physical ES80 power/current field, DP, characteristic, scale, cadence, throttle signal, regen semantic, battery/thermal condition, stable physical persistence identity, or actual full-power ceiling is claimed by this persistence work.
