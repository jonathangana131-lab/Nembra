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
- that initial-gap fact is retained separately as `beganAfterKnownObservationGap`, so a later disconnect or unrelated quality rejection cannot masquerade as proof that recovery started after an unobserved interval;
- there is deliberately no reset API, and accumulator construction is package-scoped until a trusted ride-lifecycle adapter can mechanically guarantee one observer lifetime per immutable ride identity. A caller-chosen UUID alone is not authority to restart observation and erase prior evidence-loss history.

`RidePeakSpeedEvidence` has no public free-form initializer. The ride-bound accumulator is also package-constructed: trusted NembraCore lifecycle adapters may create it, while ordinary external clients cannot start or restart arbitrary same-UUID observers. External clients may consume evidence that a trusted production path later emits; they cannot manufacture a fresh observation lifetime themselves.

## Completed-ride projection

`CompletedRidePeakSpeedEvidence` is a durable projection created from:

- one immutable `CompletedRideEvidence`;
- one `RidePeakSpeedEvidence` with the same session UUID.

A session mismatch fails closed.

A completed ride marked `.recoveredCheckpoint` proves this observer necessarily began after a process interval it could not observe. Recovery therefore requires all of the following:

- `beganAfterKnownObservationGap == true`;
- at least one explicit interruption recorded in the underlying peak evidence;
- `.partialSelectedSourceEvidence` continuity.

A GPS-quality rejection by itself is not enough. A later vehicle disconnect is also not enough if the observer did not declare that it began after the recovery gap. The specific initial-gap provenance is preserved separately so generic later evidence loss cannot satisfy the recovery invariant accidentally.

## What becomes durable

The projection keeps:

- session UUID;
- completed ride continuity;
- whether this observer began after a known observation gap;
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
- `noRecordedSelectedSourceEvidenceLoss` paired with nonzero loss counters or an initial-gap claim;
- `partialSelectedSourceEvidence` with no recorded rejection/interruption cause;
- initial-gap provenance with no interruption evidence;
- a recovered ride without explicit initial-gap provenance, partial continuity, and an interruption.

`validate(against:)` rechecks session identity and completed-ride continuity before a future persistence/statistics adapter joins the records.

## Important limitation: still not reportable top-speed truth by itself

This slice does **not** make a completed observed maximum automatically suitable for the Dashboard, History, or Statistics.

The separate telemetry benchmark/quality system must still establish whether the chosen physical source has sufficient cadence, jitter, latency, resolution, accuracy, and continuity for a peak-speed feature. A weakly observed numeric maximum remains weak evidence even when it is correctly bound to a ride UUID.

No physical ES80 source, cadence, accuracy threshold, packet semantic, or exact top speed is selected here.

## No persistence migration yet

`RideHistoryRecord` is intentionally unchanged. This PR does not add a new field to completed history, change SwiftData/storage, modify `CompletedRideEvidence`, alter `RideStatistics`, wire the app target, or show peak speed in UI.

The next safe integration step should first combine ride-bound observed peak evidence with a feature-specific telemetry-quality decision. Only then should a persistence migration decide how qualified peak evidence is stored and how legacy rides represent its absence.

## Verification target

Focused package tests cover ride identity binding, source isolation, initial-gap provenance, recovery-vs-later-loss distinction, quality-rejection-vs-recovery distinction, accuracy-policy provenance, process-clock stripping, derived-speed overflow rejection, count/continuity corruption, Codable round-trip, and durable join validation.

A local Swift 6.2.1 warnings-as-errors harness compiles the production binding/projection in debug and release and exercises source isolation, round-trip, recovered initial-gap acceptance, gap-free recovery rejection, and quality-only recovery rejection. Swift Testing adversarial fixtures also compile/run against the same focused harness. Repository exact-head package QA remains the final integration proof for this branch.

Software tests are not physical AOVOPRO ES80 verification.
