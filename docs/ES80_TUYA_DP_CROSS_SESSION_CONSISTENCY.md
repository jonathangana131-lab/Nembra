# ES80 Tuya DP Cross-Session Consistency

## Purpose

This slice sits above the dependent ES80 Tuya research chain:

1. public-family framing candidate analysis (#219);
2. generic DP structural parsing (#238);
3. stock-app marker to opaque DP correlation (#262);
4. caller-supplied numeric transform evaluation (#280, successor to superseded #270);
5. **this layer: descriptive consistency across independently labelled capture sessions**.

The goal is narrow but important: one unusually convenient capture session must not silently become protocol truth. When the same exact GATT stream, DP structural candidate, field label, framing-width hypothesis, numeric transform, and numeric comparison tolerance are evaluated in multiple sessions, Nembra can preserve repeated evidence together and make contradictions impossible to hide.

This is research prioritization only. It does not verify an AOVOPRO ES80 field.

## What the analyzer accepts

`TuyaCandidateDPCrossSessionConsistencyAnalyzer` consumes:

- a caller-supplied research `subjectIdentifier`;
- **at least two** `TuyaCandidateDPCrossSessionObservation` values, each containing a unique caller-labelled session identifier and a complete #280 numeric-hypothesis report;
- one exact caller-supplied `TuyaCandidateDPNumericTransformHypothesis`;
- a caller-owned maximum-session resource bound that must itself allow at least two sessions.

Empty input returns no report. A single non-empty session fails closed with `insufficientSessionCount(minimum: 2)`. A policy configured with a maximum below two fails construction, so an impossible cross-session configuration cannot survive as latent state.

Subject and session labels are whitespace-normalized bookkeeping evidence. They do **not** prove a unique process launch, ride, physical scooter, or independent physical experiment. They must be non-secret labels; raw Tuya keys, credentials, tokens, or other sensitive transport material must never be used as these identifiers.

The analyzer requires exact agreement on:

- field label;
- `TuyaCandidateValueStreamIdentity` (peripheral/service/characteristic strings);
- DP data-length-width hypothesis;
- DP structural candidate (ID, raw type, known-type projection, declared value length);
- numeric transform (identifier, scale, offset);
- caller-owned `absoluteTolerance` retained by #280.

Continuity generation may differ. That difference is retained per session rather than normalized away. It is provenance, not proof of independence: changing only the generation label while leaving the retained marker/message/reference evidence identical does not create a second session for this analyzer.

## Complete numeric-reference provenance

#280 retains the complete validated numeric-reference set in canonical marker-index order. #276 carries that set into every session record instead of preserving only a count plus the subset that happened to become samples.

That distinction matters for rejected evidence. A caller-supplied value can remain legitimate experiment input even when its marker is later:

- unused because the selected candidate had no independent hit;
- ambiguous because equally-near conflicting raw observations exist;
- rejected because another marker already consumed the same physical observation.

Those reference values remain beside their exclusion indices. They are not reconstructed from display text and they do not vanish because no sample was produced.

`distinctNumericReferenceValueCount` is computed across these complete retained reference sets, not only successful samples. The count remains descriptive variation evidence only; it is not protocol confidence.

## Why tolerance equality matters

#280 retains the exact `absoluteTolerance` used to compute each sample's `isWithinTolerance`. That closes an important provenance gap: a tolerance result is auditable after the caller policy leaves scope.

This child therefore requires every session report to carry **the exact same tolerance value**. A different tolerance fails with `absoluteToleranceMismatch(index:)` before any cross-session summary is produced.

Only after that equality is proven does the report expose descriptive in-tolerance counts:

- sessions with at least one evaluable in-tolerance sample;
- sessions whose complete evaluable sample set is in tolerance;
- total in-tolerance samples.

These counts describe the exact caller-supplied experiment policy only. The tolerance is not protocol resolution, sensor accuracy, engineering-unit certainty, field identity, or confidence.

## Fail-closed behavior

The analyzer rejects:

- empty subject or session labels;
- only one non-empty session;
- a maximum-session policy below the two-session invariant;
- more sessions than the caller-owned resource limit;
- duplicate normalized session labels;
- reuse of the same selected underlying #280 evidence under a second session label;
- reuse of otherwise-identical retained evidence with only continuity generation relabelled;
- mixed field labels;
- mixed GATT streams;
- mixed DP framing-width hypotheses;
- mixed DP structural candidates;
- mixed absolute comparison tolerances;
- a selected transform missing from any session;
- an exact selected transform appearing more than once inside one session report.

Underlying-evidence reuse is stricter than whole-report equality. A caller cannot take one physical evidence set, rebuild the outer #280 report with extra unrelated hypotheses, a changed candidate ranking index, or only a changed continuity-generation label and have this layer count it as another session. The exact stream/field/framing scope excluding generation, parent numeric-reference set, tolerance, marker exclusion sets, selected hypothesis evidence, raw bytes, and timing remain part of the retained evidence identity.

This still cannot prove that two genuinely different reports came from physically independent experiments. Physical/session independence remains caller-supplied provenance until Nembra has stronger capture identity and physical evidence.

## What the report preserves

For every session, the report retains:

- normalized session label;
- continuity generation;
- original candidate index;
- numeric reference count;
- complete canonical numeric-reference set, including values for excluded markers;
- unused numeric-reference marker indices;
- temporally ambiguous marker indices;
- shared-observation marker indices rejected by the parent;
- distinct evaluable reference-value count;
- complete #280 samples including raw bytes, raw unsigned magnitude, marker/message timing, DP byte offsets, transformed candidate value, absolute error, and parent tolerance result;
- mean and maximum absolute error.

At the cross-session level it retains the exact common `absoluteTolerance` plus only descriptive totals:

- number of sessions;
- sessions with any evaluable evidence;
- sessions with at least one in-tolerance sample;
- sessions whose complete evaluable sample set is in tolerance;
- total evaluable samples;
- total in-tolerance samples;
- distinct caller numeric reference values across complete retained reference sets.

There is intentionally no `verified`, `confidence`, `probability`, `fieldMeaning`, stable-identity claim, or production-authority flag.

## Contradictions are product evidence

If one session produces transformed values close to an explicit `/10` reference and another session produces large display-space error under the same tolerance, both survive in the aggregate. The analyzer never averages the contradiction into a stronger-looking protocol score and never drops the weaker session merely because another session matched better.

The regression suite includes a matching session and a contradictory session under one exact tolerance. The resulting report shows both sessions as evaluable, only one session with in-tolerance support, and preserves the large absolute errors in the contradictory session.

A separate regression changes only the parent tolerance between two reports and proves that the pair fails before aggregation. Policy drift cannot masquerade as physical repeatability.

Another regression changes only continuity generation while keeping the same marker time, observation time, raw bytes, reference, transform, tolerance, and selected evidence. The analyzer rejects that pair as reused evidence. Continuity epochs remain valuable provenance, but a label change cannot manufacture physical independence.

Likewise, a session with no evaluable evidence remains present. Missing evidence is not converted into a match or failure.

## Adversarial coverage

The focused tests exercise:

- two sessions with separate continuity generations while retaining raw/timing provenance;
- exact common tolerance retention and descriptive support counts;
- contradictory evidence under one exact tolerance;
- mixed-tolerance rejection;
- duplicate normalized session labels;
- exact report reuse;
- repackaging the same selected evidence inside a different outer #280 report;
- continuity-generation-only relabelling of otherwise identical evidence;
- single-session rejection;
- invalid maximum-session policy below the two-session invariant;
- mixed GATT streams;
- mixed DP structural candidates;
- exact field-label isolation;
- missing and duplicate selected hypotheses;
- empty-input behavior and caller-owned resource ceilings;
- retention of an unused caller numeric value in cross-session reference variation even though it never becomes a numeric sample.

## Physical truth boundary

This implementation is **software research tooling only**.

It does not establish:

- that a physical AOVOPRO ES80 uses the candidate Tuya framing family;
- that a particular GATT service/characteristic is an ES80 telemetry transport;
- that any DP ID means battery, voltage, current, power, speed, mode, ODO, trip, throttle, or regen;
- scale, signedness, engineering units, cadence, freshness, or derivation semantics;
- stable physical scooter identity;
- physical independence merely because session labels or continuity generations differ;
- command authorization or acknowledgement;
- production read-only telemetry authority.

No Bluetooth write path, credentials, decryption, command encoding, or motorized behavior is added.

## Minimal next physical experiment this layer is designed to consume

Once the dependent Research Capture + DP-analysis chain can produce legitimate #280 reports from the real selected ES80, collect **two separately started short passive capture sessions** against the same deliberately selected scooter and exact GATT value stream. In each session, use the existing marker workflow to capture repeated observations of one stock-app field over at least two distinct displayed numeric values, then run the same explicit numeric transform and the same explicit tolerance offline.

Expected evidence for this layer is two separately labelled #280 reports with:

- the same exact stream identity;
- the same structural DP candidate;
- the same field label and framing-width hypothesis;
- the same explicit numeric transform;
- the same explicit comparison tolerance;
- complete caller numeric-reference provenance;
- independently retained raw/timing provenance;
- visible agreement or contradiction in raw/transformed/error evidence.

The user should not manually decode hex. Offline Nembra tooling should perform the candidate comparison. If physical capture cannot yet produce those reports safely, that remains a dependency blocker rather than permission to invent data.

## Integration dependency

This slice is intentionally based on PR #280, which depends on #262 -> #238 -> merged #219. It must not merge independently ahead of that parent chain. If a parent changes materially, rebase/reconcile this slice and rerun exact-head NembraCore/Xcode validation.