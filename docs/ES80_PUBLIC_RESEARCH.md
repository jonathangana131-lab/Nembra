# AOVOPRO ES80 Public Protocol Research

Research checkpoint: **2026-08-06**

Nembra's physical target is the **newer 2025-generation AOVOPRO ES80**. Research in this document therefore prioritizes the current Tuya-generation path. Legacy AovoPro-app material is historical family evidence only unless independently corroborated for the current scooter.

No statement here authorizes a motorized-hardware write. Real writes remain behind the safety gate in `PROTOCOL_NOTES.md`.

## Evidence classes

- **DIRECT PHYSICAL / APP OBSERVATION** — behavior directly observed on the actual 2025 ES80 and its stock app, but not yet mapped to raw BLE/DP evidence.
- **VERIFIED PUBLIC** — authoritative documentation or reproducible public evidence directly establishes the stated fact.
- **CORROBORATED / PROBABLE** — multiple sources or a directly related official family artifact strongly support the statement, but exact current-ES80 applicability is not proven.
- **GENERIC TUYA / FAMILY FACT** — useful protocol clue from Tuya or a related AOVOPRO lineage, not an ES80-specific protocol fact.
- **UNKNOWN / PHYSICAL VERIFICATION REQUIRED** — public/app evidence does not establish the exact raw transport fact for the physical Nembra target.

## Direct physical / app observations for the Nembra target

The Nembra target is a **2025-generation ES80 using the newer app path**.

On the actual scooter's stock app, the details/device-information area visibly exposes **live**:

- battery percentage;
- pack voltage;
- current in amps;
- wattage/power.

This materially changes the research target: current/power are not hypothetical UI features for this scooter. Nembra should actively locate and classify their raw sources.

However, the app display alone does **not** yet prove:

- whether voltage, current, and wattage are three independent device-reported fields;
- whether wattage is device-reported or app-calculated from voltage × current;
- units/scales/signedness at the BLE/DP layer;
- native report cadence, latency, jitter, or duplicate filtering;
- whether current is battery current, controller input current, or another current measurement;
- behavior under acceleration, regen/e-braking, charging, and rest;
- whether battery percentage is direct measured SoC, firmware-derived SoC, or app-derived;
- whether values are local BLE notifications, requested reads, cloud-backed state, or a mixture.

Until packet evidence answers those questions, Nembra may describe the values as **stock-app-observed live telemetry**, not as decoded authoritative BLE fields.

## Verified public 2025 ES80 identity

AOVOPRO's official ES80 product page explicitly labels the scooter **New 2025 AOVOPRO Electric Scooter ES80**, identifies the app as `AOVOPRO/Tuya Smart`, and states that latest ES80/ESMAX units may be partially loaded with Tuya Smart for different market needs.

Official sources, accessed 2026-08-06:

- AOVOPRO ES80 product page: https://www.aovopro.com/product/aovopro-es80-electric-scooter-350w-10-5-ah-long-range-high-speed-foldable-electric-scooter/
- AOVOPRO brand statement: https://www.aovopro.com/aovo-pro-solemnly-declare/

The current product page lists:

- model: `ES80`;
- battery: 36 V, 10.5 Ah;
- motor: 36 V / 350 W;
- app: `AOVOPRO/Tuya Smart`.

**Nembra implication:** current 2025/Tuya behavior takes precedence over assumptions from older AovoPro-app generations.

## Current official Tuya interface evidence

AOVOPRO's current ES80 product page directly embeds the Tuya Smart panel image used for latest ES80/ESMAX variants:

- official image: https://www.aovopro.com/wp-content/uploads/2024/06/image.png

The official image visibly shows:

- connected state;
- battery percentage (`100%` in the example);
- estimated range;
- single/trip mileage;
- total mileage;
- headlight control;
- start-mode control;
- mode control.

This establishes the current stock panel family independently of the legacy AovoPro app.

Combined with the direct physical observation that the actual 2025 target also exposes live voltage/amps/watts in its details view, the current target clearly has a useful electrical telemetry surface. The remaining job is to determine raw source and truth semantics rather than asking whether electrical telemetry exists at all.

Public UI does **not** establish exact DP IDs or raw packet structure.

## Nearby official Tuya-branded product is not identity proof

AOVOPRO separately sells a `Tuya 80` / Tuya Smart scooter with materially different published hardware (for example a 7.8 Ah battery and drum brake on the currently indexed page).

Official source, accessed 2026-08-06:

- https://www.aovopro.com/product/tuya-smart-electric-scooter-350w-powerful-motor-high-speed-long-range-foldable-electric-scooter/

