# ES80 Tuya BLE Transport Research

Research checkpoint: **2026-08-06**

Target: Nembra's physical **newer 2025-generation AOVOPRO ES80**.

Purpose: narrow the passive-capture/parser problem using official Tuya material without pretending generic Tuya protocol details are already verified on the physical ES80.

This document deliberately separates:

1. Bluetooth advertisement / GATT transport
2. Tuya's encrypted/reassembled phone↔device BLE protocol
3. decrypted Tuya command / DP payloads
4. module↔MCU serial framing
5. ES80-specific DP meanings

Those layers are **not interchangeable**.

No finding here authorizes a motorized-hardware write.

## Evidence classes

- **VERIFIED PUBLIC TUYA** — directly documented by Tuya for the stated SDK/protocol generation.
- **GENERIC TUYA CANDIDATE** — useful passive-capture expectation, not verified as the 2025 ES80's exact generation/configuration.
- **ES80 DIRECT APP OBSERVATION** — visible behavior on the actual 2025 ES80 stock app, before raw transport mapping.
- **UNKNOWN / PHYSICAL VERIFICATION REQUIRED** — exact ES80 transport or DP semantics not established publicly.

## Critical architecture rule: do not parse the wrong layer

Tuya documents a familiar serial packet format beginning with `0x55 0xAA`, followed by version, command, big-endian payload length, payload, and additive modulo-256 CRC/check byte. That format belongs to Tuya's **MCU standard/module serial integration layer**.

It is **not evidence that iPhone CoreBluetooth notifications from the 2025 ES80 begin with `55 AA`**.

Official source:
- Tuya MCU Standard Protocol — Bluetooth LE Integration Basic Features: https://developer.tuya.com/en/docs/mcu-standard-protocol/Bluetooth-LE-Intergation-Base-Function?id=Kd3q32tjfcufw

Nembra must preserve raw GATT bytes first and determine the phone↔device transport empirically. If a later teardown proves an internal ES80 MCU/module serial link uses `55 AA`, that would be a separate transport fact.

## Layer 1 — advertisement and GATT fingerprint candidates

### Modern TuyaOS BLE candidate

Tuya's current Port SDK documents:

- service UUID `0xFD50`;
- write-without-response characteristic `00000001-0000-1001-8001-00805F9B07D0`;
- notify characteristic `00000002-0000-1001-8001-00805F9B07D0`;
- optional read characteristic `00000003-0000-1001-8001-00805F9B07D0` when link-layer encryption support is enabled;
- Tuya company/manufacturer identifier `0x07D0` in documented scan response data;
- advertisement service data associated with `FD50`.

Official source:
- https://developer.tuya.com/en/docs/iot-device-dev/Porting-Guide-BLE?id=Kam0xjtz4n6e0

**Classification:** VERIFIED PUBLIC TUYA, GENERIC TUYA CANDIDATE for the ES80.

### Legacy Tuya BLE candidate

Tuya's older BLE SDK guide documents:

- service `0x1910`;
- notify characteristic `0x2B10`;
- write / write-without-response characteristic `0x2B11`;
- ATT MTU 23 / 20-byte application payload in that legacy SDK generation;
- older advertisement/service-data layouts and Tuya manufacturer data.

Official source:
- https://developer.tuya.com/en/docs/iot-device-dev/tuya-ble-sdk-user-guide?id=K9h5zc4e5djd9

**Classification:** VERIFIED PUBLIC legacy Tuya, GENERIC TUYA CANDIDATE only.

### Capture consequence

The ES80 capture adapter should not filter discovery to `FD50` or `1910`. It should record:

- local name;
- all service UUIDs;
- manufacturer data;
- service data;
- Tx power when available;
- solicited/overflow UUIDs when iOS reports them;
- every service and characteristic;
- characteristic properties/security properties;
- MTU-relevant observed payload lengths.

A match to a generic Tuya fingerprint raises confidence; a mismatch must remain evidence rather than being discarded.

## Layer 2 — phone↔device Tuya protocol is reassembled and decrypted above GATT

Tuya's current Bluetooth Software architecture explicitly describes this receive path:

`GATT write -> receive packet -> packet reassembly -> decryption -> BLE command -> command dispatch -> DP parser`

The send path is the reverse, including packet assembly/fragmentation and encryption before GATT notification/write transport.

Tuya names relevant internal stages/functions including:

- `tuya_ble_gatt_receive_data`
- `TUYA_BLE_EVT_MTU_DATA_RECEIVE`
- `tuya_ble_handle_ble_data_evt`
- `tuya_ble_commonData_rx_proc`
- packet reassembly and decryption
- `TUYA_BLE_EVT_BLE_CMD`
- `tuya_ble_handle_ble_cmd_evt`
- `tuya_ble_commData_send`
- packet assembly and encryption

Official source:
- https://developer.tuya.com/en/docs/iot-device-dev/bluetooth_software_ble?id=Kcy65n2q8g8pp

**Important consequence:** one CoreBluetooth notification is not guaranteed to equal one complete Tuya command or DP report. The capture model must preserve exact notification boundaries **and** monotonic ordering so later research can reconstruct fragmented messages without rewriting history.

