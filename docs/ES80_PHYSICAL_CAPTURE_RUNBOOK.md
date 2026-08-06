# 2025 AOVOPRO ES80 Passive Physical Capture Runbook

Status: **prepared software procedure; physical target capture not yet performed**.

Target: Nembra's newer **2025-generation AOVOPRO ES80**, using the current/Tuya-generation stock-app path.

Directly observed on the physical target's stock app:

- battery percentage;
- live voltage;
- live amps/current;
- live wattage/power.

Those displays are trusted as **stock-app behavior**. Their raw Bluetooth/Tuya source, DP IDs/types/scales, cadence, signedness, current meaning, and whether wattage is independently transmitted versus derived remain unverified until the sessions below produce physical evidence.

## Software prerequisite

The isolated `NembraBluetoothCapture` package contains the passive acquisition/evidence tooling required for these sessions:

- broad first-fingerprint foreground scan;
- explicit peripheral selection;
- connect timeout/cancellation;
- complete service / included-service / characteristic / descriptor discovery;
- reads only where `.read` is advertised;
- subscriptions only where `.notify` / `.indicate` is advertised;
- immutable raw value callback recording;
- monotonic ordering + explicit interruption boundaries;
- manual stock-app correlation markers;
- versioned JSON export;
- per-peripheral transport candidate reports;
- raw callback-stream cadence statistics;
- controlled-session byte/statistics comparison.

The package also has a reusable `ES80PassiveCaptureResearchView`, but it is intentionally **not production-app wired yet**. App integration must wait for the parent passive-evidence PR to land and must add the proper Bluetooth privacy-purpose description before a physical iPhone run.

No package API sends an application characteristic value. CI fails if `.writeValue(...)` appears in the passive package source.

## Hard safety rules

1. Do not send random writes to the scooter.
2. Do not copy writable DP IDs from another Tuya scooter/product and test them on the ES80.
3. Do not use historical ZYDTECH `0xAA` telemetry-trigger writes during the passive target-ES80 phase.
4. Discover/read/subscribe only according to real GATT properties.
5. Treat CoreBluetooth write capability as metadata, never command authorization.
6. Treat all FD50/A201/1910/F1/F2 findings as candidate fingerprints until the physical scooter proves them.
7. Keep raw GATT callback boundaries immutable; derived Tuya reassembly/decryption happens later.
8. Do not publish Tuya local keys, auth keys, session keys, account tokens, or unrelated device credentials in capture JSON/GitHub artifacts.
9. Do not claim Nembra intercepted another app's Bluetooth session. CoreBluetooth gives Nembra its own central-session traffic, not raw over-the-air packets from Tuya Smart.

## Session 0 — preparation

Before the first scan:

- scooter safely stationary;
- drive wheel unloaded only if later wheel-spin observation is genuinely needed and mechanically safe;
- no unknown Nembra commands enabled;
- Bluetooth enabled;
- record scooter/app/firmware identifiers visible in legitimate UI where available;
- note approximate battery percentage from the stock app;
- note whether charger is connected;
- ensure only one physical ES80 is intentionally being tested.

If another nearby Tuya device exists, leave it alone. The capture tooling deliberately fingerprints each CoreBluetooth peripheral separately so a nearby FD50/A201 advertisement cannot become ES80 evidence.

## Session A — advertisement + GATT fingerprint

Goal: establish the physical 2025 ES80's real Bluetooth identity/topology without assuming a protocol family.

Procedure:

1. Start an explicit foreground research scan with duplicate advertisements **off** initially.
2. Observe discovered peripherals and record:
   - CoreBluetooth peripheral UUID;
   - local name, including no-name state;
   - RSSI;
   - connectability;
   - manufacturer data;
   - service data;
   - advertised / overflow / solicited service UUIDs;
   - Tx power if exposed.
