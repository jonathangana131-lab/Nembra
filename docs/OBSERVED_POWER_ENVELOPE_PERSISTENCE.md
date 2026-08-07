# Observed Power Envelope Persistence

This slice is a **dependent persistence layer** above the `ObservedPowerEnvelope` domain owned by PR #214. It does not decode ES80 telemetry, establish watts semantics, change the live learner, or wire the Dashboard.

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

- process uptime / observation chronology;
- the learner's rolling eligible-power window;
- individual physical measurements;
- display-interpolated frames;
- throttle, regen, rated maximum, battery/thermal state, or any unverified ES80 protocol meaning.

Process uptime and rolling evidence cannot safely be treated as fresh after relaunch. A new learner starts a new chronology and evidence window.

## Restore boundary

Decode is fail-closed. Schema, identity strings, authority pairing, learning policy, learned ceiling, sample count, support count, and derived scale must validate.

Restore additionally requires the caller to supply the exact current scope and policy. Verified-physical snapshot/restore entry points remain package-sealed, matching the upstream authority boundary; public clients can exercise only Simulator/runtime-QA persistence.

## Relaunch behavior

A validated retained calibration acts as a presentation **floor** for the same scope + policy. A current-session learner may replace it only after learning a strictly higher gauge scale. Lower current-session output cannot silently shrink the retained ceiling and turn temporary low-battery/thermal/partial-demand behavior into a new visual "full power" baseline.

The effective result carries explicit provenance:

- `retainedCheckpoint`, or
- `currentSession`.

That provenance is presentation/calibration state, not telemetry evidence.

## Dependency and hardware status

This branch is intentionally based on PR #214's observed-power-envelope branch. It should be reconciled after #214 reaches an accepted final contract.

**HARDWARE STATUS: NOT VERIFIED ON PHYSICAL AOVOPRO ES80.** No physical ES80 power/current field, DP, characteristic, scale, cadence, throttle signal, regen semantic, or actual full-power ceiling is claimed by this persistence work.