## Outer encrypted frame structure: still not publicly pinned down here

The official public pages inspected in this pass establish that Tuya performs:

- packet reassembly;
- decryption on receive;
- encryption on send;
- command dispatch after decryption.

They do **not**, in the material located for this checkpoint, provide enough version-specific detail to safely hard-code the exact encrypted outer-frame header, fragment index format, CRC placement, encryption mode/key selection, or session-key derivation for the physical 2025 ES80.

Therefore Nembra must not invent an outer-frame parser yet.

The capture format should retain opaque raw GATT payloads losslessly until the ES80's actual protocol generation is identified.

## Cryptographic primitives are not session semantics

The legacy Tuya BLE SDK documentation requires platform ports for primitives including AES-128 ECB/CBC and hashes/HMACs. That proves those primitives exist in that SDK ecosystem, not which exact algorithm/key schedule the 2025 ES80 uses for each message.

Official source:
- https://developer.tuya.com/en/docs/iot-device-dev/tuya-ble-sdk-user-guide?id=K9h5zc4e5djd9

Do not infer a session key from the presence of an AES API alone.

## Layer 3 — decrypted command / DP behavior

### Initial state synchronization is a high-value capture point

Tuya's application-development guidance states that after Bluetooth connection/binding, the app performs a DP query to synchronize current device state. Current callback/API documentation also defines an all-DP query when the DP query data length is zero.

This makes **first connection / reconnect / opening the stock panel** a high-value passive capture window even if the scooter is stationary and values are not changing.

Official sources:
- https://developer.tuya.com/en/docs/iot-device-dev/Application-Code-Development?id=Kambpmwque0jy
- https://developer.tuya.com/en/docs/iot-device-dev/Callback-BLE?id=Karulz5ody97z

### DP records are typed, but generation details vary

Legacy Tuya BLE documentation describes DP records composed of:

- DP ID;
- DP type;
- DP length;
- DP data;
- multiple DP records concatenated in one report.

Legacy material describes a one-byte DP length for that Bluetooth SDK generation, while newer TuyaOS DP APIs expose a `uint16_t` DP data length in their internal data structures/APIs.

Official sources:
- https://developer.tuya.com/en/docs/iot-device-dev/tuya-ble-sdk-faq?id=K9gq09vg2txe4
- https://developer.tuya.com/en/docs/iot-device-dev/bluetooth_software_map_bt_dp_data?id=Kcmeae40r8zdq

**Nembra consequence:** do not choose a DP-record decoder solely from one SDK-era document. First identify the ES80's protocol generation and decrypted framing from captures.

### DP serial numbers and acknowledgements matter

Current Tuya callback/DP documentation includes:

- serial numbers (`sn`) for data events;
- DP send modes;
- optional ACK / no-ACK behavior;
- response status associated with sent DP data;
- all-DP query semantics.

Official sources:
- https://developer.tuya.com/en/docs/iot-device-dev/Callback-BLE?id=Karulz5ody97z
- https://developer.tuya.com/en/docs/iot-device-dev/bluetooth_software_map_bt_dp_data?id=Kcmeae40r8zdq

The passive evidence model should therefore retain enough ordering/correlation context to distinguish:

- app request;
- device report;
- potential acknowledgement/response;
- repeated state refresh;
- unsolicited report-on-change.

A production command must never be called “confirmed” merely because a write returned successfully at the CoreBluetooth API level.

## Layer 4 — MCU/module serial protocol remains a separate hypothesis

Tuya MCU standard integration uses the `55 AA` serial frame family. Some Tuya products contain a separate MCU plus Bluetooth/network module; others may integrate application logic differently.

For the ES80, public research has **not** yet established:

- whether its Bluetooth logic is on the dashboard/controller MCU or a separate Tuya module;
- whether an internal UART link exists;
- whether that UART uses the standard `55 AA` frame;
- whether the live electrical telemetry originates at BMS, motor controller, dashboard MCU, or another component.

Those remain teardown/capture questions.

## Layer 5 — current 2025 ES80 app correlation anchors

Direct observation on the physical 2025 ES80 stock app establishes live display of:

- battery percentage;
- voltage;
- amps/current;
- wattage/power.

AOVOPRO's current 2025/Tuya product material also publicly exposes battery %, estimated range, trip/total mileage, and controls.

These are **correlation anchors**, not decoded DP facts.

The first successful decrypted DP map should prioritize:

1. battery percentage
2. voltage
3. current
4. wattage / whether derived
5. speed
6. trip mileage
7. total mileage / odometer
8. charging state
9. mode
10. light / lock / start-mode readback

## Reporting behavior changes how capture must be designed

Tuya's current mobility guide recommends report-on-change behavior for many ride/battery values and full synchronization at pairing/reconnection/query time.

Official source:
- https://developer.tuya.com/en/docs/iot/mobility_development_guidelines?id=Kfme01kf7zw31

Therefore:

- no notifications while stationary does **not** prove a DP is absent;
- opening/reconnecting the stock app may produce a more useful full state snapshot than passively staring at an idle connection;
- safe physical changes should be timestamp-correlated with raw notifications;
- identical repeated app values should not be fabricated into telemetry cadence evidence.