3. Select the likely scooter only from physical correlation, not name similarity alone.
4. Connect to that exact observed peripheral.
5. Let the controller discover every service, included service, characteristic property, and descriptor UUID.
6. Allow passive reads/subscriptions according to advertised properties.
7. Capture at least 30–60 seconds stationary.
8. Export versioned JSON.

Questions answered:

- Does the target expose FD50, A201, 1910, a ZYDTECH-like family, or something else?
- Which characteristics are read / notify / indicate / write-capable?
- Is there an obvious high-frequency subscribed value stream while stationary?
- Does GATT topology change after connection?

Acceptance wording:

- `OBSERVED ON PHYSICAL 2025 ES80: <advertisement/GATT fact>` only after this session.
- Do **not** call a service `the battery service` merely because a researched candidate matched.

## Session B — reconnect / initial state synchronization

Goal: catch the state burst/query behavior most likely to expose current battery/electrical state.

Procedure:

1. End Session A cleanly and keep its JSON immutable.
2. Start a new capture.
3. Reconnect to the same observed CoreBluetooth peripheral identifier when available.
4. Capture from immediately before connection through at least 15–30 seconds after service/subscription setup.
5. If a legitimate research setup allows observing the stock app's values at the same time, record manual markers for:
   - battery `%`;
   - voltage `V`;
   - current `A`;
   - power `W`;
   - speed `0`;
   - trip mileage;
   - odometer/total mileage.
6. Export JSON.

Why this matters:

Tuya's public architecture describes state synchronization/query behavior around connection/reconnection. A quiet stationary stream later does not prove a field is absent if the useful state arrived in the initial sync.

## Session C — stationary baseline cadence

Goal: characterize raw callback behavior before interpreting fields.

Procedure:

1. Scooter on, stationary, charger disconnected.
2. Capture 2–5 minutes with advertisement duplicate capture off unless advertisement cadence itself is under test.
3. Record visible stock-app V/A/W/% markers only when the research setup legitimately permits them.
4. Export JSON.
5. Run `PassiveBluetoothValueStreamAnalysis`.

Review per characteristic:

- callback count;
- continuity segments;
- read-response versus subscription-update origins;
- payload length range;
- unique payload count;
- consecutive duplicate count;
- min/median/mean/max callback interval.

These are **raw CoreBluetooth callback statistics**, not decoded telemetry cadence.

## Session D — charger disconnected versus connected

Goal: find raw streams that materially react to charging without declaring their semantics.

Prefer two separate immutable captures:

- baseline: scooter stationary, charger disconnected;
- comparison: scooter stationary, charger connected and charging normally.

Record legitimate stock-app markers when available, especially:

- battery %;
- voltage;
- current;
- watts;
- charging state/indicator if the stock app exposes one.

Then use `PassiveBluetoothCaptureComparison`.

Review:

- whether both captures resolved to the same observed CoreBluetooth peripheral identifier;
- added/removed GATT services;
- streams present in only one state;
- shared versus state-specific raw payloads;
- whether last payload changed;
- raw difference score as a sorting hint only.

If the report says `.differentObservedIdentifiers` or `.unresolved`, do not present the result as proven same-scooter state comparison without resolving that identity issue.

## Session E — post-ride voltage recovery

Goal: separate load/rest behavior from naive voltage→SoC assumptions.

Procedure:

1. Capture a stationary rested baseline with stock-app `% / V / A / W` markers where legitimate.
2. Perform a normal short ride using the scooter normally; Nembra sends no unknown commands.
3. Begin/continue passive capture as the physical setup permits.
4. Immediately after stopping, record visible stock-app `% / V / A / W`.
5. Record repeated rest markers at useful intervals such as ~30 sec, ~1 min, ~2 min, ~5 min.
6. Preserve all interruption boundaries.

Questions:

- Does displayed voltage recover while percentage stays fixed?
- Does percentage move under load/rest?
- Which raw stream follows that behavior?
- Is current zero at rest?
- Does wattage equal approximately `V × A`, suggesting derivation, or have an independent timing/value pattern?

A numerical relationship is a hypothesis until raw field mapping and timing are independently verified.

