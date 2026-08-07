# ES80 Tuya DP Numeric Hypothesis Evaluation

Status: **software research tooling only — not physical AOVOPRO ES80 protocol verification**.

## Position in the evidence ladder

This slice is an explicit child of PR #262 (`es80-tuya-dp-marker-correlation`), which is itself a child of PR #238 (`es80-tuya-dp-candidate-analysis`) and PR #219 (`es80-tuya-offline-framing`).

The layers remain deliberately separate:

1. #219: preserve bounded public-family framing candidates and transport provenance;
2. #238: parse caller-selected legitimate plaintext data into generic DP-shaped candidates without ES80 semantics;
3. #262: inside one exact stream / continuity generation / DP framing hypothesis, pair repeated stock-app markers with nearest DP candidate occurrences and preserve timing/ambiguity/equality evidence;
4. **this slice**: only after #262 has produced an unambiguous hit for a marker, compare the retained raw scalar bytes against an explicitly supplied numeric reference under explicitly supplied transform hypotheses.

This child does not compete with #262's temporal correlation. It consumes that result and adds only the next numeric-analysis step.

## Why a separate layer

A stock app may display values such as `73%`, `41.3 V`, `2.1 A`, or `480 W`. Seeing those strings is useful correlation evidence, but parsing them inside core protocol tooling would silently introduce assumptions about locale, suffixes, decimal punctuation, engineering units, and formatting.

`TuyaCandidateDPNumericReference` therefore contains only:

- the exact #262 `markerIndex`;
- one caller-supplied finite `Double` value.

The evaluator never derives the number from `displayedReference`. The exact stock-app string remains provenance on #262's accepted hit and is copied into the resulting sample unchanged.

## Explicit transform hypotheses only

A hypothesis is exactly:

`displayCandidate = rawUnsignedMagnitude * scale + offset`

`TuyaCandidateDPNumericTransformHypothesis` requires:

- a non-empty caller-owned identifier;
- a finite, non-zero scale;
- a finite offset.

There is intentionally no default:

- battery identity mapping;
- voltage `/10` mapping;
- current scale;
- power scale;
- signedness rule;
- engineering unit;
- tolerance;
- arbitrary transform search.

For example, testing whether raw `413` is consistent with a human reference `41.3` requires the caller to explicitly submit a `scale = 0.1` hypothesis. The raw `413` remains in the evidence beside the transformed `41.3`; the transform never replaces the source evidence.

## Parent evidence remains authoritative

The evaluator accepts the complete `TuyaCandidateDPMarkerCorrelationReport` from #262 plus one exact candidate index.

It therefore inherits rather than re-creates #262's boundaries:

- one exact GATT value stream;
- one exact continuity generation;
- one explicit DP length-width hypothesis;
- strict observation/marker chronology;
- message-completion receipt timing;
- at most one unambiguous support hit per candidate per marker;
- explicit equal-distance raw-value ambiguity;
- exact displayed-reference preservation;
- structural separation of same DP ID across raw type / declared length.

A numeric reference pointing at a #262 ambiguous marker is reported as ambiguous and never becomes a sample. A numeric reference for a marker where the chosen candidate has no hit is reported as unused. Neither condition is silently repaired.

## Scalar projection

The raw bytes retained by #262 are projected to an unsigned big-endian magnitude only for the same conservative public-family scalar shapes already permitted by #238:

- boolean: exactly one byte and only `0` or `1`;
- value: exactly `1`, `2`, or `4` bytes;
- enumeration: exactly one byte;
- bitmap: exactly `1`, `2`, or `4` bytes.

Raw, string, unknown, malformed boolean, malformed length, or raw-length/declared-length mismatch remains nonnumeric evidence.

Unsigned magnitude is not a signedness claim, scale claim, unit claim, field-meaning claim, or ES80 protocol claim.

## Result evidence

Each evaluable sample preserves:

- #262 marker index;
- exact stock-app displayed reference string;
- caller-supplied numeric reference;
- observation index;
- first and last message receipt uptime;
- temporal distance and before/same/after relation;
- exact raw DP value bytes;
- raw unsigned magnitude;
- caller-supplied transform result;
- absolute display-space error;
- whether that error is within the caller's explicit tolerance.

Per-hypothesis summaries expose only descriptive counts and error statistics. They are not protocol confidence scores.

Deterministic ranking favors:

1. more evaluable markers within caller tolerance;
2. more distinct evaluable numeric reference values;
3. more evaluable references;
4. lower mean absolute display-space error;
5. stable hypothesis identifier ordering.

Ranking helps decide what physical hypothesis to test next. It never converts a candidate into verified Battery, Voltage, Current, Power, or another production field.

## Fail-closed input rules

The evaluator rejects:

- candidate index outside the exact parent report;
- negative or out-of-report marker indices;
- duplicate numeric references for one marker;
- non-finite numeric references;
- blank hypothesis identifiers;
- zero/non-finite scales;
- non-finite offsets;
- invalid or exceeded caller resource bounds;
- negative/non-finite tolerances.

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
- rated/maximum motor/controller power;
- writable capability or command acknowledgement.

This slice performs no Bluetooth writes, command encoding, authentication, key handling, decryption, or motorized action.

No result is production telemetry authority. Production read-only fields still require repeatable physical ES80 evidence for raw source, exact identity, scaling, units, signedness, cadence, continuity, freshness, and failure behavior.

## Focused regressions

The test suite covers:

- explicit `/10` transform matching while retaining raw `413/412` bytes and magnitudes;
- proof that display strings do not create numeric references;
- raw/string candidate non-coercion;
- malformed boolean non-coercion;
- explicit unused numeric references when the candidate has no hit;
- preservation of parent temporal ambiguity;
- preservation of first/last receipt timing, temporal distance, and direction;
- duplicate/out-of-range marker reference rejection;
- invalid candidate rejection;
- non-finite input and zero-scale rejection;
- explicit resource ceilings.

Repository-native exact-head NembraCore/Xcode validation is required before this child can be accepted. Parent #262 must be accepted first; if its head moves, reconcile this child and rerun exact-head validation.

## Physical next step

Once physical ES80 capture can legitimately reach #262's exact-stream temporal report, Nembra tooling can collect a short set of stock-app numeric observations for one field and submit a small set of evidence-driven transform hypotheses automatically. The user should not be asked to decode hex manually.

Only repeated physical results that survive the complete upstream source/identity/framing/plaintext/DP/timing boundary plus numeric scale/unit/signedness/cadence validation may move toward production read-only telemetry.
