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

The current product page also lists:

- model: `ES80`;
- battery: 36 V, 10.5 Ah;
- motor: 36 V / 350 W;
- app: `AOVOPRO/Tuya Smart`.

**Nembra implication:** current 2025/Tuya behavior takes precedence over assumptions from older AovoPro-app generations.

## Current official Tuya interface evidence

AOVOPRO's current ES80 product material publishes a Tuya Smart interface for latest ES80/ESMAX variants. Publicly visible state includes battery percentage and ride/device information such as range/mileage and controls.

Combined with the direct physical observation above, the current 2025 target clearly has a useful battery/electrical telemetry surface in its stock app. The remaining job is to determine the raw transport and truth semantics rather than asking whether such telemetry exists at all.

Public UI still does **not** establish exact DP IDs or raw packet structure.

## Legacy AOVOPRO family evidence — historical only

The old AovoPro-app ES80/manual lineage exposes a details page containing battery, speed, voltage, current, input power, controller temperature, subtotal distance, and total mileage. This is visible in historical app/manual material and provides a useful family correlation clue.

For the 2025 Tuya ES80, this older interface is not protocol authority. It is useful only because it shows that AOVOPRO-family controllers historically surfaced electrical telemetry similar to what is directly observed on the current scooter.

Secondary manual reference, accessed 2026-08-06:

- https://manuals.plus/ae/1005012106574594

## Generic Tuya mobility facts that narrow the search

Tuya's current **Ride Development Guide** is directly relevant to scooters and other mobility products. It says that actual DP IDs/identifiers depend on the product's configured DP list; generic DP numbers must therefore not be copied into Nembra as ES80 facts.

The same Tuya guide recommends/reporting fields for mobility battery packs including:

- state of charge;
- total voltage;
- total current;
- battery temperature;
- charging status;
- estimated range.

It also notes that mobility implementations may pack high-frequency fields such as battery level and voltage while riding, and it explicitly warns about SoC jitter and device-side smoothing/hysteresis.

Official source, accessed 2026-08-06:

- Tuya Ride Development Guide: https://developer.tuya.com/en/docs/iot/mobility_development_guidelines?id=Kfme01kf7zw31

**Classification:** this is **GENERIC TUYA / FAMILY FACT**, not proof of the 2025 ES80's exact DP schema. It does, however, make separate voltage/current/SOC mobility DPs or a raw battery payload plausible candidates worth testing passively.

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

Community reports around ES80/ESMAX hardware show mixed app behavior and non-obvious Bluetooth local names, including examples such as `demo`. These reports are low-authority and must never establish canonical ES80 identity by themselves.

Their useful implication is narrow: **do not identify the 2025 ES80 by local-name string alone**. Identity should eventually combine advertisement evidence, service fingerprints, authenticated/bound device identity where legitimate, and a verified physical-scooter persistence key.

## High-priority capture questions after this research

The next physical passive capture should answer the following in order:

1. What advertisement/local-name/manufacturer/service data does the 2025 ES80 emit before and after stock-app binding?
2. Does service discovery expose `FD50`, `1910`, or another transport?
3. Which characteristics notify while the details page is open?
4. Which raw field correlates with battery percentage?
5. Which raw field correlates with live pack voltage?
6. Which raw field correlates with live amps?
7. Is displayed wattage independently transmitted, or does it equal voltage × current closely enough to indicate app/firmware derivation?
8. What are each field's units, scale, signedness, native cadence, and duplicate behavior?
9. Does current become negative during regenerative/electronic braking, clamp to zero, or use another convention?
10. What changes while charging, and is charging state separately exposed?
11. Are speed, trip, and odometer values on the same DP/report stream?
12. What exact product/firmware identifiers can safely scope learned range history to this physical scooter?

## Safe correlation experiment

A useful first stationary/passive session can collect notifications while recording visible stock-app values through controlled states:

- powered on and stationary;
- headlight off/on without riding;
- several minutes stationary for baseline cadence;
- wheel unloaded/spun only if mechanically safe and no write is required;
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
- official ES80 specification is 36 V / 10.5 Ah battery and 36 V / 350 W motor.

### GENERIC TUYA / FAMILY FACT
- Tuya mobility products commonly model SOC, voltage, current, charging and related battery information as configured DPs/raw payloads;
- actual DP IDs are product-specific;
- `FD50` is a modern Tuya BLE service candidate;
- `1910` is a legacy Tuya BLE service candidate.

### UNKNOWN / PHYSICAL VERIFICATION REQUIRED
- exact 2025 ES80 advertisement identity;
- exact GATT service/characteristic UUIDs;
- exact Tuya DP IDs/raw schema;
- battery percentage raw source/resolution/cadence;
- voltage raw source/scale/cadence;
- current raw source/scale/signedness/cadence;
- whether wattage is reported or calculated;
- charging-state source;
- speed/ODO/trip schema;
- acknowledgement behavior;
- stable per-physical-scooter identity suitable for learned-range persistence;
- firmware/batch differences.
