# AOVOPRO ES80 Passive Bluetooth Capture

Status: software capture/evidence model plus public-first capture strategy. No real AOVOPRO ES80 BLE identity, GATT mapping, data point mapping, authentication, framing, or command semantics are verified by this document unless explicitly marked as direct physical/app observation elsewhere in the project.

## Purpose

Nembra needs a durable way to record raw Bluetooth evidence from the physical AOVOPRO ES80 without guessing protocol meanings or adding motorized-vehicle writes. Public and official research should first narrow what to look for; physical capture then decides which candidate family, UUID, payload, and semantic actually apply to the target scooter.

The core capture artifact therefore records:
- advertisements and their raw manufacturer/service bytes
- advertised service UUIDs, overflow service UUIDs, solicited service UUIDs, connectability, RSSI, local name, and transmit-power metadata when iOS supplies them
- discovered services
- discovered characteristics and advertised properties, including notification/indication encryption requirements
- notification, indication, ambiguous subscribed-value, and explicitly requested read-response payloads
- stock-app state markers such as visibly displayed battery/electrical values
- explicit capture interruptions/continuity gaps
- strict process-local ordering using monotonic receipt uptime

The capture model deliberately contains no command/write event or encoder.

## Evidence classes used by this capture lane

- **VERIFIED PUBLIC FACT** — established by official AOVOPRO, Tuya, Apple, or another authoritative source, but not automatically a packet fact for the physical target.
- **PROBABLE FAMILY LEAD** — a technically specific public implementation or historical family artifact worth testing, but not sufficient to promote UUIDs/fields into ES80 truth.
- **DIRECT PHYSICAL / APP OBSERVATION** — behavior observed on the actual target/stock app, but still not automatically a decoded BLE field.
- **UNKNOWN PHYSICAL TARGET** — exact advertisement/GATT/DP/framing/semantics remain unknown until captured and correlated on the real scooter.

Public research is supposed to narrow the experiment. It must never silently upgrade a family lead into physical-target truth.

## Verified public facts that constrain the search

These facts are externally documented, but they do not by themselves prove the physical 2025 ES80's packet layout:

- AOVOPRO's official ES80 page explicitly identifies a **New 2025** ES80, lists a 36 V / 10.5 Ah battery, identifies the app as `AOVOPRO/Tuya Smart`, and says latest ES80/ESMAX production may be supplied with Tuya Smart for different market needs. Source: https://www.aovopro.com/product/aovopro-es80-electric-scooter-350w-10-5-ah-long-range-high-speed-foldable-electric-scooter/
- AOVOPRO's older official ES80 manual links the Android application package `com.zydtech.aovopro`. That is useful historical lineage evidence, not proof that the current Tuya-generation ES80 uses the same transport. Source: https://www.aovopro.com/wp-content/uploads/2020/08/AOVO-PRO-app-MANUAL-EN-FR-ES350W20200427.pdf
- Tuya's generic BLE data-point documentation describes DP payload fields including `dp_id`, `dp_type`, `dp_data_len`, and value bytes. Source: https://developer.tuya.com/en/docs/iot-device-dev/bluetooth_software_map_bt_dp_data?id=Kcmeae40r8zdq
- Tuya's current Ride Development Guide explicitly says feature identifiers/DP IDs depend on the product's configured DP list. Therefore Nembra must not assign an ES80 battery/speed/current/control DP merely because another Tuya product uses that number. Source: https://developer.tuya.com/en/docs/iot/mobility_development_guidelines?id=Kfme01kf7zw31
- Tuya's current BLE porting guide documents a modern Tuya service candidate `0xFD50`, with write-without-response characteristic `00000001-0000-1001-8001-00805F9B07D0`, notify characteristic `00000002-0000-1001-8001-00805F9B07D0`, optional read characteristic `00000003-0000-1001-8001-00805F9B07D0`, and documented advertisement/company data around `0xFD50` / company ID `0x07D0`. These are Tuya-platform fingerprints, not verified target-ES80 GATT facts. Source: https://developer.tuya.com/en/docs/iot-device-dev/Porting-Guide-BLE?id=Kam0xjtz4n6e0
- Apple's CoreBluetooth advertisement-data contract exposes standard metadata beyond the ordinary service UUID list, including overflow service UUIDs, solicited service UUIDs, transmit power, service data, manufacturer data, local name, and connectability when present. Nembra preserves these raw fields rather than silently dropping them. Source: https://developer.apple.com/documentation/corebluetooth/advertisement-data-retrieval-keys
- CoreBluetooth characteristic properties include notification/indication encryption requirements in addition to ordinary read/write/notify/indicate properties. Nembra records those as discovered capability metadata only. Source: https://developer.apple.com/documentation/corebluetooth/cbcharacteristicproperties
- CoreBluetooth uses `setNotifyValue(_:for:)` to subscribe to characteristic value changes; the characteristic-value callback is also used for explicitly requested reads. The acquisition layer must therefore track operation context and must not infer protocol meaning merely because bytes arrived in that callback. Sources: https://developer.apple.com/documentation/corebluetooth/cbperipheral/setnotifyvalue(_:for:) and https://developer.apple.com/documentation/corebluetooth/cbperipheraldelegate/peripheral(_:didupdatevaluefor:error:)
- Apple's current CoreBluetooth overview documents an iOS 26+ Live Activity behavior: when an app already has an instantiated `CBManager` and starts a Live Activity before entering background, certain Bluetooth activities may continue with foreground-like privileges, including scans without service UUIDs and scans with duplicate filtering disabled. This is a platform capability, not proof of guaranteed ES80 discovery/reconnect in every lifecycle condition. Source: https://developer.apple.com/documentation/corebluetooth