**Nembra implication:** `Tuya`, `Tuya 80`, panel appearance, or a generic scooter silhouette is not enough to identify the physical Nembra target as ES80. The real profile must eventually use exact transport/device evidence rather than branding alone.

## Legacy AOVOPRO family evidence — historical only

The old AovoPro-app ES80/manual lineage exposes a details page containing battery, speed, voltage, current, input power, controller temperature, subtotal distance, and total mileage. This is visible in historical app/manual material and provides a useful family correlation clue.

For the 2025 Tuya ES80, this older interface is not protocol authority. It is useful only because it shows that AOVOPRO-family controllers historically surfaced electrical telemetry similar to what is directly observed on the current scooter.

Secondary manual reference, accessed 2026-08-06:

- https://manuals.plus/ae/1005012106574594

## Generic Tuya mobility facts that narrow the search

Tuya's current **Ride Development Guide** explicitly covers scooters and other mobility products. It says that actual DP IDs/identifiers depend on the product's configured DP list; generic DP numbers must therefore not be copied into Nembra as ES80 facts.

Official source, accessed 2026-08-06:

- https://developer.tuya.com/en/docs/iot/mobility_development_guidelines?id=Kfme01kf7zw31

### Battery DP model candidates

The Tuya mobility guide recommends pack-summary fields including:

- state of charge;
- total voltage;
- total current;
- battery temperature;
- charging status;
- cycle count;
- estimated range.

It also documents important implementation behavior:

- report pack summary values on changes;
- filter raw SoC jitter, noting that BMS SoC may jump by 1–2%;
- report charging-state transitions explicitly;
- common voltage encodings include `0.01 V` and mV;
- common current encodings include `0.01 A` and mA;
- units, byte order, and signedness are product/protocol details that must be documented;
- private BMS protocols may be wrapped in a Raw DP;
- high-frequency riding data can be packed together on applicable Tuya vehicle architectures.

These facts make separate SOC/voltage/current DPs or a Raw battery payload plausible candidates. They do **not** prove which form the 2025 ES80 uses.

### Reporting cadence implications

The Tuya mobility guide also says:

- sync all DPs during pairing/reconnection queries;
- otherwise report changing DPs on change rather than repeatedly sending identical values;
- Bluetooth vehicle ride fields such as speed, single mileage, and battery level are expected to report on changes;
- speed may be used for local display without needing cloud history.

**Capture implication:** a quiet notification stream while stationary does not prove a field is unavailable. Nembra should intentionally cause safe observable value changes or trigger legitimate read/query flows before concluding a DP is missing.

## Generic Tuya BLE discovery candidates

Tuya's BLE documentation provides useful passive discovery candidates.

### Modern Tuya service candidate

Official Tuya material documents:

- service: `0xFD50`;
- write-without-response characteristic: `00000001-0000-1001-8001-00805F9B07D0`;
- notify characteristic: `00000002-0000-1001-8001-00805F9B07D0`;
- optional read characteristic: `00000003-0000-1001-8001-00805F9B07D0`;
- Tuya manufacturer/company identifier `0x07D0` in documented BLE advertisement templates.

Official sources, accessed 2026-08-06:

- https://developer.tuya.com/en/docs/iot-device-dev/Porting-Guide-BLE?id=Kam0xjtz4n6e0
- https://developer.tuya.com/en/docs/iot-device-dev/bluetooth_software_map_bt_bonding?id=Kcmeabmo402en

### Legacy Tuya service candidate

Older Tuya BLE documentation records a `0x1910` service family with characteristic layouts including `0x2B10` notification and `0x2B11` write/write-without-response.

Official source, accessed 2026-08-06:

- https://developer.tuya.com/en/docs/iot-device-dev/tuya-ble-sdk-user-guide?id=K9h5zc4e5djd9

**Classification:** `FD50` and `1910` are passive fingerprint candidates only. Nembra must capture every observed service/characteristic rather than filtering discovery to either assumption.

## Public batch / identity clues

Community reports around ES80/ESMAX hardware show mixed app behavior and non-obvious Bluetooth local names, including examples such as `demo` and `djlurring`. These reports are low-authority and must never establish canonical ES80 identity by themselves.

Examples, accessed 2026-08-06:

- https://www.reddit.com/r/ElectricScooters/comments/1f5obc8/disappointing_es80/
- https://www.reddit.com/r/Escooters/comments/19052tr/pure_air_3_pro_vs_aovopro_esmax/

Their useful implication is narrow: **do not identify the 2025 ES80 by local-name string alone**. Identity should eventually combine advertisement evidence, service fingerprints, authenticated/bound device identity where legitimate, and a verified physical-scooter persistence key.

