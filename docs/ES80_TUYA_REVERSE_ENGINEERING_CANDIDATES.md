# ES80 Tuya BLE Reverse-Engineering Candidates

Research checkpoint: **2026-08-06**

Target: Nembra's physical **newer 2025-generation AOVOPRO ES80**.

This document records **non-authoritative but reproducible public reverse-engineering evidence** that can accelerate passive capture analysis. It does not promote another Tuya product's protocol to ES80 truth.

The authoritative raw-evidence rule remains: capture the physical ES80 first, identify its actual protocol generation, and only then enable a matching decoder.

## Why these candidates are worth preserving

Two independent public local-Tuya-BLE implementations converge on essentially the same older Tuya BLE protocol family:

1. `PlusPlus-ua/ha_tuya_ble`, a Home Assistant integration supporting multiple real Tuya BLE product IDs.
2. `hms-homelab/hms-esp-tuya-ble`, a 2026 ESP32-C3 local bridge tested against a Tuya BLE breaker and explicitly based on the same protocol lineage.

These are not AOVOPRO ES80 implementations. Their agreement is useful as **CORROBORATED PUBLIC REVERSE ENGINEERING**, not ES80 verification.

Sources:

- https://github.com/PlusPlus-ua/ha_tuya_ble
- https://github.com/PlusPlus-ua/ha_tuya_ble/blob/6037ac5a04ceb23a36d1b88e2303aa1da7fdbe83/custom_components/tuya_ble/tuya_ble/tuya_ble.py
- https://github.com/PlusPlus-ua/ha_tuya_ble/blob/6037ac5a04ceb23a36d1b88e2303aa1da7fdbe83/custom_components/tuya_ble/tuya_ble/const.py
- https://github.com/hms-homelab/hms-esp-tuya-ble
- https://github.com/hms-homelab/hms-esp-tuya-ble/blob/main/main/tuya_packet.c
- https://github.com/hms-homelab/hms-esp-tuya-ble/blob/main/main/tuya_crypto.c

## A201 versus 1910: preserve the inconsistency

Tuya's legacy official documentation is internally interesting:

- its service table names `0x1910` as the GATT service with `0x2B10` notify and `0x2B11` write;
- its own advertisement examples advertise service UUID `0xA201` and put PID/product-key data under `A201` service data.

Meanwhile the public `ha_tuya_ble` implementation uses:

- GATT service `0000A201-0000-1000-8000-00805F9B34FB`;
- notify `00002B10-0000-1000-8000-00805F9B34FB`;
- write `00002B11-0000-1000-8000-00805F9B34FB`;
- GATT application MTU `20`;
- Tuya manufacturer ID `0x07D0`.

The newer 2026 ESP32 bridge also describes its tested device as advertising `A201` and implements the same general packet family.

**Nembra implication:** the passive scanner must treat `FD50`, `A201`, and `1910` as candidate clues and record all actual services. Do not hard-code only one candidate before scanning the ES80.

## Corroborated candidate outer BLE message format

The `ha_tuya_ble` implementation and the 2026 ESP32 implementation agree on this **decrypted logical packet** shape for their supported protocol family:

- `seq_num`: 4 bytes, big endian
- `response_to`: 4 bytes, big endian
- `code`: 2 bytes, big endian
- `data_len`: 2 bytes, big endian
- `data`: `data_len` bytes
- CRC16: 2 bytes

Their CRC implementation uses an initial value of `0xFFFF` and polynomial `0xA001`.

After the CRC, the logical message is zero-padded to a 16-byte boundary for encryption.

**Classification:** CORROBORATED PUBLIC REVERSE ENGINEERING. This is a decoder candidate only if the physical ES80's raw traffic matches the same generation.

## Corroborated candidate encrypted envelope

For the same protocol family, both implementations use an encrypted envelope consisting conceptually of:

- 1-byte security flag;
- 16-byte IV;
- AES-128-CBC ciphertext.

`ha_tuya_ble` selects different keys based on command/security context and uses a random IV when transmitting.

Again, this must not become Nembra's production ES80 decoder until a physical capture matches it.

## Corroborated candidate fragmentation format

Both implementations split encrypted logical messages across BLE-sized packets.

The candidate framing behavior is:

- each BLE chunk starts with a variable-length packet index encoded 7 bits per byte with the high bit as continuation;
- the first chunk additionally carries the total encrypted-message length using the same varint encoding;
- the first chunk then carries a protocol-version nibble/byte (`protocol_version << 4` in the public implementations);
- remaining bytes are encrypted-message data up to the GATT payload limit;
- following chunks continue the encrypted byte stream and increment the packet index.

