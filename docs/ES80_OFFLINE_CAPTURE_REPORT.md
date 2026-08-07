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

Write the deterministic JSON report atomically to a file:

```sh
swift run --package-path Packages/NembraBluetoothCapture nembra-es80-capture-report \
  /path/to/capture.json \
  --output /path/to/framing-report.json
```

`--compact` emits sorted-key compact JSON for automation.

## Offline safety bounds

The command defaults to:

- `--max-message-bytes 65536`
- `--max-fragments 256`

These values are **process/resource ceilings only**. They are not measured ES80 limits, expected packet sizes, protocol claims, or learned device behavior. They can be tightened explicitly for a specific offline run.

The bounded analyzer still rejects candidates that violate the selected limits. The report preserves that rejection rather than changing offsets, dropping observations, synthesizing timing, or trying alternate bytes until something parses.

## What the report preserves

Schema v1 includes:

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

A `completed` event means only that the captured raw bytes satisfy the selected bounded public-family reassembly hypothesis. It does **not** mean the bytes are an ES80 message or that any field has been identified.

The raw capture JSON remains the authority for bytes. The report intentionally does not create a second copy of encrypted payload bytes that could later be mistaken for a transformed evidence source.

## Physical experiment handoff

After the product-facing Nembra Capture flow produces a versioned JSON artifact from the selected ES80:

1. keep the original artifact unchanged;
2. run this command against that artifact;
3. retain both the raw artifact and generated report;
4. use the report to identify exact streams/candidate outcomes for the next correlation layer;
5. only promote a field after repeatable physical evidence verifies raw source, framing, DP identity/type, scale, signedness, units, cadence, continuity, and provenance.

A failed candidate is useful falsifying evidence. Do not edit the capture to manufacture a parse.

## Safety / truth boundary

This command adds no CoreBluetooth write path, command encoder, authentication/decryption key handling, production `ScooterService`, Dashboard telemetry wiring, battery/range authority, or acknowledgement claim.

It does not verify:

- the physical AOVOPRO ES80 uses this Tuya framing family;
- any physical service/characteristic identity;
- any DP ID, type, scale, signedness, or unit;
- battery percentage, voltage, current, watts/power, speed, throttle, regen, distance, or odometer semantics;
- command authorization or command acknowledgement.

Its purpose is narrower: make the passive physical-capture artifact directly consumable by deterministic Nembra offline tooling while keeping provenance and uncertainty intact.