## Probable historical ZYDTECH family lead

A public open-source project, `Ennar1991/ZydDash`, reverse engineered an ePowerFun scooter using a ZYDTECH HW9027-or-similar controller/display family. This is not an ES80 implementation and must not be imported as one. It is nevertheless a technically important **PROBABLE FAMILY LEAD** because the historical official AOVOPRO Android package itself uses the `com.zydtech.aovopro` namespace.

ZydDash documents, for its ePowerFun/ZYDTECH target:
- high-level service family beginning `F2F0`, with `F2F1` transmit and `F2F2` receive characteristics;
- low-level service family beginning `F1F0`, with `F1F1` client-transmit and `F1F2` client-receive characteristics;
- MODBUS-like payloads with a CRC;
- 25-byte telemetry packets containing fields interpreted by that project as SoC, speed, voltage, signed current, temperature, trip distance, and total distance;
- vendor/address lead bytes such as `AF`, `AB`, or `A5` on related implementations.

Sources:
- https://github.com/Ennar1991/ZydDash
- https://github.com/Ennar1991/ZydDash/blob/main/BLE_Telemetry.md
- https://github.com/Ennar1991/ZydDash/blob/main/code/ePF1_gatt.py

### Critical safety distinction

The ZydDash sample does **not** simply receive all telemetry passively. Its example subscribes to `F1F2` and periodically writes `0xAA` to `F1F1` to trigger response bursts. That write behavior is **not authorized for Nembra's target ES80**.

For the Nembra target, `F1F0/F1F1/F1F2/F2F0/F2F1/F2F2`, `AF/AB/A5`, 25-byte packet shapes, CRC behavior, field offsets, scales, and the `0xAA` trigger are all only historical-family fingerprints until the physical 2025 scooter proves otherwise.

The first ES80 capture may passively **look for** those services/characteristics and record their advertised properties. It must not send the ZydDash trigger merely because the UUIDs look familiar.

## Modern Tuya versus historical ZYDTECH fingerprint decision

Public research now gives the first physical discovery session a concrete decision tree without requiring any guessed write:

### Candidate A — modern Tuya generation

Evidence that would support this path includes observed `FD50`, the documented modern Tuya characteristic family, Tuya-formatted service/manufacturer data, or another clearly identified Tuya transport on the physical scooter.

If observed:
1. capture the entire advertisement and GATT tree rather than filtering only to expected UUIDs;
2. record characteristic properties/security requirements;
3. subscribe/read only where the API/device legitimately allows it and where doing so is non-mutating;
4. correlate raw value changes with the stock app's visible battery/electrical/speed state;
5. determine actual product DP IDs, scales, signedness, cadence, and derivation from physical evidence;
6. do not transplant generic Tuya example DP numbers into production.

