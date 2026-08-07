# Ride-bound observed peak-speed evidence

Date: 2026-08-07
Worker: `chat-t6v9m`
Primary hardware-validation target: **AOVOPRO ES80**

## Product problem

`PeakSpeedEvidence` intentionally answers one narrow question: what was the highest authoritative selected-source speed measurement this accumulator accepted?

That primitive is not enough for durable ride history because it contains no ride UUID. A valid observed maximum must never be joined to a completed ride merely because both values happen to exist at the same time.

This slice adds the identity/provenance boundary before any History, Statistics, or UI integration.

## Live ride binding

`RidePeakSpeedEvidenceAccumulator` owns exactly one `PeakSpeedEvidenceAccumulator` plus one immutable ride `sessionID`.

- every accepted peak emitted by this wrapper is bound to that session;
- foreign sources and quality rejection continue to use the already-accepted peak-speed rules;
- `recordInterruption` preserves known selected-source evidence loss;
- `beginsAfterKnownObservationGap` records an initial application-lifecycle gap immediately instead of pretending the observer saw the whole ride;
- there is deliberately no reset API on the ride-bound wrapper. A new ride should create a new accumulator rather than erase the old ride's evidence-loss history.

`RidePeakSpeedEvidence` has no public free-form initializer. External callers obtain it from the ride-bound accumulator rather than pairing an arbitrary bare `PeakSpeedEvidence` with a UUID after the fact.

## Completed-ride projection

`CompletedRidePeakSpeedEvidence` is a durable projection created from:

- one immutable `CompletedRideEvidence`;
- one `RidePeakSpeedEvidence` with the same session UUID.

A session mismatch fails closed.

A completed ride marked `.recoveredCheckpoint` also proves a process interval existed outside one uninterrupted process-local observer. Therefore a recovered ride is rejected if its supplied peak evidence claims `.noRecordedSelectedSourceEvidenceLoss`. The caller must have recorded the known gap before durable projection.

## What becomes durable

The projection keeps:

- session UUID;
- completed ride continuity;
- selected authoritative source;
- observed peak meters/second;
- peak sample speed accuracy when present;
- caller-injected maximum allowed speed accuracy when one was required;
- accepted selected-source sample count;
- selected-source quality-rejection count;
- known interruption count;
- observed-peak continuity classification.

The projection deliberately does **not** persist process-local receive uptime, receive wall-clock metadata, or a fabricated peak timestamp. Uptime is useful for in-process ordering but is meaningless across process/boot recovery.

## Decode / import trust boundary

Decoded durable peak evidence is rebuilt through the same validating initializer. It rejects:

- `.motionAssist` as an authoritative completed peak source;
- negative/non-finite speed;
- a raw SI speed whose required km/h conversion is non-finite;
- negative/non-finite accuracy values;
- an accuracy ceiling with no measured peak accuracy;
- peak accuracy worse than the persisted acceptance ceiling;
- zero/negative accepted-sample count;
- negative rejection/interruption counts;
- `noRecordedSelectedSourceEvidenceLoss` paired with nonzero loss counters;
- `partialSelectedSourceEvidence` with no recorded rejection/interruption cause;
- a recovered ride claiming no recorded selected-source loss.

`validate(against:)` rechecks session identity and completed-ride continuity before a future persistence/statistics adapter joins the records.

## Important limitation: still not reportable top-speed truth by itself

This slice does **not** make a completed observed maximum automatically suitable for the Dashboard, History, or Statistics.

The separate telemetry benchmark/quality system must still establish whether the chosen physical source has sufficient cadence, jitter, latency, resolution, accuracy, and continuity for a peak-speed feature. A weakly observed numeric maximum remains weak evidence even when it is correctly bound to a ride UUID.

No physical ES80 source, cadence, accuracy threshold, packet semantic, or exact top speed is selected here.

## No persistence migration yet

`RideHistoryRecord` is intentionally unchanged. This PR does not add a new field to completed history, change SwiftData/storage, modify `CompletedRideEvidence`, alter `RideStatistics`, wire the app target, or show peak speed in UI.

The next safe integration step should first combine ride-bound observed peak evidence with a feature-specific telemetry-quality decision. Only then should a persistence migration decide how qualified peak evidence is stored and how legacy rides represent its absence.

## Verification target

Focused package tests cover ride identity binding, source isolation, initial-gap retention, recovered-ride fail-closed behavior, accuracy-policy provenance, process-clock stripping, Codable round-trip/corruption, and durable join validation.

Software tests are not physical AOVOPRO ES80 verification.
