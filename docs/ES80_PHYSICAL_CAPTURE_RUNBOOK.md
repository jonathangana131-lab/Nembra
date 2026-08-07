# 2025 AOVOPRO ES80 Passive Physical Capture Runbook

Status: **prepared software procedure; physical target capture not yet performed by the V11 feature cell**.

Target: the newer 2025-generation AOVOPRO ES80 research target. Existing stock-app observations provide useful visible reference values such as battery percentage, voltage, current, and power, but their raw Bluetooth/Tuya source, identifiers, scale, cadence, signedness, and derivation remain unverified until physical capture evidence closes those gates.

## Software prerequisite

The V11 `ES80 Passive Capture + CoreBluetooth Adapter` feature cell contains the passive tooling required for physical sessions:

- broad first-fingerprint foreground candidate scan;
- explicit peripheral target selection before any durable target artifact exists;
- selected-target connection timeout/cancellation and stale-callback isolation;
- service / included-service / characteristic / descriptor discovery;
- reads only where `.read` is advertised;
- subscriptions only where `.notify` / `.indicate` is advertised;
- structured connection/subscription evidence;
- raw value callback provenance and monotonic ordering;
- fail-closed incomplete acquisition;
- selected-target stock-app correlation markers;
- versioned JSON export;
- per-peripheral transport candidate reports;
- continuity-aware callback-stream statistics and controlled-session comparison.

`ES80PassiveCaptureResearchView` remains research UI, not production scooter-control wiring. Physical iPhone integration must include the appropriate Bluetooth privacy-purpose configuration and must be accepted as an app-visible cell/release-train change before use.

No package API performs an application characteristic-value write. The V11 product recovery intentionally does **not** revive historical #22's package workflow; any CI write guard is a separate control-plane slice and must be reviewed on its own merits.

## Hard safety and truth rules

1. Do not send unknown application characteristic writes or random scooter commands.
2. Do not copy writable DP IDs from another Tuya product and treat them as ES80 commands.
3. Discover/read/subscribe only according to observed GATT properties.
4. Treat `.write` / `.writeWithoutResponse` properties as metadata, never authorization.
5. Treat subscription success as transport state, never scooter command acknowledgement.
6. Treat FD50/A201/1910 and other researched families as candidates until the physical scooter supplies matching evidence.
7. Keep raw CoreBluetooth callback boundaries immutable; derived framing/decryption happens later.
8. Do not export Tuya local/auth/session keys, account tokens, or unrelated credentials.
9. Do not claim Nembra intercepted another app's private Bluetooth exchange. CoreBluetooth supplies Nembra's own central-session observations.
10. A broad-scan candidate is not target evidence. Select one peripheral explicitly before recording markers, analyzing, or exporting a target-labeled artifact.
11. If discovery/read/subscription acquisition fails closed, discard that session as incomplete for absence claims; do not interpret missing events as “not present.”
12. `VehicleIdentity` and a CoreBluetooth UUID are attribution labels/evidence, not permanent proof of physical ES80 identity.

## Session 0 — preparation

Before the first scan:

- scooter safely stationary;
- no unknown Nembra command path enabled;
- Bluetooth enabled;
- note app/scooter/firmware identifiers visible in legitimate UI when available;
- note approximate visible battery/reference state;
- note charger state;
- ensure only one physical ES80 is intentionally being tested;
- record the exact Nembra build/commit and research setup.

Nearby Bluetooth/Tuya devices may remain visible in the broad catalog. They must not enter the target capture unless the operator deliberately selects that peripheral for its own separate research session.

## Session A — advertisement + GATT fingerprint

Goal: establish the physical target's real Bluetooth identity/topology without assuming a protocol family.

Procedure:

1. Start an explicit foreground research scan with duplicate advertisements off initially.
2. Observe the candidate catalog: local name/no-name state, RSSI, connectability, manufacturer/service data, advertised/overflow/solicited UUIDs, and Tx power when supplied.
3. Identify the likely physical scooter using legitimate physical correlation, not local-name similarity alone.
4. Choose **Select & connect** for that exact candidate. This action creates the durable target session.
5. Confirm the research UI shows the intended selected-target CoreBluetooth identifier.
6. Let the controller discover services, included services, characteristics/properties, descriptors, and passive read/subscription paths.
7. If capture becomes fail-closed, stop and investigate; do not export an apparently complete artifact.
8. If healthy, capture roughly 30–60 seconds stationary and export versioned JSON.

Questions answered only after physical evidence exists:

- Which advertisement/GATT identifiers are actually observed for the target?
- Does it resemble FD50, A201, 1910, or another family?
- Which characteristics advertise read/notify/indicate/write capabilities?
- Which passive value streams are observed?
- Does topology change/invalidate during the session?

Acceptance wording should say `OBSERVED ON PHYSICAL TARGET: ...`, not “battery service” or “ES80 protocol” unless later evidence really establishes that meaning.

## Session B — reconnect and lifecycle evidence

Goal: characterize reconnect/initial-state behavior and preserve connection continuity truth.

Procedure:

1. Keep Session A JSON immutable.
2. Reconnect the same selected research target when appropriate, or start a deliberately separate session if the setup requires it.
3. Capture from before connection through at least 15–30 seconds after discovery/subscription setup.
4. Preserve structured `.connected`, `.failedToConnect`, `.disconnected`, platform error domain/code, and platform disconnect timestamp/reconnect metadata when CoreBluetooth supplies them.
5. Record legitimate visible stock-app markers only after a selected target session exists.
6. Export only if acquisition remains healthy.