### Candidate B — historical ZYDTECH-like generation

Evidence that would support further investigation includes observed `F1F0/F2F0` service families and matching `F1F1/F1F2/F2F1/F2F2` characteristic structure.

If observed:
1. record the GATT tree and any unsolicited/subscribed updates first;
2. compare packet lengths/headers with the public family lead only as an offline hypothesis;
3. do not send `0xAA`, AT commands, speed/config packets, lock/light packets, or MODBUS-like requests during the passive phase;
4. promote field offsets/scales only after the target's own packets and stock-app values correlate repeatedly;
5. treat any need for a request/trigger write as a new safety gate, not part of passive capture.

### Candidate C — neither family appears

Remain protocol-agnostic. Capture every observed advertisement/service/characteristic/property/value that can be collected non-mutatingly and classify the transport as unknown. Do not force the target into either public family.

This decision tree is intentionally asymmetric: public fingerprints can tell Nembra **where to look**, but only physical evidence can tell Nembra **what is true**.

## Current user-visible target behavior

The physical ES80 used for Nembra development has been observed with a stock Tuya UI that displays a numeric battery percentage. Additional current-target app/public research is maintained in its own worker lane so this capture-model document does not duplicate or compete with that research surface.

A numeric stock-app percentage proves only that a user-facing value exists somewhere in the stock stack. It does not prove that the scooter directly transmits a true 1%-resolution state-of-charge value. Likewise, a stock-app voltage/current/power display would not by itself prove separate raw DPs or an independently transmitted power field.

## Unknown on the physical target until captured

- advertisement local name, service data, manufacturer data, overflow/solicited UUIDs, and transmit-power metadata
- whether `FD50`, `1910`, `F1F0/F2F0`, or another service family is actually present
- all service and characteristic UUIDs
- characteristic read/write/notify/indicate properties and security requirements
- pairing/authentication/session behavior
- whether payloads are encrypted or wrapped before useful DP/data fields are exposed
- battery percentage raw source/resolution/cadence/derivation
- voltage raw source/scale/cadence and load/rest behavior
- current raw source/scale/signedness/cadence if exposed
- whether wattage/power is independently reported or derived from voltage × current
- charging-state source
- speed source/cadence/latency/jitter/resolution
- odometer/trip values and scaling
- ride-mode/control identifiers and semantics
- command acknowledgement behavior
- packet framing/checksum used by this ES80 batch
- stable per-physical-scooter identity suitable for learned-range persistence
- firmware/hardware/batch differences

Generic Tuya examples and historical ZYDTECH packet layouts must never be promoted to target-ES80 protocol truth without matching physical evidence.

## Safety boundary

Public-first passive research follows:

`official/public research → discover → enumerate → subscribe/read → capture → correlate → decode → validate`

Do not send random bytes to the scooter. Do not send a public project's request/trigger bytes merely to see what happens. A future write path is a separate gate and requires known target characteristic/framing, known semantic, known safe range, understood acknowledgement/state confirmation, parser/encoder tests, and cautious stationary/unloaded validation where appropriate.

Recording that a characteristic advertises `.write` or `.writeWithoutResponse` is observational metadata only. It is not authorization to invoke it.

## CoreBluetooth acquisition constraints

The platform-neutral capture model is intentionally broader than one acquisition adapter, but a future iOS adapter must preserve current CoreBluetooth semantics rather than hiding them:

- In ordinary foreground discovery, `scanForPeripherals(withServices:nil, ...)` can discover peripherals regardless of advertised services, though Apple recommends providing service UUIDs when known.
- Initial physical ES80 research should use broad foreground discovery because assuming only `FD50` or only ZYDTECH-family UUIDs could hide the other batch/protocol family.
- The conventional `bluetooth-central` background-scan path requires explicit service UUIDs. Current iOS 26+ CoreBluetooth also documents a separate Live Activity exception: if the app has an instantiated `CBManager` and starts a Live Activity before backgrounding, the manager can retain foreground-like privileges for certain Bluetooth activities, including unfiltered scans. Nembra must treat these as distinct lifecycle modes instead of collapsing them into one generic promise.
- Even with the Live Activity behavior, Nembra must not promise perpetual scanning/reconnect across force-quit, reboot, permission changes, Bluetooth toggles, process eviction, or every OS scheduling condition. Those remain physical-device lifecycle tests.
- A scene-based app that later adopts CoreBluetooth state preservation/restoration should use a stable central-manager restoration identifier and reconcile the peripherals/scanning state restored by iOS. Restoration support is complementary to, not a substitute for, verified ES80 identity and lifecycle testing.
- `setNotifyValue` may enable notifications or indications according to discovered characteristic properties. If an acquisition callback cannot truthfully prove which GATT mechanism delivered a subscribed value, Nembra records `.subscriptionUpdate` rather than guessing.
- `didUpdateValueFor` can correspond to a requested read or to subscribed value changes. The adapter must carry enough request/subscription context to classify `.readResponse` versus `.subscriptionUpdate` truthfully.
- Encryption-required characteristic properties are preserved as evidence. They do not prove that Nembra has authenticated, paired, or successfully subscribed to the physical ES80.

Relevant Apple references:
- https://developer.apple.com/documentation/corebluetooth
- https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/scanforperipherals(withservices:options:)
- https://developer.apple.com/documentation/corebluetooth/core-bluetooth-background-processing-for-ios-apps
- https://developer.apple.com/documentation/corebluetooth/cbcentralmanageroptionrestoreidentifierkey
- https://developer.apple.com/documentation/corebluetooth/central-manager-state-restoration-options
- https://developer.apple.com/documentation/corebluetooth/cbperipheral/setnotifyvalue(_:for:)
- https://developer.apple.com/documentation/corebluetooth/cbperipheraldelegate/peripheral(_:didupdatevaluefor:error:)

## Capture truth rules

1. Preserve raw bytes. Do not replace a payload with a decoded interpretation.
2. Preserve standard discovery metadata when the acquisition platform exposes it; absence in one capture means only that it was not observed/provided in that capture.
3. Unknown UUIDs/values remain unknown rather than being normalized to a guessed Tuya or ZYDTECH meaning.
4. Public protocol implementations are hypotheses/fingerprints until the target scooter matches them.
5. Stock-app observations are correlation markers, not decoded protocol facts.
6. Monotonic uptime is the ordering clock. Wall-clock dates are correlation metadata and cannot repair event order.
7. Imported capture artifacts must be revalidated for nested evidence validity plus sequence/uptime ordering; Codable decoding is not a trust boundary.
8. Disconnects, Bluetooth transitions, process restarts, and observer restarts create explicit continuity breaks.
9. A capture session is tied to a vehicle identity, but the current ES80 profile identity does not assert a verified protocol family implementation.
10. Parser/decoder output should later live beside raw evidence rather than overwrite it.
11. Software/Simulator fixtures never become real-hardware verification.
12. A request that appears harmless in a different ZYDTECH/Tuya scooter is still a motorized-hardware write until verified for this exact target.

## Battery/electrical investigation workflow

For the battery/range requirement, collect longer sessions with deliberate stock-app correlation markers such as:
- battery percentage before riding
- battery percentage after meaningful riding windows
- voltage/current/power displays when available in the target stock app
- values while accelerating versus stopped/rested
- reconnect observations
- charging/unplugged transitions when available
- low-battery behavior

Then correlate changes against raw notifications/read responses and discovered GATT structure. Do not select the adaptive-range model's authoritative SoC source or minimum useful percentage window until the physical ES80 evidence supports it.

If current/power become raw verified telemetry later, that still does not authorize immediate `Wh/mi`: Nembra must first verify units, signedness, source semantics, cadence, gaps, time integration, and trustworthy distance coverage.

## Software artifact

`PassiveBluetoothCaptureSession` is intentionally platform-neutral and Codable so physical-device tooling can export raw observations for offline parser/tests. JSON export is schema-versioned, preserves sub-second wall-clock correlation metadata, and keeps monotonic uptime as the ordering authority.

The current model records only non-mutating value origins:
- notification, when the acquisition source can prove it
- indication, when the acquisition source can prove it
- subscribed-value update when the acquisition API cannot truthfully distinguish notification from indication
- read response

A future CoreBluetooth acquisition adapter may feed this model, but it must preserve the same evidence boundaries and must not quietly add vehicle writes.
