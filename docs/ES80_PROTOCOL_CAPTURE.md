# AOVOPRO ES80 Passive Bluetooth Capture

Status: software capture/evidence model plus public-first capture strategy. No raw BLE/GATT/DP mapping or motorized command semantic is verified on the physical AOVOPRO ES80 by this document.

## Canonical research inputs

This document owns the **capture/evidence boundary**, not the full protocol-research ledger.

Use the merged research on `main` as the current candidate source:
- `docs/ES80_PUBLIC_RESEARCH.md` — current 2025 ES80/Tuya product and stock-app evidence, evidence taxonomy, telemetry questions, and physical-validation gaps.
- `docs/ES80_TUYA_TRANSPORT_RESEARCH.md` — current Tuya BLE transport/framing research, including separation between phone↔device GATT transport and Tuya MCU serial framing.
- `docs/ES80_TUYA_REVERSE_ENGINEERING_CANDIDATES.md` — corroborated decoder/transport candidates that remain candidates until the target scooter matches them.

Historical ZYDTECH-family evidence remains useful as a **family fingerprint**, especially because the older official AOVOPRO Android package used `com.zydtech.aovopro`, but it must not outrank the merged current-generation Tuya research for the 2025 target.

GitHub/current merged research wins if one of the candidate details below becomes stale.

## Purpose

Nembra needs a durable way to record raw Bluetooth evidence from the physical AOVOPRO ES80 without guessing meanings or accidentally turning protocol research into a scooter-control path.

Public/official research narrows what to look for. Physical capture decides what is actually present on this scooter.

The capture artifact preserves:
- raw advertisements and manufacturer/service bytes;
- local name, RSSI, connectability, advertised service UUIDs, overflow UUIDs, solicited UUIDs, service data, and transmit-power metadata when iOS provides them;
- discovered services and whether they are primary;
- **included-service relationships**, so the GATT tree is not flattened into a misleading service list;
- discovered characteristics and their advertised properties/security requirements;
- **descriptor UUID discovery**, without pretending arbitrary `CBDescriptor.value` objects have a universal lossless string encoding;
- non-mutating notification, indication, ambiguous subscribed-value, and requested read-response bytes;
- stock-app correlation markers;
- explicit continuity interruptions;
- strict process-local ordering using monotonic receipt uptime;
- a versioned JSON envelope for durable/offline analysis.

The model deliberately contains **no command/write event and no command encoder**.

## Evidence classes

Use the repository's current evidence taxonomy. For this capture lane the important distinction is:

- **DIRECT PHYSICAL / APP OBSERVATION** — observed on the target scooter/stock app, but not automatically a decoded BLE field.
- **VERIFIED PUBLIC / GENERIC TUYA FACT** — documented behavior of the product family/platform, but not automatically target-packet truth.
- **CORROBORATED / PROBABLE FAMILY LEAD** — specific public implementation or historical family artifact worth testing.
- **UNKNOWN / PHYSICAL VERIFICATION REQUIRED** — exact target advertisement/GATT/DP/framing/semantic remains unresolved.

A family fingerprint can tell Nembra where to look. Only target evidence can promote it to physical truth.

## Direct target/app observations to correlate

The current target's stock Tuya-facing experience has directly exposed user-visible electrical values including:
- battery percentage;
- pack voltage;
- current/amps;
- watts/power.

Those displays are valuable correlation anchors. They do **not** prove:
- that each value is independently transmitted by the scooter;
- that the displayed wattage is not derived from voltage × current;
- the BLE characteristic or Tuya DP carrying a value;
- the DP ID, type, scale, signedness, cadence, resolution, filtering, or charging semantics;
- that the displayed battery percentage is a raw 1%-resolution SoC packet.

`docs/ES80_PUBLIC_RESEARCH.md` is the canonical current-target evidence source for these observations and questions.

## Candidate transport fingerprints

The first broad discovery session must not filter the target into one assumed family.