## Session F — controlled riding electrical correlation

Only after Sessions A–E have identified stable passive streams.

Goal: measure behavior under real motion without turning raw callbacks into fake fields.

Capture:

- stationary before motion;
- gentle acceleration;
- steady low speed;
- steady higher speed where safe/legal;
- coast;
- electronic/regenerative braking where the stock scooter normally performs it;
- stationary recovery.

Record stock-app values with a legitimate second-device/external-observation setup if simultaneous observation is actually supported. Do not look at or operate a phone unsafely while riding.

Questions:

- which stream cadence resembles speed versus slower battery state;
- whether current becomes negative during e-braking, goes to zero, or uses another convention;
- whether watts are signed/unsigned;
- native speed update cadence/jitter/resolution;
- relationship between voltage sag and current/load;
- whether one packet carries multiple changing fields.

## Cross-app correlation limitation

On one iPhone, Nembra cannot claim to passively sniff Tuya Smart's private CoreBluetooth exchange.

Legitimate options include:

- Nembra's own read/subscribe session plus before/after stock-app values;
- simultaneous second-device observation only if the scooter truly supports it;
- external BLE sniffer/test equipment where appropriate;
- repeated controlled states whose physical conditions are reproducible.

Every capture should document which setup was actually used.

## Promotion gates for each stock-app field

### Battery percentage

Before classifying as authoritative measured SoC, verify:

- exact raw field / decoded DP path;
- scale and valid range;
- whether direct 0–100 or derived;
- quantization;
- update cadence/latency;
- load/rest behavior;
- reconnect behavior;
- charging behavior;
- low-SoC behavior.

### Voltage

Before using as measured voltage evidence, verify:

- exact raw field;
- units/scale;
- cadence;
- load sag and recovery;
- full/low pack behavior;
- whether app value is raw or transformed.

Never map instantaneous voltage linearly to precise SoC.

### Current

Before using current for energy estimation, verify:

- exact raw field;
- units/scale;
- signedness;
- battery current versus controller/input/other meaning;
- zero/rest behavior;
- acceleration behavior;
- e-braking behavior;
- charging behavior;
- cadence/timestamp quality.

### Wattage/power

Before treating watts as an independent measured field, verify:

- whether a distinct raw field exists;
- units/scale;
- timing versus voltage/current;
- whether `W ≈ V × A` and whether that relation indicates local derivation;
- sign behavior;
- update cadence.

Even a verified live watt field is not enough by itself for trustworthy `Wh/mi`; energy integration also requires trustworthy timing and distance.

## Physical identity gate

CoreBluetooth peripheral UUID is useful observed identity evidence, but Nembra must not assume it is the final durable per-scooter learning key without validating lifecycle behavior across:

- app relaunch;
- phone reboot;
- Bluetooth toggles;
- forget/re-pair/rebind flows;
- scooter power cycles;
- firmware/app changes where relevant.

Adaptive-range history must not silently leak between different physical scooters.

## Expected artifacts

Each physical session should preserve:

- versioned raw capture JSON;
- exact app/build/commit SHA used to capture;
- research setup note;
- physical state label;
- relevant stock-app markers;
- transport fingerprint report;
- raw value-stream statistics;
- controlled-session comparison when applicable;
- a short VERIFIED / PROBABLE / UNKNOWN conclusion list.

Do not overwrite an old raw capture with decoded/reconstructed data. Derived decoders should consume immutable evidence and produce separate outputs.

## Smallest first physical action after app integration

Once PR #11 lands and this package is safely integrated with Bluetooth privacy configuration, the smallest useful physical step is:

1. scooter stationary;
2. start broad foreground scan;
3. identify/select the physical ES80;
4. connect;
5. capture advertisement + full GATT topology + passive reads/subscriptions for ~60 seconds;
6. export JSON;
7. stop.

That single session should establish which protocol family the **actual 2025 scooter** resembles and determine the next exact decoder/correlation step without sending one unknown application write.
