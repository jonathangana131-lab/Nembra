# AOVOPRO ES80 Passive Bluetooth Capture

Status: software capture/evidence model only. No real AOVOPRO ES80 BLE identity, GATT mapping, data point mapping, authentication, framing, or command semantics are verified by this document.

## Purpose

Nembra needs a durable way to record raw Bluetooth evidence from the physical AOVOPRO ES80 without guessing protocol meanings or adding motorized-vehicle writes. The first job is to preserve what was actually observed so later offline correlation and parser tests can promote only proven facts.

The core capture artifact therefore records:
- advertisements and their raw manufacturer/service bytes
- advertised service UUIDs, overflow service UUIDs, solicited service UUIDs, connectability, RSSI, local name, and transmit-power metadata when iOS supplies them
- discovered services
- discovered characteristics and advertised properties, including notification/indication encryption requirements
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
- Apple's CoreBluetooth advertisement-data contract exposes standard metadata beyond the ordinary service UUID list, including overflow service UUIDs, solicited service UUIDs, transmit power, service data, manufacturer data, local name, and connectability when present. Nembra preserves these raw fields rather than silently dropping them. Source: https://developer.apple.com/documentation/corebluetooth/advertisement-data-retrieval-keys
- CoreBluetooth characteristic properties include notification/indication encryption requirements in addition to ordinary read/write/notify/indicate properties. Nembra records those as discovered capability metadata only. Source: https://developer.apple.com/documentation/corebluetooth/cbcharacteristicproperties
- CoreBluetooth uses `setNotifyValue(_:for:)` to subscribe to characteristic value changes; the resulting characteristic-value callback is also used for explicitly requested reads. The acquisition layer must therefore track the operation context and must not infer a protocol meaning merely because bytes arrived in that callback. Sources: https://developer.apple.com/documentation/corebluetooth/cbperipheral/setnotifyvalue(_:for:) and https://developer.apple.com/documentation/corebluetooth/cbperipheraldelegate/peripheral(_:didupdatevaluefor:error:)

### VERIFIED user-visible ES80 behavior

- The physical ES80 used for Nembra development has been observed with a stock Tuya UI that displays a numeric battery percentage.

That observation proves only a user-facing value exists somewhere in the stock stack. It does not prove that the scooter directly transmits a true 1%-resolution state-of-charge value.

### UNKNOWN on the physical ES80 until captured

- advertisement local name, service data, manufacturer data, overflow/solicited UUIDs, and transmit-power metadata
- whether `0xFD50` is actually present
- all service and characteristic UUIDs
- characteristic read/write/notify/indicate properties and security requirements
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

## CoreBluetooth acquisition constraints

The platform-neutral capture model is intentionally broader than one acquisition adapter, but a future iOS adapter must preserve current CoreBluetooth semantics rather than hiding them:

- Initial research for an ES80 whose service UUIDs are still unknown is a foreground discovery task. CoreBluetooth can scan without a service filter in the foreground, but background discovery is constrained and should not be represented as an unlimited generic scanner. After the physical ES80 service identity is verified, reconnect/discovery design can become appropriately service-specific.
- A scene-based app that later adopts CoreBluetooth state preservation/restoration should use a stable central-manager restoration identifier and reconcile the peripherals/scanning state restored by iOS. Restoration support does not mean Nembra can promise relaunch or reconnect behavior in every force-quit, reboot, Bluetooth-toggle, or OS condition; those remain physical-device lifecycle tests.
- `setNotifyValue` may enable notifications or indications according to the discovered characteristic properties. If an acquisition callback cannot truthfully prove which GATT mechanism delivered a subscribed value, Nembra records `.subscriptionUpdate` rather than guessing.
- `didUpdateValueFor` can correspond to a requested read or to subscribed value changes. The adapter must carry enough request/subscription context to classify `.readResponse` versus `.subscriptionUpdate` truthfully.
- Encryption-required characteristic properties are preserved as evidence. They do not prove that Nembra has authenticated, paired, or successfully subscribed to the physical ES80.

Relevant Apple references:
- https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/scanforperipherals(withservices:options:)
- https://developer.apple.com/documentation/corebluetooth/core-bluetooth-background-processing-for-ios-apps
- https://developer.apple.com/documentation/corebluetooth/cbcentralmanageroptionrestoreidentifierkey
- https://developer.apple.com/documentation/corebluetooth/cbcentralmanagerdelegate/centralmanager(_:willrestorestate:)
- https://developer.apple.com/documentation/corebluetooth/cbperipheral/setnotifyvalue(_:for:)
- https://developer.apple.com/documentation/corebluetooth/cbperipheraldelegate/peripheral(_:didupdatevaluefor:error:)

## Capture truth rules

1. Preserve raw bytes. Do not replace a payload with a decoded interpretation.
2. Preserve standard discovery metadata when the acquisition platform exposes it; absence in one capture means only that it was not observed/provided in that capture.
3. Unknown UUIDs/values remain unknown rather than being normalized to a guessed Tuya meaning.
4. Stock-app observations are correlation markers, not decoded protocol facts.
5. Monotonic uptime is the ordering clock. Wall-clock dates are correlation metadata and cannot repair event order.
6. Imported capture artifacts must be revalidated for nested evidence validity plus sequence/uptime ordering; Codable decoding is not a trust boundary.
7. Disconnects, Bluetooth transitions, process restarts, and observer restarts create explicit continuity breaks.
8. A capture session is tied to a vehicle identity, but the current ES80 profile identity does not assert a verified protocol family implementation.
9. Parser/decoder output should later live beside raw evidence rather than overwrite it.
10. Software/Simulator fixtures never become real-hardware verification.

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

A future CoreBluetooth acquisition adapter may feed this model, but it must preserve the same evidence boundaries and must not quietly add vehicle writes.