A structured disconnect is a byte-continuity break. Receipt uptime/date and CoreBluetooth platform event timestamp are different clocks and must not be substituted for one another.

## Session C — stationary baseline cadence

Goal: characterize callback behavior before assigning semantics.

1. Scooter on, stationary, charger disconnected.
2. Capture 2–5 minutes with duplicate advertisement capture off unless advertisement cadence itself is the experiment.
3. Record legitimate visible reference markers when the setup permits them.
4. Export a healthy immutable session.
5. Run `PassiveBluetoothValueStreamAnalysis`.

Review per characteristic:

- callback count;
- continuity segments;
- read-response versus subscription-update provenance;
- payload length range;
- unique/duplicate payload behavior;
- min/median/mean/max callback interval.

These are raw CoreBluetooth callback statistics, not decoded telemetry cadence.

## Session D — charger disconnected versus connected

Goal: find raw streams that react to charging without declaring field meaning.

Prefer two separate immutable target captures:

- baseline: stationary, charger disconnected;
- comparison: stationary, charger connected/charging normally.

Record legitimate reference markers such as visible battery %, voltage, current, power, or charging indicator when available. Then use `PassiveBluetoothCaptureComparison`.

Review:

- whether both captures resolve to the intended observed peripheral identity;
- added/removed GATT services;
- streams present in only one state;
- shared versus state-specific raw payloads;
- last-payload differences and raw difference score.

If identity is `.differentObservedIdentifiers` or `.unresolved`, do not present the comparison as proven same-scooter state evidence without resolving that ambiguity.

## Session E — post-ride voltage recovery

Goal: separate load/rest behavior from naive voltage-to-SoC assumptions.

1. Capture a stationary rested baseline and legitimate visible reference markers.
2. Perform a normal short ride using the scooter normally; Nembra sends no unknown application commands.
3. Resume/start passive capture as the physical setup safely permits.
4. Record visible post-stop reference values.
5. Record repeated rest markers at useful intervals such as ~30 s, ~1 min, ~2 min, and ~5 min.
6. Preserve every disconnect/interruption boundary.

Questions include whether displayed voltage recovers while percentage remains fixed, which raw streams correlate with load/rest, whether current behavior changes sign/zero state, and whether displayed watts may be derived. Numerical relationships remain hypotheses until field identity and timing are independently verified.

## Session F — controlled riding electrical correlation

Only after Sessions A–E identify stable passive streams.

Capture safe, legitimate states such as stationary-before-motion, gentle acceleration, steady motion, coast, normal electronic braking behavior, and stationary recovery. Use a second observer/device only if the physical setup truly supports it; never operate a phone unsafely while riding.

Potential questions:

- which raw stream cadence resembles speed versus slower battery state;
- current sign/zero behavior;
- power sign/derivation behavior;
- speed update cadence/jitter/resolution;
- voltage sag versus load;
- whether one packet contains multiple changing fields.

None of those questions is answered by the software adapter alone.

## Cross-app correlation limitation

Nembra cannot claim to passively sniff a stock app's private CoreBluetooth exchange from the same iPhone. Legitimate approaches include Nembra's own read/subscribe session plus before/after reference values, simultaneous second-device observation only when physically supported, external BLE test equipment where appropriate, or repeated controlled physical states.

Every capture must document the actual setup used.

## Promotion gates for visible fields

### Battery percentage
Verify exact raw/decoded path, scale/range, direct-vs-derived behavior, quantization, cadence/latency, reconnect/charging/load-rest behavior, and low-state behavior before calling it authoritative measured SoC.

### Voltage
Verify exact raw field, units/scale, cadence, load sag/recovery, pack-state behavior, and whether the stock app transforms the value. Never map instantaneous voltage linearly to precise SoC.

### Current
Verify exact raw field, units/scale, signedness, physical meaning, zero/rest behavior, acceleration/braking/charging behavior, and timing quality before energy integration.

### Power
Verify whether an independent raw field exists, units/scale/sign, timing relative to voltage/current, possible `V × A` derivation, and update cadence. A live watt value alone is insufficient for trustworthy energy-per-distance estimates.

## Physical identity gate

CoreBluetooth peripheral UUID is useful observed identity evidence but is not yet a proven durable per-scooter key. Validate behavior across app relaunch, phone reboot, Bluetooth toggles, pair/rebind flows, scooter power cycles, and relevant firmware/app changes before using it as a long-lived physical identity.

## Expected artifacts

Preserve for each physical session:

- versioned raw capture JSON;
- exact Nembra build/commit SHA;
- selected-target CoreBluetooth identifier and how it was physically correlated;
- research setup/physical state note;
- legitimate reference markers;
- transport fingerprint report;
- raw value-stream statistics;
- controlled-session comparison where applicable;
- a short `VERIFIED / PROBABLE / UNKNOWN` conclusion list;
- acquisition-failure notes for any discarded incomplete session.

Never overwrite raw capture evidence with reconstructed/decoded data. Derived analysis produces separate artifacts.

## Smallest first physical action after app-visible integration

Once this V11 feature cell has local package acceptance, app-visible Bluetooth privacy/integration is reviewed, and the release train proves the combined build, the smallest useful physical step is:

1. scooter stationary;
2. start broad foreground scan;
3. physically correlate and explicitly select the intended target;
4. connect;
5. capture selected-target advertisement + GATT topology + passive reads/subscriptions for ~60 seconds;
6. export only if the capture remains healthy;
7. stop and inspect the immutable evidence before adding any decoder hypothesis.

That session should determine the next research step without sending an unknown application write.
