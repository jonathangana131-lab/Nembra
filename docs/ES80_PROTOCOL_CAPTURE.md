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
- structured connection callbacks for connected, failed-to-connect, and disconnected states;
- optional platform-supplied disconnect timestamp and reconnecting state **separate from** Nembra's callback-receipt clocks;
- stable transport error evidence as domain/code rather than localized text;
- discovered services and whether they are primary;
- **included-service relationships**, so the GATT tree is not flattened into a misleading service list;
- discovered characteristics and their advertised properties/security requirements;
- deterministic exported ordering of characteristic-property metadata even though the in-memory API uses a `Set`;
- **descriptor UUID discovery**, without pretending arbitrary `CBDescriptor.value` objects have a universal lossless string encoding;
- value-subscription callback evidence including known request context, resulting notification state, and transport error evidence;
- non-mutating notification, indication, ambiguous subscribed-value, and requested read-response bytes;
- stock-app correlation markers;
- explicit continuity interruptions plus structured disconnect continuity boundaries;
- strict monotonic receipt ordering; the current iOS acquisition source uses system-boot-relative `DispatchTime` uptime, so a physical device reboot starts a new capture session;
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

- Initial target research should use broad foreground discovery so a preselected Tuya or ZYDTECH UUID list cannot hide the actual batch/protocol family. Broad discoveries are a candidate catalog; they must not all be appended into one session already labeled as the selected ES80.
- Preserve all standard advertisement metadata that iOS supplies.
- Record `didConnect`, `didFailToConnect`, and disconnect callbacks as structured connection evidence rather than reducing them to diagnostic strings.
- Keep callback receipt `Date`/monotonic uptime separate from any platform-supplied disconnect event timestamp. Preserve `isReconnecting` only when the callback/API actually supplies it; `nil` means unknown/not supplied, not false.
- The current iOS adapter's `DispatchTime.now().uptimeNanoseconds` source is system-boot-relative. An app-process restart on the same boot does not reset that clock, but it is still an observation gap and should be marked when a session is legitimately resumed. A physical device reboot resets the clock and starts a new `PassiveBluetoothCaptureSession`; do not allow wall-clock time to repair cross-reboot ordering.
- Preserve stable error domain/code when CoreBluetooth supplies an error. Do not use localized error descriptions as durable protocol evidence.
- Discover services, included services, characteristics, and descriptor UUIDs rather than flattening the GATT tree.
- `setNotifyValue` is subscription configuration, not a scooter command acknowledgement. The acquisition adapter should track the requested enable/disable state when it can do so without ambiguity, then record the corresponding `didUpdateNotificationStateFor` callback with the resulting `isNotifying` state and error evidence.
- `setNotifyValue` may result in notifications or indications according to characteristic behavior/properties. If the acquisition callback cannot prove which GATT mechanism delivered a subscribed value, record `.subscriptionUpdate` rather than guessing.
- `didUpdateValueFor` can represent a requested read or subscribed update. The adapter must keep enough operation context to classify `.readResponse` versus `.subscriptionUpdate` truthfully.
- Descriptor discovery is evidence. Arbitrary descriptor values are **not** currently forced through a generic string/Data representation. Add typed descriptor-value evidence only when a trustworthy codec exists for the value actually returned.
- Encryption-required characteristic properties are evidence only; they do not prove Nembra authenticated, paired, or subscribed successfully.
- A structured `.connection(.disconnected)` event is a byte-continuity boundary for offline analysis. `PassiveBluetoothCaptureEvent.breaksByteContinuity` is the domain predicate consumers should use. Generic `.interruption` events cover other known gaps such as Bluetooth transitions, observer/app-process restarts within the same boot, or continuity loss not already represented by a disconnect callback.
- The conventional `bluetooth-central` background path and the newer iOS 26+ Live Activity Bluetooth behavior are distinct lifecycle modes. Neither should be turned into a promise of perpetual ES80 scanning/reconnect across force-quit, reboot, permission changes, Bluetooth toggles, process eviction, or every scheduler condition.

