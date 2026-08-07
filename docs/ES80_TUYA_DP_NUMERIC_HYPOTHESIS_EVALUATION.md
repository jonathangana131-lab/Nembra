# ES80 Tuya DP Numeric Hypothesis Evaluation

Status: **software research tooling only — not physical AOVOPRO ES80 protocol verification**.

## Position in the evidence ladder

This slice is an explicit child of PR #262 (`es80-tuya-dp-marker-correlation`), itself dependent on PR #238 (`es80-tuya-dp-candidate-analysis`) and PR #219 (`es80-tuya-offline-framing`).

The layers remain deliberately separate:

1. #219 preserves bounded public-family framing candidates and transport provenance.
2. #238 parses caller-selected legitimate plaintext data into generic DP-shaped candidates without ES80 semantics.
3. #262, inside one exact stream / continuity generation / DP framing hypothesis, pairs repeated stock-app markers with nearest DP candidate occurrences while preserving timing, ambiguity, equality, and independent-observation evidence.
4. **This slice** only after #262 resolves an independent unambiguous hit, compares retained raw scalar bytes against an explicitly supplied numeric reference under explicitly supplied transform hypotheses.

This child does not compete with #262's temporal correlation. It consumes that report and adds only the next numeric-analysis step.

## Numeric input boundary

A stock app may display values such as `73%`, `41.3 V`, `2.1 A`, or `480 W`. Those strings are useful correlation evidence, but parsing them inside protocol core would silently introduce assumptions about locale, suffixes, decimal punctuation, engineering units, and formatting.

`TuyaCandidateDPNumericReference` therefore contains only:

- the exact #262 `markerIndex`;
- one caller-supplied finite `Double` value.

The evaluator never derives a number from `displayedReference`. The exact stock-app text remains provenance on #262's accepted hit and is copied into the resulting sample unchanged.

## Explicit transform hypotheses only

A hypothesis is exactly:

`displayCandidate = rawUnsignedMagnitude * scale + offset`

`TuyaCandidateDPNumericTransformHypothesis` requires a non-empty caller-owned identifier, a finite non-zero scale, and a finite offset.

There is intentionally no default:

- battery identity mapping;
- voltage `/10` mapping;
- current scale;
- power scale;
- signedness rule;
- engineering unit;
- tolerance;
- arbitrary transform search.

For example, testing whether raw `413` is consistent with independently entered numeric reference `41.3` requires the caller to explicitly submit `scale = 0.1`. Raw `413` remains in every sample beside transformed `41.3`; transformation never replaces evidence.

## Parent evidence remains authoritative

The evaluator accepts the complete `TuyaCandidateDPMarkerCorrelationReport` plus one exact candidate index. It therefore inherits rather than re-creates the parent boundaries:

- one exact GATT value stream;
- one exact continuity generation;
- one explicit DP length-width hypothesis;
- strict observation and marker chronology;
- message-completion receipt timing;
- at most one candidate hit per marker;
- at most one human marker supported by one physical candidate message;
- explicit equal-distance conflicting-raw ambiguity;
- explicit shared-observation rejection;
- exact displayed-reference preservation;
- structural separation of the same DP ID across raw type / declared length.

A numeric reference pointing at an ambiguous parent marker is reported as ambiguous and never becomes a sample. A numeric reference rejected because it would reuse another marker's physical observation is reported separately as `sharedObservationReferenceMarkerIndices` and never becomes a sample. A numeric reference for a marker where the chosen candidate simply has no hit is reported as unused. These states are not collapsed or silently repaired.

## Scalar projection

The raw bytes retained by #262 are projected to an unsigned big-endian magnitude only for the same conservative public-family scalar shapes permitted by #238:

- boolean: exactly one byte and only `0` or `1`;
- value: exactly `1`, `2`, or `4` bytes;
- enumeration: exactly one byte;
- bitmap: exactly `1`, `2`, or `4` bytes.

Raw, string, unknown, malformed boolean, malformed length, or raw-length/declared-length mismatch remains nonnumeric evidence.

Unsigned magnitude is not a signedness claim, scale claim, unit claim, field-meaning claim, or ES80 protocol claim.

## Result evidence

Each evaluable sample preserves:

- #262 marker index;
- exact marker receipt uptime;
- exact stock-app displayed reference string;
- caller-supplied numeric reference;
- observation index;
- first and last message receipt uptime;
- temporal distance and before/same/after relation;
- exact DP header/value/end byte offsets;
- exact raw DP value bytes;
- raw unsigned magnitude;
- caller-supplied transform result;
- absolute display-space error;
- whether that error is inside caller-supplied tolerance.

Per-hypothesis summaries expose descriptive counts and error statistics only. They are not protocol confidence scores.

Deterministic ranking favors more in-tolerance support, broader distinct numeric-reference variation, greater evaluable coverage, lower mean absolute display-space error, then stable hypothesis identifier ordering. Ranking only helps decide what hypothesis to test next.

## Fail-closed input rules

The evaluator rejects:

- candidate index outside the exact parent report;
- negative or out-of-report marker indices;
- duplicate numeric references for one marker;
- non-finite numeric references;
- blank hypothesis identifiers;
- zero or non-finite scales;
- non-finite offsets;
- invalid or exceeded caller resource bounds;
- negative or non-finite tolerance.

## Truth and safety boundary

A perfect numeric match still does **not** establish:

- that the physical AOVOPRO ES80 uses this public Tuya framing family;
- physical GATT identity;
- plaintext provenance, decryption/authentication correctness, or key material;
- DP field meaning;
- signedness;
- decimal scale;
- engineering unit;
- cadence or freshness;
- direct 1% battery resolution;
- voltage/current/watts semantics;
- throttle position;
- regenerative braking;
- rated/maximum motor or controller power;
- writable capability or command acknowledgement.

This slice performs no Bluetooth writes, command encoding, authentication, key handling, decryption, or motorized action.

No result is production telemetry authority. Production read-only fields still require repeatable physical ES80 evidence for raw source, exact identity, scaling, units, signedness, cadence, continuity, freshness, and failure behavior.

## Focused regression intent

The child suite covers:

- explicit `/10` matching while retaining raw `413/412` bytes and magnitudes;
- proof that display text never creates numeric references;
- raw/non-scalar and malformed-boolean non-coercion;
- explicit unused references where the candidate has no hit;
- preservation of parent conflicting-nearest ambiguity;
- preservation of parent shared-observation rejection;
- preservation of exact marker receipt, first/last observation receipt, temporal distance/direction, and DP byte offsets;
- duplicate and out-of-range marker reference rejection;
- invalid candidate rejection;
- non-finite input and zero-scale rejection;
- caller-owned resource ceilings.

Repository-native exact-head NembraCore/Xcode validation is required before this child can be accepted. PR #262 must be accepted first; if its head moves, this child must be reconciled and re-gated.

## Physical next step

Once physical ES80 capture legitimately reaches #262's exact-stream temporal report, Nembra tooling can collect a short set of stock-app numeric observations for one field and submit a small set of evidence-driven transform hypotheses automatically. The user should not be asked to decode hex manually.

Only repeated physical results that survive the complete upstream source / identity / framing / plaintext / DP / timing / independent-observation boundary plus numeric scale / unit / signedness / cadence validation may move toward production read-only telemetry.
