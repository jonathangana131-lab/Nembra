# Observed Power Envelope Persistence

This slice is a **dependent persistence layer** above the `ObservedPowerEnvelope` domain owned by authoritative PR #225. It does not decode ES80 telemetry, establish watts semantics, change the live learner, or wire the Dashboard.

## What persists

Only a validated learned calibration checkpoint:

- exact opaque vehicle identity key;
- optional confirmed-mode key;
- identity/evidence authority class;
- exact software learning policy;
- learned observed ceiling watts;
- learning/support counts needed to validate that calibration.

The gauge scale is recomputed from the retained observed ceiling and the exact retained/expected headroom policy instead of persisting a second redundant floating-point truth.

## What never persists

A checkpoint intentionally excludes:

- receipt sequence / process uptime / observation chronology;
- the learner's rolling eligible-power window;
- individual physical measurements;
- display-interpolated frames;
- throttle, regen, rated maximum, battery/thermal state, or any unverified ES80 protocol meaning.

Receipt ordering and process uptime cannot safely be treated as fresh after relaunch. A new learner starts a new chronology and evidence window. Persistence stores only the already-established calibration result.

## Restore boundary

Decode is fail-closed. Schema, identity strings, authority pairing, learning policy, learned ceiling, sample count, support count, and derived scale must validate.

Restore additionally requires the caller to supply the exact current scope and policy. Verified-physical snapshot/restore entry points remain package-sealed, matching the upstream authority boundary; public clients can exercise only Simulator/runtime-QA persistence.

The persisted count invariants intentionally match #225's rolling-window semantics: `learningSampleCount` is the current bounded eligible-power window count, and `upperBandSupportCount` is computed from that same window. Decode therefore requires the sample count to remain within the retained policy's `windowCapacity` and support to remain within the sample count.

## Relaunch behavior

A validated retained calibration acts as a presentation **floor** for the same scope + policy. A current-session learner may replace it only after learning a strictly higher gauge scale. Lower current-session output cannot silently shrink the retained ceiling and turn temporary low-battery/thermal/partial-demand behavior into a new visual "full power" baseline.

The effective result carries explicit provenance:

- `retainedCheckpoint`, or
- `currentSession`.

That provenance is presentation/calibration state, not telemetry evidence.

## Persistence-write reconciliation

The retained floor must survive the **write** side as well as the read/presentation side. Once a checkpoint already exists, callers must not independently snapshot a lower fresh-session learner and overwrite durable state with it.

Use the reconciliation APIs when an existing checkpoint is present:

- `reconciledSimulatorQACheckpoint(with:)` for Simulator/runtime QA;
- package-sealed `reconciledVerifiedVehicleMeasurementCheckpoint(with:)` for trusted production integration.

These APIs first validate the exact retained scope, policy, and authority against the current-session learner. If the new session is uncalibrated or has learned a lower/equal scale, the existing checkpoint is returned unchanged. Only a strictly stronger calibration for the exact same scope/policy/authority produces a replacement checkpoint.

The one-shot snapshot constructors remain appropriate for creating an initial checkpoint when no retained checkpoint exists. They must not be used to bypass reconciliation once durable state already exists.

## Ordering compatibility

Authoritative #225 separates strict source-owned `receiptSequenceNumber` from monotonic receipt uptime and allows equal uptime ticks when receipt sequence advances. Persistence deliberately stores neither chronology field. The current-parent regression suite establishes a calibration from multiple equal-uptime observations with distinct receipt sequences, then persists/restores it without turning that old ordering metadata into fresh post-launch evidence.

## Dependency and hardware status

This successor branch is cleanly based on authoritative PR #225 head `813b013944a939101e89ee33010748b6fc4307d0`. It supersedes the earlier persistence draft that was based on a pre-receipt-sequence parent snapshot.

PR #225 still has a separate scope-attribution review blocker: accepted observations need to become mechanically bound to the exact vehicle/mode scope before the calibration domain is production-ready. If #225 changes that upstream contract, this persistence slice must reconcile to the accepted exact parent head and rerun validation.

**HARDWARE STATUS: NOT VERIFIED ON PHYSICAL AOVOPRO ES80.** No physical ES80 power/current field, DP, characteristic, scale, cadence, throttle signal, regen semantic, or actual full-power ceiling is claimed by this persistence work.
