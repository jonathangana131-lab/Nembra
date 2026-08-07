# ES80 Tuya Candidate Offline Framing Analysis

Status: **PUBLIC-FAMILY CANDIDATE TOOLING — NOT PHYSICAL ES80 VERIFICATION**

This slice adds bounded, semantic-free offline analysis for one Tuya BLE protocol family already documented in `ES80_TUYA_REVERSE_ENGINEERING_CANDIDATES.md`.

It exists to shorten the path from an immutable physical ES80 CoreBluetooth capture to a falsifiable transport/framing hypothesis. It does **not** promote public reverse engineering into scooter truth and it does not add any Bluetooth write path, credential handling, decryption, DP decoding, telemetry mapping, or vehicle command behavior.

## Public evidence encoded

Two independent public implementations currently corroborate the candidate structure:

- `PlusPlus-ua/ha_tuya_ble` at commit `6037ac5a04ceb23a36d1b88e2303aa1da7fdbe83`;
- `hms-homelab/hms-esp-tuya-ble` on its current public `main` as researched by Nembra.

The candidate recognizer encodes only the portions required for offline structural testing:

1. BLE fragmentation uses a low-seven-bits-first varint packet index, with the high bit meaning continuation.
2. Fragment zero also contains the candidate assembled encrypted-message length and a raw protocol-version byte before encrypted bytes.
3. The stricter `ha_tuya_ble` receiver rejects varints longer than four bytes; Nembra mirrors that fail-closed receive bound rather than accepting an arbitrary generic varint grammar.
4. A candidate encrypted envelope has one security-flag byte, a 16-byte IV, and one or more AES-CBC-sized 16-byte ciphertext blocks.
5. After legitimate caller-provided decryption, the candidate logical packet is `seq_num: UInt32 BE`, `response_to: UInt32 BE`, `code: UInt16 BE`, `data_len: UInt16 BE`, opaque `data`, then `CRC16: UInt16 BE`.
6. Candidate CRC uses initial value `0xFFFF` and reflected polynomial `0xA001` over the 12-byte logical header plus data.
7. The public family zero-pads the logical packet to a 16-byte boundary before encryption.

These are **CORROBORATED PUBLIC REVERSE ENGINEERING**, not verified AOVOPRO ES80 semantics.

## Truth boundaries

The analyzer deliberately refuses to infer or manufacture:

- ES80 service or characteristic identity;
- Tuya DP IDs, types, scale, units, signedness, cadence, or field meaning;
- battery %, voltage, current, watts, speed, odometer, trip, charging state, throttle, regen, or any other vehicle telemetry;
- session/local/login keys;
- authentication success;
- command acknowledgement;
- writable capabilities;
- a claim that a structurally matching message actually came from this Tuya family.

`code` and logical `data` remain opaque bytes even after CRC validation.

## Continuity and provenance contract

`TuyaCandidateFragmentObservation` requires the higher-level capture layer to supply:

- exact peripheral identifier;
- exact service identifier;
- exact characteristic identifier;
- an explicit byte-continuity generation;
- process-local monotonic receipt uptime;
- raw opaque value bytes.

One `TuyaCandidateFragmentReassembler` permanently binds to the first stream identity and continuity generation it accepts. A different stream, a new continuity generation, non-monotonic receipt time, skipped/out-of-order packet index, declared-length overrun, or post-completion data fails closed.

That means a disconnect, interrupted acquisition, target change, or other evidence gap cannot silently splice bytes into one candidate message. The capture layer remains authoritative for deciding when continuity is broken.

`TuyaCandidateTranscriptAnalyzer` adds a batch layer for an already ordered immutable value transcript. It automatically rolls from one completed candidate message to the next while preserving every important failure boundary as output evidence. It emits explicit events for:

- completed candidate messages;
- a candidate rejected by the framing contract, including its first, last accepted, and failing observation indices;
- an incomplete candidate terminated by stream-identity and/or continuity-generation change;
- an incomplete candidate still open when the transcript ends;
- an unexpected analyzer failure, which stops analysis rather than silently discarding evidence.

The transcript analyzer never retries mutated bytes, searches for a convenient parse offset, or joins data across a known gap. This makes future physical capture analysis reproducible without asking the user to manually decide which hex fragments look valid.

## Resource safety without invented hardware limits

The caller must inject:

- maximum candidate encrypted-message bytes;
- maximum candidate fragment count.

Those are analysis resource limits only. There are intentionally no hard-coded ES80 message-size or fragment-count claims.

## Envelope versus semantics

`TuyaCandidateEncryptedEnvelope.inspect` checks structural shape only. It preserves the raw security flag and IV and never selects a key or decrypts.

`TuyaCandidateLogicalPacket.parse` operates only on caller-supplied plaintext. It validates length, optional exact public-family zero padding, and CRC. It does not perform AES, derive credentials, or interpret command/data semantics.

This separation keeps the evidence ladder explicit:

`raw capture -> ordered same-stream/same-generation transcript -> candidate fragments -> candidate encrypted envelope -> legitimate external decryption (future, credential-safe) -> candidate logical packet + CRC -> only then product-specific DP correlation research`

A failure at any stage is useful falsifying evidence and should not be massaged until it parses.

## Acceptance evidence in this slice

The repository tests exercise:

- one- and multi-byte candidate varints;
- truncated/overlong varint rejection with caller-cursor rollback;
- multi-fragment reconstruction;
- exact stream and continuity-generation isolation;
- strict monotonic receipt ordering;
- missing/out-of-order fragment rejection with atomic recovery;
- injected message/fragment resource bounds;
- declared-length overrun, clean retry after rejected first fragment, and post-completion rejection;
- encrypted envelope minimum/alignment rules;
- logical big-endian header extraction without semantic interpretation;
- CRC corruption rejection;
- exact-vs-zero-padded plaintext policy separation;
- non-zero padding rejection;
- automatic rollover across multiple complete candidate messages in one transcript;
- explicit preservation of continuity-boundary truncation;
- whole-candidate rejection followed by clean packet-zero recovery;
- explicit end-of-transcript truncation evidence.

Supplemental local Swift 6.2.1 validation passed **17/17 focused tests across two suites** in both debug and release with warnings treated as errors. That is supporting evidence only. Repository/exact-head CI remains the acceptance source for the integrated branch.

## Physical next step

This tooling does not replace the active passive-capture work. Once a physical ES80 capture supplies immutable raw notification bytes with exact GATT identity and continuity generations, offline analysis can feed those values into the transcript analyzer and candidate recognizer without manual hex selection.

A structural match raises a transport hypothesis only. Production battery/current/power fields remain blocked until repeatable physical correlation proves each field's raw source, scale, units, signedness, cadence, and provenance.