Relevant Apple APIs include:
- `CBCentralManager.scanForPeripherals(withServices:options:)`
- `CBCentralManagerDelegate.centralManager(_:didConnect:)`
- `CBCentralManagerDelegate.centralManager(_:didFailToConnect:error:)`
- CoreBluetooth disconnect delegate callbacks, including the newer timestamp/reconnecting-state form where available;
- `CBPeripheral.discoverServices(_:)`
- `CBPeripheral.discoverIncludedServices(_:for:)`
- `CBPeripheral.discoverCharacteristics(_:for:)`
- `CBPeripheral.discoverDescriptors(for:)`
- `CBPeripheral.setNotifyValue(_:for:)`
- `CBPeripheralDelegate.peripheral(_:didUpdateNotificationStateFor:error:)`
- `CBPeripheralDelegate.peripheral(_:didUpdateValueFor:error:)`

## Capture truth rules

1. Preserve raw evidence before interpretation.
2. Preserve standard advertisement and complete discovered GATT topology when the platform exposes it.
3. Absence in one capture means only that the value/structure was not observed or provided in that capture.
4. Unknown identifiers/values remain unknown; do not normalize them into guessed Tuya or ZYDTECH meanings.
5. Public implementations and decoder candidates are hypotheses until the physical target matches them.
6. Stock-app values are correlation markers, not decoded BLE facts.
7. Monotonic uptime is the callback-receipt ordering clock. In the current iOS acquisition path it is system-boot-relative, not process-relative; wall-clock receipt timestamps and platform-supplied event timestamps are distinct metadata and must not be substituted for it. Device reboot starts a new capture session.
8. Durable artifacts go through `PassiveBluetoothCaptureJSON`; the in-memory session intentionally does not conform to `Codable`, so callers cannot bypass the versioned envelope. Imported artifacts revalidate nested evidence plus sequence/uptime ordering.
9. Structured connection events preserve callback state. `.connection(.disconnected)` and `.interruption(...)` are byte-continuity boundaries through `breaksByteContinuity`; connected/failed/subscription events are not automatically gaps.
10. Subscription request/result evidence describes CoreBluetooth value-update configuration only. It does not prove app authentication, a Tuya session, telemetry semantics, or a vehicle command acknowledgement.
11. Descriptor UUID discovery is preserved, but arbitrary descriptor values are not fabricated/stringified.
12. Parser/decoder output should live beside raw evidence rather than overwrite it.
13. Software/Simulator fixtures never become real-hardware verification.
14. A request harmless on another Tuya/ZYDTECH scooter is still a motorized-hardware write until proven for this exact ES80.

## JSON schema and recovery

The current writer emits capture schema **v2** because structured connection and subscription event cases extend the durable event vocabulary.

The current decoder accepts both:
- **v1** — original advertisement/GATT/value/marker/interruption evidence;
- **v2** — v1 plus structured connection lifecycle and subscription result/state evidence.

The schema number is authoritative for the artifact grammar. A v1-labeled artifact containing a v2-only `.connection` or `.subscription` event fails closed instead of being silently decoded with the current enum. Unknown future schema versions also fail closed.

This is one-way compatibility: current tooling can continue reading genuine v1 artifacts rather than discarding historical raw evidence. A v1 implementation is not expected to understand newly authored v2 event cases.

The only supported durable serialization surface is `PassiveBluetoothCaptureJSON`. `PassiveBluetoothCaptureSession` remains platform-neutral in memory but is intentionally **not `Codable`**; this prevents long-lived unversioned evidence files from being accidentally created through direct `JSONEncoder().encode(session)` calls.

Characteristic properties remain a `Set` in memory for truthful set semantics, but the versioned encoder writes them in deterministic raw-value order so semantically identical captures do not produce hash-order noise across processes.

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

`PassiveBluetoothCaptureSession` is the platform-neutral in-memory evidence model. Physical-device tooling exports/imports durable evidence only through `PassiveBluetoothCaptureJSON`, whose schema-versioned envelope owns migration and validation.

The JSON envelope preserves sub-second wall-clock callback-receipt metadata, keeps monotonic uptime as the receipt-ordering authority within one device boot, stores any platform-supplied disconnect timestamp as separate evidence, rejects event vocabulary that contradicts the declared schema, and deterministically orders characteristic-property arrays.

Current non-mutating characteristic value origins are:
- notification, when proven by the acquisition source;
- indication, when proven by the acquisition source;
- subscribed-value update when the acquisition API cannot truthfully distinguish notification from indication;
- requested read response.

A future CoreBluetooth acquisition adapter may feed this model, but it must preserve these evidence boundaries and must not quietly add vehicle writes.
