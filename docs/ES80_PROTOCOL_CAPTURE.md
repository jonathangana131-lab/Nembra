# AOVOPRO ES80 Passive Bluetooth Capture

Status: software capture/evidence model only. No real AOVOPRO ES80 BLE identity, GATT mapping, data point mapping, authentication, framing, or command semantics are verified by this document.

## Purpose

Nembra needs a durable way to record raw Bluetooth evidence from the physical AOVOPRO ES80 without guessing protocol meanings or adding motorized-vehicle writes. The first job is to preserve what was actually observed so later offline correlation and parser tests can promote only proven facts.

The core capture artifact therefore records:
- advertisements and their raw manufacturer/service bytes
- discovered services
- discovered characteristics and advertised properties
- notification, indication, ambiguous subscribed-value, and explicitly requested read-response payloads
- stock-app state markers such as a visibly displayed battery value
- explicit capture interruptions/continuity gaps
- strict process-local ordering using monotonic receipt uptime

The capture model deliberately contains no command/write event or encoder.

## Current evidence classifications

### VERIFIED product/general facts

These facts are externally documented, but they do not by themselves prove the physical ES80's packet layout:

- AOVOPRO's official ES80 page identifies the model as ES80, lists a 36 V / 10.5 Ah battery, and says current ES80/ESMAX production can be supplied with the Tuya Smart app. Source: https://www.aovopro.com/product/aovopro-es80-electric-scooter-350w-10-5-ah-long-range-high-speed-foldable-electric-scooter/
- Tuya's generic BLE data-point documentation describes DP payload fields including `dp_id`, `dp_type`, `dp_data_len`, and the value bytes. Source: https://developer.tuya.com/en/docs/iot-device-dev/bluetooth_software_map_bt_dp_data?id=Kcmeae40r8zdq
- Tuya's current Ride Development Guide explicitly says a feature name/identifier depends on the DP list configured for that product, and actual DP IDs/identifiers follow the selected Product Configuration. Therefore Nembra must not assign an ES80 battery/speed/control DP merely because another Tuya product uses that number. Source: https://developer.tuya.com/en/docs/iot/mobility_development_guidelines?id=Kfme01kf7zw31
- Tuya's generic BLE pairing documentation describes a Tuya-specific service UUID `0xFD50` for its pairing protocol. This is a Tuya-platform fact, not yet an ES80 capture fact. Source: https://developer.tuya.com/en/docs/iot-device-dev/bluetooth_software_map_bt_bonding?id=Kcmeabmo402en

### VERIFIED user-visible ES80 behavior

- The physical ES80 used for Nembra development has been observed with a stock Tuya UI that displays a numeric battery percentage.

That observation proves only a user-facing value exists somewhere in the stock stack. It does not prove that the scooter directly transmits a true 1%-resolution state-of-charge value.

### UNKNOWN on the physical ES80 until captured

- advertisement local name, service data, and manufacturer data
- whether `0xFD50` is actually present
- all service and characteristic UUIDs
- characteristic read/write/notify/indicate properties
- pairing/authentication/session behavior
- whether payloads are encrypted or wrapped before DP data is exposed
- the battery percentage DP/characteristic/source
- whether the battery percentage is direct, derived, filtered, or quantized
- battery update cadence/latency and load/rest behavior
- voltage and charging-state exposure
- speed source, cadence, latency, jitter, and resolution
- odometer/trip values and scaling
- ride-mode/control identifiers and semantics
- command acknowledgement behavior
- packet framing/checksum used by this ES80 batch
- firmware/hardware/batch differences

Generic Tuya examples, including any `55 AA ...` serial/accessory framing documented for other Tuya paths, must not be promoted to ES80 protocol truth without a matching ES80 capture.

## Safety boundary

Passive research follows:

`discover → enumerate → subscribe/read → capture → correlate → decode → validate`

Do not send random bytes to the scooter. A future write path is a separate gate and requires known characteristic/framing, known semantic, known range, understood acknowledgement/state confirmation, parser/encoder tests, and cautious stationary/unloaded validation where appropriate.

Recording that a characteristic advertises `.write` or `.writeWithoutResponse` is observational metadata only. It is not authorization to invoke it.

## Capture truth rules

1. Preserve raw bytes. Do not replace a payload with a decoded interpretation.
2. Unknown UUIDs/values remain unknown rather than being normalized to a guessed Tuya meaning.
3. Stock-app observations are correlation markers, not decoded protocol facts.
4. Monotonic uptime is the ordering clock. Wall-clock dates are correlation metadata and cannot repair event order.
5. Imported capture artifacts must be revalidated for nested evidence validity plus sequence/uptime ordering; Codable decoding is not a trust boundary.
6. Disconnects, Bluetooth transitions, process restarts, and observer restarts create explicit continuity breaks.
7. A capture session is tied to a vehicle identity, but the current ES80 profile identity does not assert a verified protocol family implementation.
8. Parser/decoder output should later live beside raw evidence rather than overwrite it.
9. Software/Simulator fixtures never become real-hardware verification.

## Battery investigation workflow

For the battery percentage requirement, collect longer passive sessions that include deliberate stock-app markers such as:
- Tuya battery value before riding
- Tuya battery value after meaningful riding windows
- values while accelerating versus stopped/rested
- reconnect observations
- charging/unplugged transitions when available
- low-battery behavior

Then correlate changes against raw notifications/read responses and discovered GATT structure. Do not select the adaptive-range model's authoritative SoC source or minimum useful percentage window until the physical ES80 evidence supports it.

## Software artifact

`PassiveBluetoothCaptureSession` is intentionally platform-neutral and Codable so physical-device tooling can export raw observations for offline parser/tests. JSON export preserves sub-second wall-clock correlation metadata while monotonic uptime remains the ordering authority.

The current model records only non-mutating value origins:
- notification, when the acquisition source can prove it
- indication, when the acquisition source can prove it
- subscribed-value update when the acquisition API cannot truthfully distinguish notification from indication
- read response

A future CoreBluetooth acquisition adapter may feed this model, but it must use the ambiguous subscribed-value classification when CoreBluetooth cannot prove notification versus indication. It must preserve the same evidence boundaries and must not quietly add vehicle writes.
