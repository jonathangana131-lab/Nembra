# ES80 Offline Capture Report

Status: **PUBLIC-FAMILY FRAMING-CANDIDATE RESEARCH ONLY — NOT PHYSICAL ES80 PROTOCOL VERIFICATION**

This tool closes the operator gap between a shared Nembra passive-capture JSON artifact and the existing bounded Tuya-family framing candidate analyzer.

It does **not** decode scooter fields and it does not require the operator to copy raw hex, manually choose a characteristic, renumber fragments, or reconstruct continuity generations.

## Command

From the repository root:

```sh
swift run --package-path Packages/NembraBluetoothCapture nembra-es80-capture-report /path/to/capture.json
```

When the capture contains one unique target-attributable peripheral, the command selects that exact captured identifier automatically. Broad-scan advertisement-only devices are intentionally ignored for selection because an advertisement is candidate-catalog evidence, not proof of the selected physical target.

If target-attributable evidence contains more than one peripheral, the command fails closed and prints the exact candidates. Select one explicitly:

```sh
swift run --package-path Packages/NembraBluetoothCapture nembra-es80-capture-report \
  /path/to/capture.json \
  --peripheral '<exact captured identifier>'
```

Write the deterministic JSON report to a file:

```sh
swift run --package-path Packages/NembraBluetoothCapture nembra-es80-capture-report \
  /path/to/capture.json \
  --output /path/to/framing-report.json
```

`--compact` emits sorted-key compact JSON for automation.

When `--output` is used, the command also prints one compact operator summary to **stderr** after successful publication:

```text
candidate outcomes: completed=2 rejected=1 incomplete=1 unexpected_failures=0 streams=2 fragments=4
```

Those numbers are only cardinalities of bounded framing-candidate analyzer outcomes. `completed=2` means two byte sequences satisfied the selected public-family framing hypothesis under the selected offline limits; it does **not** mean Nembra verified two physical ES80 messages, decoded two DPs, or identified any vehicle field. Rejected and incomplete candidates remain useful falsifying/truncation evidence rather than being silently discarded.

Stdout mode remains JSON-only so the command can be piped directly into other deterministic tooling without summary text mixed into the artifact.

## Evidence-preserving output behavior

The command will **never** permit its derived report to replace the raw capture input, including when the output reaches the same file through a symlink alias. `--force-output` cannot override this rule.

Existing derived report files are also protected by default. To intentionally replace an existing report, use:

```sh
swift run --package-path Packages/NembraBluetoothCapture nembra-es80-capture-report \
  /path/to/capture.json \
  --output /path/to/existing-framing-report.json \
  --force-output
```

`--force-output` is valid only together with `--output` / `-o`; using it for stdout mode fails closed as an invalid command invocation.

For protected output, Nembra writes the report to a uniquely named sibling first and then publishes it with a non-replacing `FileManager.moveItem`. If a destination appears after preflight, the move fails instead of replacing it, and the temporary sibling is cleaned. This avoids relying on the unsupported Foundation combination of atomic + without-overwriting write options.

With `--force-output`, the source-capture identity check still runs first, then Foundation atomic replacement is allowed only for a distinct derived-report path.

These protections are about preserving research evidence and prior derived artifacts. They are not physical-device safety claims.

## Exact source-artifact binding

The command opens the source artifact once, reads it under the configured artifact-byte ceiling, rewinds the **same open file handle**, and requires a second complete pass to match the first byte-for-byte and terminate at the same offset. If the open file changes in place between or across those verification passes, admission fails closed before JSON decode.

The exact bytes from the first verified pass are then both hashed and decoded. The report wraps the framing analysis with:

- the input artifact byte count; and
- a lowercase SHA-256 digest of those exact admitted bytes.

The bounded reader does not normalize, re-encode, trim, or otherwise transform accepted input. A later replacement of the filesystem path cannot retarget the already-open subject used by the two verification passes.

The stable-read check and SHA-256 are artifact-integrity/provenance boundaries only. They do **not** authenticate the scooter, prove who recorded the capture, establish physical chain of custody by themselves, or verify any ES80 protocol meaning.

The raw capture JSON remains the authority for raw bytes. The report intentionally stores the digest and raw callback byte counts rather than duplicating encrypted payload bytes into a second evidence object that could later be mistaken for a transformed source of truth.

## Offline safety bounds

The command defaults to:

- `--max-artifact-bytes 67108864` (64 MiB source-artifact/decode ingress ceiling)
- `--max-message-bytes 65536`
- `--max-fragments 256`

All three values are **offline process/resource ceilings only**. They are not measured ES80 limits, expected packet sizes, protocol claims, learned device behavior, or physical capture maxima.

The artifact ceiling is enforced before JSON decode. Each verification pass consumes bounded chunks and reads at most one byte beyond the configured ceiling to prove that the source is oversized. The second pass is compared incrementally against the retained first pass, so the tool does not materialize a second full artifact merely to prove stability. The artifact-report builder independently validates already-materialized `Data` against the same ceiling before it invokes `PassiveBluetoothCaptureJSON.decode`.