## Device identity / binding clues

Tuya's BLE APIs describe product/device identity concepts including:

- Product ID (PID) assigned per product;
- unique device authorization identity / auth key in applicable flows;
- firmware/hardware version metadata;
- configurable local name.

Official source:
- https://developer.tuya.com/en/docs/iot-device-dev/API-BLE?id=Karuly74nihjx

This reinforces a Nembra rule already implied by public ES80 reports: **local name is not a durable physical-scooter identity key**.

The eventual learned-range persistence key should use a verified stable physical identity only after Nembra knows which identifier is legitimate and safe to persist.

## What the passive capture model should preserve now

Without editing the active PR #11 implementation branch from this worker, the research implies the capture artifact should be capable of preserving:

- complete advertisement dictionaries and raw manufacturer/service data;
- all discovered services/characteristics/properties;
- raw GATT value bytes exactly as received;
- one event per actual notification/read result rather than guessed reconstructed packets;
- characteristic UUID and value origin;
- sequence order and monotonic receipt time;
- wall-clock correlation timestamp as metadata only;
- connection / disconnection / continuity boundaries;
- subscription changes;
- stock-app-visible correlation markers;
- schema versioning for capture JSON.

After outer framing is actually decoded, a **derived decoder layer** can reconstruct Tuya messages/DP records without mutating the raw evidence.

## Smallest justified physical capture after public research

Public research has reduced the next required physical step to a passive fingerprint/correlation session.

### Session A — identity and GATT

Record:

- advertisement before stock app connects;
- local name;
- manufacturer/service data;
- all services/characteristics/properties;
- connection/reconnect state;
- notification subscriptions and raw values.

Key question: does the 2025 ES80 match `FD50`, legacy `1910`, or something else?

### Session B — initial state sync

Reconnect/open the stock panel and capture the first several seconds of raw traffic while recording visible:

- battery %;
- voltage;
- amps;
- watts;
- speed = 0;
- trip mileage;
- odometer.

Key question: can a full-state query/report boundary be recognized?

### Session C — controlled correlation

Without Nembra sending unknown writes, observe stock-app traffic while values legitimately change:

- stationary rest;
- charger connected/disconnected;
- after a short ride, voltage recovery;
- later during a controlled ride, speed/current/power changes;
- braking, specifically to determine current sign/convention if safely observable.

## Current research classification

### VERIFIED PUBLIC TUYA

- modern TuyaOS BLE service candidate `FD50` and documented characteristic family;
- legacy Tuya BLE service candidate `1910` / `2B10` / `2B11`;
- Tuya BLE receive path performs packet reassembly and decryption before command/DP dispatch;
- send path performs command packaging, encryption, and BLE transport;
- Tuya DPs are typed records and support full-state query/report behavior;
- modern Tuya DP APIs have serial/ACK concepts;
- `55 AA` framing is documented for the MCU/module serial protocol layer.

### ES80 DIRECT APP OBSERVATION

- newer 2025-generation ES80 target;
- stock app live battery %;
- stock app live voltage;
- stock app live amps/current;
- stock app live wattage/power.

### UNKNOWN / PHYSICAL VERIFICATION REQUIRED

- whether the 2025 ES80 uses `FD50`, `1910`, or another GATT profile;
- exact advertisement identity/PID;
- exact encrypted outer Tuya frame and fragmentation format for this scooter;
- pairing/session key derivation and encryption mode for this scooter;
- exact DP IDs/types/scales;
- whether wattage is transmitted or derived;
- current signedness and physical meaning;
- command acknowledgement semantics;
- internal MCU/module topology and whether any `55 AA` serial link exists;
- stable physical-scooter identity for per-scooter learned range.

## Sources

Official Tuya sources accessed 2026-08-06:

- https://developer.tuya.com/en/docs/iot-device-dev/bluetooth_software_ble?id=Kcy65n2q8g8pp
- https://developer.tuya.com/en/docs/iot-device-dev/Porting-Guide-BLE?id=Kam0xjtz4n6e0
- https://developer.tuya.com/en/docs/iot-device-dev/tuya-ble-sdk-user-guide?id=K9h5zc4e5djd9
- https://developer.tuya.com/en/docs/iot-device-dev/tuya-ble-sdk-faq?id=K9gq09vg2txe4
- https://developer.tuya.com/en/docs/iot-device-dev/Callback-BLE?id=Karulz5ody97z
- https://developer.tuya.com/en/docs/iot-device-dev/bluetooth_software_map_bt_dp_data?id=Kcmeae40r8zdq
- https://developer.tuya.com/en/docs/iot-device-dev/Application-Code-Development?id=Kambpmwque0jy
- https://developer.tuya.com/en/docs/iot-device-dev/API-BLE?id=Karuly74nihjx
- https://developer.tuya.com/en/docs/iot/mobility_development_guidelines?id=Kfme01kf7zw31
- https://developer.tuya.com/en/docs/mcu-standard-protocol/Bluetooth-LE-Intergation-Base-Function?id=Kd3q32tjfcufw
