# ES80 Tuya DP Marker Correlation

Research/implementation checkpoint: **2026-08-07**

Dependencies:

- PR #219 `[es80-tuya-offline] Add bounded public-family framing analysis`;
- PR #238 `[es80-tuya-dp] Parse generic DP candidates without inventing ES80 semantics`.

## Purpose

This slice moves the candidate-analysis path one rung above a caller-bound structural Tuya DP parse. It compares repeated **opaque raw DP values** with human-observed stock-app reference markers so Nembra can prioritize which candidate deserves the next physical investigation.

It is not a decoder and it does not assign an AOVOPRO ES80 field meaning.

A report whose caller label is `Battery` means only:

> the caller asked Nembra to compare these raw DP candidates with markers labeled Battery.

It does **not** mean:

> Nembra proved that the top-ranked DP is battery percentage.

The same boundary applies to Voltage, Current/Amps, Power/Watts, or any other human label.

## Input truth chain

The intended research chain is:

raw GATT value evidence
-> exact stream identity + continuity generation
-> #219 candidate fragment reconstruction
-> legitimate caller-supplied plaintext
-> CRC-validated candidate logical packet
-> #238 explicit DP-length-width parse
-> caller binding back to the exact reassembled-message provenance
-> this marker correlation

`TuyaCandidateDPMessageObservation` makes the caller binding explicit. This layer does not decrypt or authenticate, so it cannot independently prove that caller-supplied plaintext came from the encrypted message. It preserves #219's exact stream identity, continuity generation, first receipt, and accepted completion receipt so that limitation is not erased by a convenient correlation API.

## Hard scope boundaries

Every correlation pass is bound to exactly one:

- GATT value-stream identity;
- byte-continuity generation;
- explicit DP length-width hypothesis (`oneByte` or `twoByteBigEndian`);
- caller-supplied human field label.

Mixed stream, continuity-generation, or length-width evidence fails closed.

The analyzer also refuses to repair chronology. Message receipt intervals must be strictly ordered and non-overlapping; markers must be strictly monotonic. Known gaps or ambiguous ordering are not sorted away to manufacture cleaner evidence.

This complements PR #241's raw-GATT repeated-marker prioritization. #241 can help identify which characteristic stream repeatedly appears near stock-app markers. This slice then operates **inside one already-selected exact stream** to compare DP-shaped records. It does not duplicate or replace the raw capture/stream-ranking layer.

## Timing truth

A parsed DP value does not exist as accepted complete-message evidence at the first fragment receipt. It only becomes a complete candidate when #219 accepts the final fragment.

Therefore marker proximity is measured against:

`TuyaCandidateReassembledMessage.lastReceiptUptimeNanoseconds`

—not against the whole first-to-last fragment interval and not against an invented midpoint.

The full first/last receipt interval is still preserved in every marker hit as provenance. Each hit also records whether the accepted message completion occurred:

- before the human marker;
- at the same receipt time;
- after the human marker.

This prevents a marker that occurs between fragments from being treated as distance zero to a DP value that was only completed later. A symmetric caller-owned time window can still consider nearby before/after evidence, but the direction is retained rather than hidden.

## One message cannot manufacture repeated evidence

Repeated human markers must not all claim the same physical candidate message. Otherwise a single DP observation near several closely spaced markers could masquerade as repeated protocol evidence.

For each structural DP candidate, marker matching therefore has two bounded stages:

1. each marker proposes its nearest accepted message-completion observation inside policy;
2. proposals that point to the same physical message are reconciled before support is counted.

One candidate message can support **at most one** human marker.

If several markers compete for the same message:

- a uniquely closer marker may consume that observation;
- the other markers are recorded in `sharedObservationMarkerIndices` and do not count as support;
- if the closest distance itself is tied, none of the competing markers receives a hit and all are recorded as shared-observation ambiguity.

This is deliberately conservative. More human annotations cannot create more physical evidence than the capture actually contains.

The rule is per structural candidate, not global across all DPs in a packet. One Tuya packet may legitimately contain several different DP records, so distinct candidate IDs/types may each be evaluated against the same human marker while remaining separate hypotheses.

## What is compared

Candidate structural identity is:

- DP identifier;
- raw type byte;
- declared value length.

Same numeric DP ID is therefore not silently merged across a different raw type or width. The report scope separately preserves the selected DP framing width.

For every candidate and human marker, the analyzer finds the nearest accepted **message-completion receipt** inside the caller's time-distance policy.

A marker contributes at most **one** support hit to a candidate, no matter how many callbacks occurred nearby. This prevents a high-rate unrelated DP from winning merely because it generated more packets.