For example:

```sh
swift run --package-path Packages/NembraBluetoothCapture nembra-es80-capture-report \
  /path/to/capture.json \
  --max-artifact-bytes 134217728
```

Choosing a larger value is a local tooling resource decision. It does not teach Nembra that an ES80 session or protocol object may be that size.

The message/fragment bounds apply later to framing-candidate reassembly. The bounded analyzer still rejects candidates that violate the selected limits. The report preserves that rejection rather than changing offsets, dropping observations, synthesizing timing, or trying alternate bytes until something parses.

## What the report preserves

The outer artifact-report schema v1 includes:

- exact source capture JSON SHA-256;
- exact source capture JSON byte count; and
- one deterministic framing-analysis report.

The nested framing-analysis schema **v3** includes:

- immutable capture session ID;
- captured `VehicleIdentity` metadata;
- capture session start time;
- exact selected peripheral identifier;
- explicit bridge provenance class `validated-software-session-only`;
- caller-owned analysis resource bounds;
- deterministic first-observed GATT + value-origin stream order;
- exact service and characteristic identifiers;
- exact `PassiveBluetoothValueOrigin`;
- every stream-local fragment's source capture record index and immutable capture sequence number;
- accepted receipt-sequence scope plus receipt-sequence number for each projected raw value observation;
- boot-relative receipt uptime;
- wall-clock receipt date as correlation metadata only;
- continuity generation;
- raw callback payload byte count without duplicating the raw payload itself;
- completed framing candidates with receipt-sequence scope plus first/last receipt sequence numbers;
- typed candidate rejections, including receipt-order/scope failures;
- explicit continuity boundaries;
- explicit `candidatePacketZeroRestart` truncation when packet index zero starts a new candidate before the prior one completes;
- end-of-capture truncation;
- source-record mappings for every analyzer event.

`validated-software-session-only` is a machine-readable authority ceiling. `PassiveBluetoothCaptureSession` is publicly constructible, so a valid session and its derived report do not prove recorder custody, cryptographic attestation, physical AOVOPRO ES80 identity, protocol semantics, telemetry truth, command authority, or field GO.

The scoped receipt sequence is capture chronology/provenance only. It does not assign packet, DP, command, or vehicle meaning. The report keeps it because flattening accepted sequence scope back to uptime-only chronology would weaken the current bridge/analyzer evidence contract.

The library also exposes a deterministic `outcomeSummary` over those retained event kinds. It counts streams, fragments, completed candidates, rejected candidates, boundary-truncated candidates, end-truncated candidates, and unexpected analyzer failures. A packet-zero restart remains an `incompleteAtBoundary` event and is therefore counted as an incomplete candidate while retaining its explicit boundary reason and next-source mapping.

A `completed` event means only that the captured raw bytes satisfy the selected bounded public-family reassembly hypothesis. It does **not** mean the bytes are an ES80 message or that any field has been identified.

## Physical experiment handoff

After the product-facing Nembra Capture flow produces a versioned JSON artifact from the selected ES80:

1. keep the original artifact unchanged;
2. run this command against that artifact;
3. retain both the raw artifact and generated report;
4. verify the report's source-artifact SHA-256 against the retained raw file before using it for later protocol evidence;
5. retain the report's `validated-software-session-only` authority classification until an independently accepted stronger evidence layer actually earns promotion;
6. use the report plus its candidate-outcome summary to identify exact streams/candidate outcomes for the next correlation layer;
7. only promote a field after repeatable physical evidence verifies raw source, framing, DP identity/type, scale, signedness, units, cadence, continuity, and provenance.

A failed candidate is useful falsifying evidence. Do not edit the capture to manufacture a parse.

## Dependency contract

This report layer is intentionally downstream of the accepted passive-capture bridge and candidate analyzer. It must preserve their stronger provenance rather than flatten it.

The current bridge preserves capture record/sequence provenance, stream-local source mapping, scoped receipt-sequence chronology, explicit continuity-generation advances before target filtering, and the software-only provenance classification. The report consumes those contracts directly; it must not reconstruct a second byte timeline, drop continuity boundaries, erase provenance class, or renumber observations in a way that could make separated raw callbacks appear contiguous.

Any future bridge/analyzer provenance strengthening must remain visible in this report and its source mappings before the report layer can be considered accepted on that newer dependency head.

## Safety / truth boundary

This command adds no CoreBluetooth write path, command encoder, authentication/decryption key handling, production `ScooterService`, Dashboard telemetry wiring, battery/range authority, or acknowledgement claim.

It does not verify:

- the physical AOVOPRO ES80 uses this Tuya framing family;
- any physical service/characteristic identity;
- any DP ID, type, scale, signedness, or unit;
- battery percentage, voltage, current, watts/power, speed, throttle, regen, distance, or odometer semantics;
- command authorization or command acknowledgement.

Its purpose is narrower: make the passive physical-capture artifact directly consumable by deterministic Nembra offline tooling while keeping provenance, bounded resource behavior, and uncertainty intact.
