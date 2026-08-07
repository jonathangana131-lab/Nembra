# ES80 Tuya DP Marker Correlation

Status: **software research tooling only — not physical AOVOPRO ES80 protocol verification**.

## Purpose

This slice sits above the generic public-family DP candidate parser in PR #238 and below any future production telemetry mapping.

It answers one narrow offline research question:

> Given repeated human-observed stock-app numeric references and already-parsed DP-shaped candidate payloads from one exact opaque source stream, which exact DP structural keys remain numerically consistent under an **explicit caller-supplied transform hypothesis**?

The analyzer is a prioritization aid. It does not name a DP as Battery, Voltage, Current, Power, or any other ES80 field.

## Dependency

This lane is an explicit dependent child of PR #238 (`es80-tuya-dp-candidate-analysis`), which is itself dependent on PR #219's public-family framing analysis.

A successful result here therefore inherits all of those upstream candidate boundaries. A public-family framing/CRC/DP-shaped parse is still not proof that the physical ES80 uses that family.

## Input boundary

`TuyaCandidateDPMarkerSnapshot` preserves:

- exact human marker sequence identity;
- original marker field and displayed string;
- an explicitly supplied finite numeric reference value;
- exact candidate sequence identity supplied by the upstream research bridge;
- one opaque exact source-stream identity;
- continuity generation;
- the already-parsed `TuyaCandidateDPPayload`.

The core analyzer deliberately does **not** parse strings such as `73%`, `41.3 V`, `2.1 A`, or `480 W` into numeric values. Research tooling must supply the numeric reference separately so locale, suffix, decimal, and unit assumptions do not silently become protocol semantics.

Upstream passive-capture/correlation tooling may eventually construct these snapshots from exact immutable capture evidence. This NembraCore type itself is not proof that a caller-supplied stream identity or marker/candidate pairing came from physical capture.

## Explicit transform hypotheses only

A hypothesis is exactly:

`displayCandidate = rawUnsignedMagnitude * scale + offset`

The caller names the hypothesis and supplies finite non-zero `scale` plus finite `offset`.

There is intentionally:

- no default `0.1` voltage scale;
- no default battery-percent identity assumption;
- no guessed current/power scale;
- no automatic signedness interpretation;
- no arbitrary transform search;
- no automatic unit inference;
- no production tolerance default.

The raw unsigned magnitude remains present beside every transformed comparison. The transformed `Double` is descriptive display-space research math only; it never replaces the raw evidence and is not telemetry persistence or a physical measurement.

## Fail-closed correlation rules

For one requested marker field, the selected snapshots must retain:

1. unique marker sequence identities;
2. unique `(continuity generation, candidate sequence)` identities, so one callback cannot be reused as repeated independent evidence;
3. one exact source-stream identity;
4. one fixed DP length-width hypothesis for the entire report.

The analyzer never switches one-byte vs two-byte DP framing per marker just because one interpretation fits better.

Candidate identity is structural:

- DP framing width;
- DP identifier;
- raw type byte;
- declared value length.

Only public-family scalar-shaped candidates (`bool`, `value`, `enum`, `bitmap`) are numerically evaluated. Raw/string/unknown types remain outside scalar projection.

For every marker/key pair:

- no matching candidate stays missing;
- exactly one structurally matching candidate may be evaluated;
- multiple same-key candidates in one marker are counted as ambiguous and none is cherry-picked;
- malformed/non-projectable scalar bytes stay nonnumeric;
- non-finite transform/error math is counted as transformation failure;
- raw magnitude, marker/candidate sequence identity, and continuity generation remain visible for every evaluable comparison.

A marker contributes at most once to one key/hypothesis result, and one exact callback cannot be reused to manufacture support from multiple markers in the same field report.

## Ranking

Ranking is deterministic research convenience only. It prefers, in order:

1. more marker comparisons within the caller's explicit absolute tolerance;
2. more distinct evaluable human reference values;
3. more evaluable markers;
4. lower mean absolute display-space error;
5. deterministic structural key and hypothesis ordering.

This is **not a protocol confidence score** and does not promote a candidate into verified semantics.

## Continuity

Known continuity generations are preserved in both the report and individual samples. This layer may compare repeated marker observations that span more than one explicitly represented generation, but it does not erase or bridge missing transport evidence and it does not infer packet cadence from the marker snapshots.

The upstream bridge remains responsible for never fabricating marker/candidate pairings across a known evidence gap.

## Relationship to passive stock-app correlation

PR #241 ranks exact GATT value streams by repeated temporal proximity to stock-app markers without decoding payload bytes. This DP correlation slice is deliberately independent of that capture package and does not create a package dependency cycle.

A later integration bridge may combine the two only after it can preserve exact capture provenance:

1. passive capture identifies one exact candidate stream/callback near a marker;
2. offline framing analysis preserves exact bytes and transport provenance;
3. legitimate plaintext logical data, if available, is parsed under one explicit DP framing hypothesis;
4. the bridge constructs a marker snapshot without changing marker/candidate identity;
5. this analyzer compares repeated raw scalar candidates under explicit hypotheses.

Failure at any upstream step is evidence; tooling must not mutate bytes, switch streams, cross continuity gaps, reuse one callback as multiple independent observations, or try alternate interpretations until something numerically matches.

## Truth and safety boundary

A high-ranking result does **not** establish:

- that the physical AOVOPRO ES80 uses the candidate Tuya framing family;
- a physical GATT service/characteristic or notification source;
- DP field meaning;
- signedness;
- decimal scale;
- engineering unit;
- cadence or freshness;
- 1% battery resolution;
- voltage/current/watts semantics;
- throttle position;
- regen;
- rated/maximum motor or controller power;
- command acknowledgement or writable capability.

This slice performs no CoreBluetooth writes, command encoding, authentication, key handling, decryption, or motorized action.

No output from this analyzer is production telemetry authority. Production read-only integration requires repeatable physical ES80 evidence for raw source, identity, scaling, units, signedness, cadence, continuity, and freshness.

## Verification

An isolated Swift 6.2.1 mirror of the exact split implementation passes with warnings-as-errors:

- debug: **12/12 tests green across 2 suites**;
- optimized release: **12/12 tests green across 2 suites**.

Focused coverage includes repeated exact-value matching, explicit caller-supplied decimal scaling, raw-magnitude preservation, continuity-generation retention, ambiguous duplicate candidates, malformed scalar projection, missing candidate coverage, mixed-source rejection, mixed-framing rejection, duplicate-marker rejection, reused-candidate-callback rejection, finite-input/resource-policy validation, and no-match field isolation.

This is supporting software evidence only. Repository-native NembraCore/Xcode validation on the final dependency composition is still required before integration.

## Physical next step

Do not ask the user to decode hex manually.

Once the passive-capture lineage can produce immutable physical ES80 candidate callbacks with exact stream identity and continuity, and the upstream Tuya family/DP parsing prerequisites are legitimately satisfied, Nembra tooling should automatically build short repeated marker snapshots for one stock-app field at a time. Compare explicit, evidence-driven transform hypotheses while preserving raw magnitudes and failed candidates.

Only repeated physical correlations that survive source/identity/scale/unit/signedness/cadence validation may move upward toward a verified read-only vehicle field.