If two equally-near occurrences of the same structural candidate disagree in raw value bytes, that marker is recorded in `ambiguousNearestMarkerIndices` and contributes no chosen hit. Nembra does not select whichever raw value looks more compatible with the desired field.

If equally-near occurrences carry the same raw bytes, one deterministic earliest occurrence becomes that marker's proposal; the one-message-one-marker reconciliation above still applies before it becomes accepted support.

## Equality-pattern evidence

The analyzer intentionally compares only exact strings and exact bytes.

For accepted marker hits it records:

- marker support count;
- conflicting-nearest marker indices;
- shared-observation marker indices;
- distinct displayed-reference count;
- distinct raw-value count;
- pairs where the stock-app displayed reference is exactly the same;
- same-reference pairs whose raw DP bytes are also the same;
- pairs where the displayed references differ;
- different-reference pairs whose raw DP bytes also differ;
- exact per-marker raw bytes, source offsets, observation index, full receipt interval, completion-time distance, and before/same/after relation.

No unit conversion is attempted.

For example:

- `41.3 V` and `41.30 V` remain different human references;
- raw bytes whose generic unsigned projection is `413` are not converted to `41.3 V`;
- a raw value changing whenever a displayed value changes is useful prioritization evidence, not proof of scale or meaning;
- a stable raw value near repeated identical markers is useful repeatability evidence, not proof of field ownership.

Pair counts are not a confidence score.

## Ranking

Candidate order is deterministic research prioritization only. The comparator prefers, in order:

1. more unambiguous marker support;
2. more same-reference pairs with the same raw value;
3. more different-reference pairs with a different raw value;
4. fewer combined conflicting-nearest and shared-observation ambiguities;
5. smaller worst accepted completion-time distance;
6. stable structural identity ordering.

Index zero is therefore **the first candidate to inspect next**, not a decoded ES80 telemetry mapping.

## Resource bounds

Caller policy must explicitly bound:

- maximum marker count;
- maximum parsed-message observation count;
- maximum candidate-record occurrence count;
- maximum absolute marker-to-message-completion time distance.

A zero time-distance policy is legitimate when a research setup requires exact completion/marker coincidence. Invalid or exceeded resource bounds fail closed.

## Verification

A standalone Swift 6.2.1 warnings-as-errors harness matching the parent API shape currently passes **17/17** focused tests in both debug and optimized release.

Coverage includes:

- repeated exact-reference equality patterns;
- deterministic candidate ranking;
- high-callback-rate de-biasing;
- equally-near conflicting-value ambiguity;
- one physical candidate message supporting only the uniquely closer of two competing markers;
- equal-distance marker competition supporting neither marker;
- exact display-string preservation;
- completion-receipt timing and explicit before/after direction without interval look-ahead;
- mixed stream rejection;
- mixed continuity-generation rejection;
- mixed one-/two-byte DP hypothesis rejection;
- overlapping/non-monotonic message rejection;
- non-monotonic marker rejection;
- same DP ID with different raw types remaining separate;
- resource ceilings;
- invalid human labels/policy;
- no support producing no guessed candidate.

That harness is supporting software evidence only. Repository-native NembraCore and exact-head Xcode 27 acceptance are still required on the final dependency composition.

## Physical closure experiment

Once the active passive-capture path and legitimate plaintext path are ready, one minimal safe experiment should be enough to exercise this layer without asking the user to inspect hex manually:

1. select the physical ES80 in Nembra Research Capture and keep the scooter stationary;
2. record a short passive baseline on the selected exact stream;
3. insert several stock-app markers for one visible field, preserving the exact displayed text each time;
4. where safe and naturally occurring, include repeated identical references plus at least one changed reference;
5. export the immutable capture;
6. let offline tooling reconstruct the candidate family, parse the explicit DP hypothesis, and run this correlation automatically.

The user should not manually choose a DP ID or scale.

A strong repeated candidate still remains a hypothesis until Nembra repeats the experiment and verifies source, type, scale, unit, signedness, cadence, firmware/identity behavior, and disagreement cases on the real ES80.

## Safety / truth boundary

Classification: **OFFLINE RESEARCH PRIORITIZATION / NOT PHYSICAL FIELD VERIFICATION**.

This slice adds no CoreBluetooth application write, credential acquisition, decryption, command encoding, acknowledgement inference, motorized control, production ScooterService mapping, Dashboard telemetry, battery truth, range learning, propulsion truth, throttle signal, or regen signal.

Simulator/package/software success cannot be promoted to physical AOVOPRO ES80 protocol truth.