## Public research result: no exact 2025 ES80 DP dump found yet

Reasonable public searches performed for this checkpoint included:

- AOVOPRO official current product/statement/manual material;
- Tuya current mobility/ride development documentation;
- Tuya BLE service/pairing documentation;
- indexed GitHub/web searches for ES80 Tuya DP/schema/GATT/UUID/localTuya/TinyTuya references;
- community ES80/ESMAX Bluetooth/app reports;
- regulatory/FCC/ISED-style searches.

No trustworthy public source located in this pass exposes the **exact 2025 ES80 Tuya product DP list, PID, GATT dump, packet capture, or raw voltage/current/power mapping**.

That means the next unresolved facts are genuinely device-specific enough to justify passive physical capture; the public research step has still narrowed the capture substantially.

## High-priority capture questions after this research

The next physical passive capture should answer the following in order:

1. What advertisement/local-name/manufacturer/service data does the 2025 ES80 emit before and after stock-app binding?
2. Does service discovery expose `FD50`, `1910`, or another transport?
3. What full DP/state snapshot appears on pairing/reconnection/query?
4. Which characteristics notify while the details page is open?
5. Which raw field correlates with battery percentage?
6. Which raw field correlates with live pack voltage?
7. Which raw field correlates with live amps?
8. Is displayed wattage independently transmitted, or does it equal voltage × current closely enough to indicate app/firmware derivation?
9. What are each field's units, scale, signedness, native cadence, and duplicate behavior?
10. Does current become negative during regenerative/electronic braking, clamp to zero, or use another convention?
11. What changes while charging, and is charging state separately exposed?
12. Are speed, trip, and odometer values on the same DP/report stream?
13. What exact product/firmware identifiers can safely scope learned range history to this physical scooter?

## Safe correlation experiment

A useful first stationary/passive session can collect advertisements/services/notifications while recording visible stock-app values through controlled states:

- powered on and stationary;
- open the stock app details screen and record the exact battery/voltage/amps/watts values with timestamps;
- several minutes stationary for baseline/report-on-change behavior;
- headlight off/on only if using the already understood stock app, not a Nembra write;
- charger disconnected vs connected;
- after a short ride, observe load-recovery changes in voltage/current/percentage;
- later, during a controlled real ride, correlate speed and electrical telemetry with monotonic receipt timestamps.

No random writes are required for these questions.

## Battery/range consequence

Because the actual 2025 app exposes live voltage, amps, and watts, Nembra's battery architecture should preserve room for richer **verified future energy telemetry**. But implementation must still gate every derived metric by source truth:

- measured SoC may train percent-based range once its source/cadence is verified;
- voltage may become supporting load/rest evidence once scale and sag behavior are known;
- current/power may support a future energy model only after raw semantics and timing are verified;
- `Wh/mi` remains prohibited until Nembra can integrate trustworthy energy over time with trustworthy distance.

A stock-app watt number alone is not sufficient proof for energy integration.

## Current classification summary

### DIRECT PHYSICAL / APP OBSERVATION
- target scooter is newer 2025-generation ES80;
- stock app exposes live battery percentage;
- stock app details expose live voltage;
- stock app details expose live amps/current;
- stock app details expose live wattage/power.

### VERIFIED PUBLIC
- AOVOPRO markets a New 2025 ES80;
- latest ES80/ESMAX can legitimately use Tuya Smart;
- official ES80 specification is 36 V / 10.5 Ah battery and 36 V / 350 W motor;
- current official Tuya ES80 panel imagery exposes battery percentage, estimated range, trip/total mileage and core controls.

### GENERIC TUYA / FAMILY FACT
- Tuya mobility products commonly model SOC, voltage, current, charging and related battery information as configured DPs/raw payloads;
- actual DP IDs are product-specific;
- report-on-change behavior means passive capture must intentionally observe legitimate state changes and reconnect snapshots;
- `FD50` is a modern Tuya BLE service candidate;
- `1910` is a legacy Tuya BLE service candidate.

### UNKNOWN / PHYSICAL VERIFICATION REQUIRED
- exact 2025 ES80 advertisement identity;
- exact GATT service/characteristic UUIDs;
- exact Tuya PID/product DP list/raw schema;
- battery percentage raw source/resolution/cadence;
- voltage raw source/scale/cadence;
- current raw source/scale/signedness/cadence;
- whether wattage is reported or calculated;
- charging-state source;
- speed/ODO/trip schema;
- acknowledgement behavior;
- stable per-physical-scooter identity suitable for learned-range persistence;
- firmware/batch differences.