### Current Tuya candidates

The merged Tuya transport research documents current candidate fingerprints such as the modern `FD50` family and corroborated legacy Tuya candidates. Treat those UUIDs/framing rules as **search/correlation candidates only** until observed on the physical ES80.

If a Tuya candidate appears:
1. preserve the entire advertisement and GATT topology;
2. record services, included-service edges, characteristics, descriptors, and characteristic properties;
3. subscribe/read only where doing so is non-mutating and semantically legitimate;
4. retain raw bytes before decoding;
5. correlate against stock-app battery/voltage/current/power/speed/trip/ODO behavior;
6. determine actual product-specific DP IDs, types, scales, signedness, cadence, reassembly/decryption behavior, and derivation from target evidence;
7. never transplant an example Tuya DP number into production merely because another Tuya mobility product uses it.

### Historical ZYDTECH-family candidate

Independent project `Ennar1991/ZydDash` reverse engineered a different ZYDTECH-based scooter and documents F1/F2 GATT families, MODBUS-like CRC packets, and telemetry fields interpreted as SoC/speed/voltage/signed current/temperature/trip/ODO.

This remains a **historical-family lead**, not a 2025 ES80 implementation.

Critical safety fact: its example writes `0xAA` to a transmit characteristic to trigger telemetry bursts. Nembra must **not** copy that trigger into the passive target-ES80 phase merely because similar UUIDs appear.

If F1/F2-like services appear on the target, record their structure and any naturally available non-mutating evidence first. Any request/trigger write becomes a separate safety gate.

### Neither family appears

Remain protocol-agnostic. Capture the observed structure and bytes. Do not force the target into either Tuya or historical ZYDTECH assumptions.

## Unknown on the physical ES80 until captured

Still unknown/physical-verification-required includes:
- actual advertisement identity and manufacturer/service data;
- actual GATT services, included-service topology, characteristics, descriptors, and properties;
- pairing/authentication/session behavior;
- whether current Tuya candidate services/characteristics are present;
- whether historical ZYDTECH-family services are present;
- battery raw source/resolution/cadence/derivation;
- voltage raw source/scale/cadence and sag/recovery behavior;
- current raw source/scale/signedness/cadence;
- whether wattage is independently transmitted or derived;
- charging state;
- speed source/cadence/latency/jitter/resolution;
- trip/odometer source and scaling;
- product-specific DP IDs/types/scales;
- packet reassembly/decryption/framing behavior on this exact target;
- command semantics and acknowledgements;
- stable per-physical-scooter identity suitable for learned-range persistence;
- firmware/hardware/batch differences.

## Safety boundary

Public-first passive research follows:

`official/public research → discover → enumerate → subscribe/read → capture → correlate → decode → validate`

Do not send random bytes to the scooter.

Do not send a public project's trigger/request merely to see what happens.

A future write path is a separate gate and requires, for the exact target:
- known characteristic/transport;
- known framing/reassembly/encryption expectations;
- known semantic and valid value range;
- understood acknowledgement/state confirmation;
- parser/encoder tests;
- cautious stationary/unloaded validation where appropriate.

Recording that a characteristic advertises `.write` or `.writeWithoutResponse` is observational metadata only. It is never authorization to invoke it.

## CoreBluetooth acquisition constraints

A future iOS acquisition adapter must preserve CoreBluetooth semantics rather than hiding uncertainty:

