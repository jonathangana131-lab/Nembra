# ES80 Tuya DP Electrical-Coherence Research Evidence

Status: **software research tooling only / physical ES80 semantics unverified**

Dependency chain:

`#219 public-family framing -> #238 structural DP candidates -> #262 stock-app marker correlation -> #280 explicit numeric transforms -> this layer`

## Purpose

The stock Tuya app has been observed exposing battery percentage, voltage, current/amps, and watts/power for the target AOVOPRO ES80 generation. Those visible values are useful **correlation anchors**, but they do not prove which raw Tuya DP carries any field, what its scale is, or whether Nembra has production authority for it.

`TuyaCandidateDPElectricalCoherenceEvaluator` adds one narrow research question after #280 has already produced explicit candidate/scale hypotheses:

> Do one caller-selected voltage candidate, one current candidate, and one power candidate remain mutually consistent with the explicit relationship `power = voltage × current` across repeated, time-bounded stock-app anchors?

This can prioritize which hypotheses deserve more physical capture. It is not a decoder and is not protocol confidence.

## Inputs are explicit

The caller supplies:

- one #280 numeric-hypothesis report assigned to the **voltage anchor role**;
- one report assigned to **current**;
- one report assigned to **power**;
- the exact transform identifier selected from each report;
- an explicit evidence-context identity for each role;
- explicit three-way marker-index groups;
- a maximum allowed evidence span;
- absolute and relative power-error tolerances.

There are no ES80 defaults for timing, scale, signedness, unit, or tolerance. Field-label strings are preserved but never parsed to infer meaning.

Each #280 report carries the complete validated caller numeric-reference set and the exact caller-owned numeric `absoluteTolerance` that produced its samples' `isWithinTolerance` flags. This layer retains both separately for voltage, current, and power, including references whose candidate samples were excluded by the parent. The three roles may legitimately use different numeric tolerances.

For each selected role, the child also retains the **complete source #280 report** and the **exact selected #280 evidence object**. That keeps parent unused/ambiguous/shared-reference indices, nonnumeric and transformation-failure counts, alternate hypothesis evidence, exact selected samples, and all parent timing/raw-byte provenance available from the child result. The electrical layer adds evidence; it does not compress away the evidence below it.

## Unit contract

The relationship `power = voltage × current` is evaluated only in the caller-supplied numeric spaces. The caller is responsible for supplying mutually compatible units for the intended research question, for example numeric anchors normalized to volts, amps, and watts.

The evaluator does not infer a unit from a label, DP identifier, payload width, scale, or magnitude. It does not silently convert milliamps to amps, kilowatts to watts, or any other unit system. A coherent numeric relationship is therefore evidence about the explicitly supplied hypothesis only, never proof that the raw fields physically use V/A/W.

## Capture / monotonic-clock boundary

The three reports contain monotonic receipt uptimes. Those numbers are meaningful for cross-field timing only when all three reports come from the same retained capture/analysis clock context. Equal GATT identity and continuity generation alone do not prove that two independently created captures share a comparable uptime origin.

The evaluator therefore requires caller-attested per-role `TuyaCandidateDPElectricalEvidenceContextIdentity` values and fails closed unless all three match **before** it performs timing-span math.

The identifier should come from retained capture metadata or another durable analysis-session identity. It is deliberately opaque. This layer does not invent one by hashing timestamps or GATT identity.

This binding is a provenance contract, not authentication. A caller can still supply the wrong identifier. Production research wiring should therefore feed it from Nembra's retained capture/session metadata rather than asking a user to type it manually.

All three reports must also come from the same exact:

- peripheral/service/characteristic value-stream identity;
- continuity generation;
- structural DP length-width hypothesis.

Mixing any of those boundaries fails closed.

## Why both references and candidates are checked

Each accepted anchor evaluates two relationships separately:

1. **stock-reference relationship** — independently entered numeric stock-app values must themselves be coherent enough for the chosen timing/tolerance policy;
2. **candidate relationship** — the transformed raw DP candidate values must also be coherent.