This aligns with Tuya's official high-level statement that its BLE stack performs packet reassembly before decryption.

**Passive heuristic:** if physical ES80 notifications show monotonically increasing small varint-like leading fields and a first-fragment length/version pattern, Nembra can test this decoder offline against a copy of the raw capture. The raw capture itself stays immutable.

## Corroborated candidate login/session key flow

`ha_tuya_ble` implements the following protocol-generation-specific key flow:

1. Take the first 6 bytes/characters of the Tuya local key.
2. `login_key = MD5(local_key_first_6)`.
3. Send/get device-info using the login-key context.
4. Device-info response contains a 6-byte random value (`srand`) in the layout handled by that implementation.
5. `session_key = MD5(local_key_first_6 + srand)`.
6. Subsequent paired/session traffic uses the session key.

The implementation uses security flag `0x04` for login-key encrypted data and `0x05` for session-key encrypted data.

The 2026 ESP32 bridge implements the same session-key derivation and security-flag split.

**Classification:** CORROBORATED PUBLIC REVERSE ENGINEERING for a known Tuya BLE family. It is not permission to obtain, transmit, or use credentials against the ES80 until its protocol generation and legitimate device ownership/binding path are established.

## Candidate command codes from the public implementation

`ha_tuya_ble` defines, among others:

- device info: `0x0000`
- pair: `0x0001`
- DP send: `0x0002`
- device status/query: `0x0003`
- DP v4 send: `0x0027`
- receive DP: `0x8001`
- receive DP v4: `0x8006`
- time requests: `0x8011` / `0x8012`

These are useful labels for offline hypothesis testing if matching decrypted packet structure is proven. They are not ES80 command facts.

## Response correlation is stronger than BLE write completion

The candidate logical packet contains both `seq_num` and `response_to`. The Home Assistant implementation keeps a map of pending request sequence numbers and treats a received packet referencing `response_to` as an application-protocol response.

This independently reinforces Nembra's existing pessimistic-command design:

- CoreBluetooth write completion is transport evidence only;
- a Tuya-level response can be stronger protocol evidence;
- mirrored state/telemetry after a command may be stronger still depending on the ES80's actual semantics;
- exact acknowledgement policy remains hardware-capture work.

## Public implementations require Tuya credentials

The local Home Assistant implementation states that BLE control requires device identity/encryption credentials obtained from the user's own Tuya account/cloud context. The 2026 ESP32 bridge similarly expects device ID, local key, UUID, and MAC.

This is useful identity evidence:

- local BLE name is insufficient as persistent identity;
- Product ID/device ID/UUID/local key roles can differ;
- re-pairing may rotate keys in some products;
- Nembra must never log secret keys into ordinary capture JSON or GitHub artifacts.

**Security rule for Nembra:** raw research captures should record protocol evidence, not user secrets. If future decryption requires a credential, secrets must use an appropriate local secure-storage path and must be redacted from exported evidence by default.

## What would make this candidate family plausible for the ES80

A passive physical ES80 capture would substantially raise confidence if several of these appear together:

- advertisement/service data involving `A201` and manufacturer ID `07D0`;
- `2B10` notify + `2B11` write characteristics;
- approximately 20-byte GATT chunks;
- first-fragment packet-number/total-length/protocol-version pattern matching the public implementations;
- encrypted assembled payload length compatible with `1 + 16 + N*16` bytes;
- after legitimate decryption, a `>IIHH` logical header and valid CRC16/A001;
- request/response sequence correlation;
- DP payloads that correlate with the stock app's battery %, voltage, current, watts, speed, trip, and odometer.

One clue alone is not enough.

## What would falsify or weaken this candidate

Do not force this decoder if the ES80 instead shows:

- modern `FD50` service/characteristics and clearly different framing;
- different GATT payload structure;
- no matching varint fragmentation;
- assembled encrypted lengths incompatible with the candidate envelope;
- no valid logical CRC/header after legitimate candidate decryption;
- a different documented/observed TuyaOS generation;
- BLE link-layer encryption with a different app-level protocol path.

A failed candidate decode is useful evidence, not a reason to mutate captures until something parses.

## Safety boundary

This research is for **passive recognition and offline decoding first**.

Even if the candidate protocol matches perfectly, Nembra must still separately verify for the ES80:

- DP IDs and meanings;
- valid writable ranges;
- state confirmation/ack behavior;
- firmware/batch differences;
- stationary/unloaded first-write safety where appropriate.

Do not use generic Fingerbot/breaker DP IDs on a motorized scooter.