- Initial target research should use broad foreground discovery so a preselected Tuya or ZYDTECH UUID list cannot hide the actual batch/protocol family.
- Preserve all standard advertisement metadata that iOS supplies.
- Discover services, included services, characteristics, and descriptor UUIDs rather than flattening the GATT tree.
- `setNotifyValue` may result in notifications or indications according to characteristic behavior/properties. If the acquisition callback cannot prove which GATT mechanism delivered a subscribed value, record `.subscriptionUpdate` rather than guessing.
- `didUpdateValueFor` can represent a requested read or subscribed update. The adapter must keep enough operation context to classify `.readResponse` versus `.subscriptionUpdate` truthfully.
- Descriptor discovery is evidence. Arbitrary descriptor values are **not** currently forced through a generic string/Data representation. Add typed descriptor-value evidence only when a trustworthy codec exists for the value actually returned.
- Encryption-required characteristic properties are evidence only; they do not prove Nembra authenticated, paired, or subscribed successfully.
- The conventional `bluetooth-central` background path and the newer iOS 26+ Live Activity Bluetooth behavior are distinct lifecycle modes. Neither should be turned into a promise of perpetual ES80 scanning/reconnect across force-quit, reboot, permission changes, Bluetooth toggles, process eviction, or every scheduler condition.

Relevant Apple APIs include:
- `CBCentralManager.scanForPeripherals(withServices:options:)`
- `CBPeripheral.discoverServices(_:)`
- `CBPeripheral.discoverIncludedServices(_:for:)`
- `CBPeripheral.discoverCharacteristics(_:for:)`
- `CBPeripheral.discoverDescriptors(for:)`
- `CBPeripheral.setNotifyValue(_:for:)`
- `CBPeripheralDelegate.peripheral(_:didUpdateValueFor:error:)`

## Capture truth rules

1. Preserve raw evidence before interpretation.
2. Preserve standard advertisement and complete discovered GATT topology when the platform exposes it.
3. Absence in one capture means only that the value/structure was not observed or provided in that capture.
4. Unknown identifiers/values remain unknown; do not normalize them into guessed Tuya or ZYDTECH meanings.
5. Public implementations and decoder candidates are hypotheses until the physical target matches them.
6. Stock-app values are correlation markers, not decoded BLE facts.
7. Monotonic uptime is the ordering clock; wall-clock timestamps are correlation metadata only.
8. Imported capture artifacts revalidate nested evidence and sequence/uptime ordering; Codable decoding is not a trust boundary.
9. Disconnects, Bluetooth transitions, process restarts, and observer restarts create explicit continuity breaks.
10. Descriptor UUID discovery is preserved, but arbitrary descriptor values are not fabricated/stringified.
11. Parser/decoder output should live beside raw evidence rather than overwrite it.
12. Software/Simulator fixtures never become real-hardware verification.
13. A request harmless on another Tuya/ZYDTECH scooter is still a motorized-hardware write until proven for this exact ES80.

## Battery/electrical correlation workflow

For adaptive range and battery truth, collect longer physical sessions with deliberate stock-app markers such as:
- battery percentage before/after meaningful consumption windows;
- voltage/current/power displays at matching moments;
- accelerating versus stopped/rested behavior;
- reconnect observations;
- charging/unplugged transitions;
- low-battery behavior;
- speed/trip/ODO values when visible.

Correlate those markers against raw BLE evidence without letting UI presentation become telemetry truth.

Do not select the adaptive-range estimator's authoritative SoC source, useful consumption window, voltage interpretation, or energy model until the physical ES80 evidence supports it.

If current/power later become verified raw telemetry, that still does not automatically authorize `Wh/mi`: Nembra must first verify units, signedness, cadence, gaps, time integration, and trustworthy distance coverage.

## Software artifact

`PassiveBluetoothCaptureSession` is platform-neutral and Codable so physical-device tooling can export evidence for offline parser/tests.

The JSON envelope is schema-versioned, preserves sub-second wall-clock correlation metadata, and keeps monotonic uptime as the ordering authority.

Current non-mutating characteristic value origins are:
- notification, when proven by the acquisition source;
- indication, when proven by the acquisition source;
- subscribed-value update when the acquisition API cannot truthfully distinguish notification from indication;
- requested read response.

A future CoreBluetooth acquisition adapter may feed this model, but it must preserve these evidence boundaries and must not quietly add vehicle writes.