Joint support additionally requires all three #280 candidate samples to individually match their own caller-supplied numeric anchors under their retained per-report numeric tolerances.

So one accidental `V × I ≈ P` result cannot hide that a selected transform failed its original stock-app value, and asynchronous/incoherent stock-app anchors cannot silently become positive candidate evidence.

## Timing boundary

After the shared evidence context has been established, an electrical anchor is accepted only when the span across all six relevant monotonic timestamps is within caller policy:

- voltage marker receipt;
- current marker receipt;
- power marker receipt;
- voltage accepted candidate-message completion receipt;
- current accepted candidate-message completion receipt;
- power accepted candidate-message completion receipt.

This deliberately follows #262's accepted measurement clock, which pairs markers against candidate message **completion** receipt. The parent still retains first-receipt timestamps as provenance, but this layer does not silently redefine the parent's accepted sample clock.

The evaluator never repairs, interpolates, or pretends separated observations were simultaneous. A too-wide group remains an explicit rejected anchor.

## Repeated evidence boundary

One stock marker may support at most one anchor within each role in a single evaluation. Duplicate anchor tuples and per-role marker reuse fail closed so callers cannot inflate support counts by repeating the same evidence.

Missing numeric samples, excessive timing span, and non-finite relationship math are retained as explicit rejection reasons instead of being silently dropped. Because every role selection retains the entire parent report and selected evidence, a missing sample can still be audited against parent exclusions and caller references rather than collapsing into a context-free index.

## Numeric stability

Each accepted anchor must keep predicted power, absolute error, relative allowance, and relative error finite. Overflowing relationship math is rejected rather than treated as a match.

Aggregate mean absolute errors use normalized finite accumulation (`value / count` before summation) so several very large but finite per-anchor errors do not become infinite only because an intermediate raw sum overflowed. This does not increase evidence strength; it preserves truthful descriptive math.

## Signed values

The evaluator multiplies the transformed values exactly as supplied. It does not take absolute current, guess signedness, or infer regenerative braking. If a researcher wants to evaluate a negative transform, that transform must already have been explicitly supplied to #280.

A negative result is therefore still only research math. It is **not** verified regen.

## Output

The report preserves:

- exact shared evidence-context identity;
- exact shared stream/generation/framing scope;
- exact field labels;
- each role's complete source #280 numeric report;
- each role's exact selected #280 evidence object;
- each selected raw DP candidate identity;
- each selected numeric transform;
- each role's complete validated parent numeric-reference set;
- each role's exact parent numeric absolute tolerance;
- full #280 samples including raw bytes and timing provenance;
- reference-side and candidate-side predicted power/error/tolerance;
- whether each of the three numeric hypotheses matched its own stock anchor;
- explicit rejected anchors;
- descriptive repeated-support counts and finite aggregate errors.

Counts are not confidence scores and are never sufficient to promote a DP into production telemetry.

## Non-goals / truth boundary

This layer does **not**:

- decrypt Tuya traffic;
- discover DP IDs or transforms automatically;
- parse stock-app display strings into numbers;
- claim any candidate is voltage/current/power;
- infer or convert physical units;
- prove the caller supplied the correct capture-context identity;
- establish unit, scale, signedness, cadence, freshness, or source authority;
- reinterpret a parent numeric tolerance as sensor accuracy or protocol confidence;
- infer battery energy, Wh, Wh/mi, torque, throttle, or regen;
- authorize Bluetooth writes or vehicle commands;
- replace repeated physical capture and correlation.

Before Nembra may expose voltage/current/power as production truth, each field still requires repeated physical verification of raw source, framing, DP identity/type, scaling, units, signedness, cadence, continuity behavior, and provenance on the real AOVOPRO ES80.

## Suggested physical use after the capture UI is ready

A later research workflow can record a short, safe physical session in one retained Nembra capture context, place stock-app voltage/current/power markers close together, and let Nembra perform framing, structural DP parsing, marker correlation, numeric transform evaluation, and this coherence check offline.

The capture tooling should carry the evidence-context identity automatically. The user should not need to decode hex or invent session identifiers manually. This layer only narrows what Nembra should investigate next.
