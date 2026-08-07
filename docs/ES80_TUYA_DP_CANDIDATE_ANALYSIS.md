# ES80 Tuya DP Candidate Analysis

Research/implementation checkpoint: **2026-08-07**

Dependency: PR #219 `[es80-tuya-offline] Add bounded public-family framing analysis`.

## Purpose

This slice moves Nembra one rung above an already CRC-validated, caller-supplied-plaintext Tuya logical-packet candidate. It can parse a byte slice as a sequence of generic Tuya **data-point-shaped units** while preserving the exact bytes and offsets needed for later physical correlation.

It does **not** claim that an AOVOPRO ES80 packet contains DPs, that any particular logical command code carries DPs, or that any DP ID means battery, voltage, current, watts, speed, mode, lock, light, trip, or odometer.

## Public basis

Current Tuya documentation consistently describes a DP as:

- DP ID;
- DP type;
- DP data length;
- DP data value.

Relevant Tuya documentation:

- https://developer.tuya.com/en/docs/iot-device-dev/bluetooth_software_map_bt_dp_data?id=Kcmeae40r8zdq
- https://developer.tuya.com/en/docs/iot/application-development?id=Kbe6embsa0wtu
- https://developer.tuya.com/en/docs/mcu-standard-protocol/Bluetooth-LE-Intergation-Base-Function?id=Kd3q32tjfcufw
- https://developer.tuya.com/en/docs/iot/title?id=K9nmje3twsy7n

The important ambiguity is preserved rather than hidden: Tuya documentation shows a **two-byte** DP data-length field for current Bluetooth SDK/MCU-standard material, while accessory/protocol-generation documentation states that some 3.x Bluetooth communication versions use **one byte** and 4.x-or-later versions use **two bytes**.

Nembra therefore has no implicit DP-length default. `TuyaCandidateDPParserPolicy` requires the caller to select `.oneByte` or `.twoByteBigEndian` explicitly.

## Generic type evidence

The parser recognizes the public Tuya type identifiers only as generic family structure:

- `0x00` raw;
- `0x01` boolean;
- `0x02` value/integer-shaped;
- `0x03` string;
- `0x04` enum;
- `0x05` bitmap.

Recognition does not establish ES80 meaning.

The parser records a shape finding for known public forms. A surprising length is preserved as evidence and flagged; the parser does not mutate, skip, truncate, or search for a nearby interpretation just to obtain a clean parse.

Current generic shape evidence retained by this candidate analyzer is:

- raw: `1...255` bytes;
- boolean: `1` byte;
- value: `4` bytes;
- string: `0...255` bytes;
- enum: `1` byte;
- bitmap: `1`, `2`, or `4` bytes.

For bitmap length, Nembra preserves the broader public-family `1/2/4`-byte shape because current Tuya documents are not perfectly uniform across product/protocol material. This is intentionally a structural candidate, not a product schema.

Out-of-family raw/string lengths are still retained byte-for-byte when the caller's resource policy permits them; the finding says only that the shape is surprising under this public candidate family. This keeps protocol falsification possible instead of turning a mismatch into discarded evidence.

## Scalar projection boundary

`candidateUnsignedBigEndianMagnitude` exists only for structurally compatible generic boolean/value/enum/bitmap forms. It is useful for later stock-app correlation, but the name is intentionally narrow:

- it does not assert signedness;
- it does not assert a decimal scale;
- it does not assert units;
- it does not assert a physical source;
- it does not assign a DP ID to an ES80 feature.

For example, raw magnitude `413` must not silently become `41.3 V`. That transformation would need an explicit hypothesis and repeatable physical correlation first.

A boolean is projected only when its single byte is exactly `0` or `1`. Other bytes stay unavailable rather than being coerced to true.

## Failure semantics

The parser is stateless and bounded by caller-owned analysis policy.

It fails closed on:

- invalid resource limits;
- incomplete DP headers;
- a declared value larger than the caller's resource limit;
- a value truncated by the source byte slice;
- more DP units than the caller permits.

Unknown type IDs are not failures. They are retained as raw structural evidence because an unknown/proprietary field is materially different from malformed transport.

Known-type shape mismatches are findings rather than parser errors when the bytes are structurally complete. This distinction is deliberate: transport truncation must fail closed, while a complete but surprising field is useful evidence against the current hypothesis.

Empty input produces an empty candidate payload and never manufactures a DP.

## Relationship to PR #219

PR #219 validates one public candidate transport/framing family through:

raw value observations -> bounded fragment reconstruction -> encrypted-envelope shape -> caller-supplied plaintext -> logical `>IIHH + data + CRC16` candidate.

This dependent slice can consume only the resulting `logicalPacket.data` bytes. The convenience bridge deliberately ignores the logical command code. Calling it means only:

> "For this already selected packet, test whether these data bytes structurally fit this DP grammar."

It does not mean:

> "This command is known to be an ES80 DP report."

## Verification

The focused suite covers both explicit length-width hypotheses, exact byte offsets, unknown types, fixed- and variable-length shape anomalies, malformed booleans, truncation, caller resource bounds, raw scalar projection, the logical-packet bridge, and deterministic malformed-input stress across both parser policies.

A local Swift 6.2.1 warnings-as-errors mirror of the exact feature logic passes **14/14** tests in both debug and optimized release. That is supporting software evidence only; repository-native exact-head NembraCore/Xcode acceptance remains required on the final dependency composition.

## Physical closure path

The useful next evidence is still physical and read-only:

1. capture immutable ES80 notification/value evidence with exact GATT/session/continuity provenance;
2. establish or falsify the #219 transport/framing candidate;
3. only through a legitimate local credential/decryption path, obtain plaintext without storing secrets in capture artifacts;
4. test the exact logical data bytes with the appropriate explicit DP-length hypothesis;
5. retain raw DP IDs/types/lengths/values and packet timing;
6. correlate repeated candidate magnitudes/changes against stock-app battery %, voltage, current/amps, and watts markers;
7. verify source, scale, units, signedness, cadence, identity and repeatability before promoting any field to production telemetry.

A structurally valid DP parse is still **not** a verified ES80 decoder.

## Safety / truth boundary

Classification: **OFFICIAL GENERIC TUYA STRUCTURE + CANDIDATE OFFLINE ANALYSIS**.

No application BLE write exists in this slice. No credential acquisition, decryption, command encoding, command acknowledgement, motor control, writable range, throttle signal, regen signal, or ES80 product-specific DP mapping is added.

Simulator/software/package success cannot be promoted to physical AOVOPRO ES80 verification.
