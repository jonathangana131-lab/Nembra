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

The command reads the source artifact under the configured artifact-byte ceiling, then hashes and decodes the **exact bytes returned by that bounded read**. The report wraps the framing analysis with:

- the input artifact byte count; and
- a lowercase SHA-256 digest of those exact bytes.

The bounded reader does not normalize, re-encode, trim, or otherwise transform accepted input. This means a later worker can verify which physical-capture artifact produced a report even when two files decode to the same session content but differ byte-for-byte, for example because one was re-encoded or reformatted.

The SHA-256 is an artifact-integrity/provenance identifier only. It does **not** authenticate the scooter, prove who recorded the capture, establish chain-of-custody by itself, or verify any ES80 protocol meaning.

The raw capture JSON remains the authority for raw bytes. The report intentionally stores the digest and raw callback byte counts rather than duplicating encrypted payload bytes into a second evidence object that could later be mistaken for a transformed source of truth.

## Offline safety bounds

The command defaults to:

- `--max-artifact-bytes 67108864` (64 MiB source-artifact/decode ingress ceiling)
- `--max-message-bytes 65536`
- `--max-fragments 256`

All three values are **offline process/resource ceilings only**. They are not measured ES80 limits, expected packet sizes, protocol claims, learned device behavior, or physical capture maxima. They can be changed explicitly for a specific offline run.

The artifact ceiling is enforced before JSON decode. The file reader consumes bounded chunks and reads at most one byte beyond the configured ceiling to prove that the source is oversized; an oversized source fails closed instead of first materializing the complete file and decoded capture object graph. The artifact-report builder independently validates already-materialized `Data` against the same ceiling before it invokes `PassiveBluetoothCaptureJSON.decode`.

For example, to intentionally analyze a retained artifact under a different operator-tool ceiling:

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

The nested framing-analysis schema v1 includes:

- immutable capture session ID;
- captured `VehicleIdentity` metadata;
- capture session start time;
- exact selected peripheral identifier;
- caller-owned analysis resource bounds;
- deterministic first-observed GATT + value-origin stream order;
- exact service and characteristic identifiers;
- exact `PassiveBluetoothValueOrigin`;
- every stream-local fragment's source capture record index and sequence number;
- boot-relative receipt uptime;
- wall-clock receipt date as correlation metadata only;
- continuity generation;
- raw callback payload byte count without duplicating the raw payload itself;
- completed framing candidates;
- typed candidate rejections;
- explicit continuity boundaries;
- end-of-capture truncation;
- source-record mappings for every analyzer event.

The library also exposes a deterministic `outcomeSummary` over those retained event kinds. It counts streams, fragments, completed candidates, rejected candidates, boundary-truncated candidates, end-truncated candidates, and unexpected analyzer failures. The summary derives only from the already-retained report; it does not reinterpret bytes or add protocol meaning.

A `completed` event means only that the captured raw bytes satisfy the selected bounded public-family reassembly hypothesis. It does **not** mean the bytes are an ES80 message or that any field has been identified.

## Physical experiment handoff

After the product-facing Nembra Capture flow produces a versioned JSON artifact from the selected ES80:

1. keep the original artifact unchanged;
2. run this command against that artifact;
3. retain both the raw artifact and generated report;
4. verify the report's source-artifact SHA-256 against the retained raw file before using it for later protocol evidence;
5. use the report plus its candidate-outcome summary to identify exact streams/candidate outcomes for the next correlation layer;
6. only promote a field after repeatable physical evidence verifies raw source, framing, DP identity/type, scale, signedness, units, cadence, continuity, and provenance.

A failed candidate is useful falsifying evidence. Do not edit the capture to manufacture a parse.

## Dependency evolution

This report layer is intentionally downstream of the passive-capture bridge and candidate analyzer. When those accepted parents gain stronger provenance, this layer must preserve it rather than flatten it.

In particular, active analyzer work may add explicit candidate restart boundaries and scoped receipt-sequence chronology. On reconciliation, those semantics must remain visible in the report and source mappings before this lane can be accepted against the newer dependency head.

## Safety / truth boundary

This command adds no CoreBluetooth write path, command encoder, authentication/decryption key handling, production `ScooterService`, Dashboard telemetry wiring, battery/range authority, or acknowledgement claim.

It does not verify:

- the physical AOVOPRO ES80 uses this Tuya framing family;
- any physical service/characteristic identity;
- any DP ID, type, scale, signedness, or unit;
- battery percentage, voltage, current, watts/power, speed, throttle, regen, distance, or odometer semantics;
- command authorization or command acknowledgement.

Its purpose is narrower: make the passive physical-capture artifact directly consumable by deterministic Nembra offline tooling while keeping provenance, bounded resource behavior, and uncertainty intact.
