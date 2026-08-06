# PROTOCOL NOTES — AOVOPRO ES80 PRIMARY / MAXSHOT DEFERRED

This document deliberately separates facts from hypotheses. Never promote a hypothesis to a real write command without a capture or authoritative schema proving it.

## Primary hardware-validation target
- **AOVOPRO ES80** is now Nembra's first and primary real scooter target.
- MAXSHOT V1S Pro hardware validation is deferred. Preserve its prior protocol findings, capability abstractions, tests, and profile work for future support.
- Generic vehicle/service/command/telemetry architecture remains capability-driven; do not hard-code the entire app around one scooter.

## AOVOPRO ES80 — directly observed product behavior
- The stock Tuya application visibly reports a battery percentage for the physical ES80 used for Nembra development.
- That visible percentage is **not yet proven** to be a raw 1%-resolution value transmitted directly by the scooter. Packet/GATT evidence must establish its source, resolution, update cadence, and whether Tuya derives it.

## AOVOPRO ES80 — battery investigation is a priority protocol task
Determine with captures rather than assumptions:
- exact BLE/Tuya data point or characteristic carrying battery information
- whether the scooter transmits a direct 0–100 percentage
- percentage resolution/quantization
- native update frequency and latency
- whether percentage updates while riding
- whether updates freeze then jump in large increments
- whether pack voltage is exposed
- whether charging state is exposed
- whether Tuya calculates percentage locally from bars/voltage/another field
- behavior under acceleration/load
- recovery behavior after stopping/rest
- behavior near low battery/cutoff
- whether values differ across firmware/hardware batches

Battery evidence must eventually map into the single Nembra battery domain as **measured**, **estimated**, **displayed/interpolated**, or **unknown**. Presentation smoothing must never be mistaken for raw scooter telemetry.

## AOVOPRO ES80 — unknown, hardware capture required
- exact advertisement name(s) / manufacturer data / service data for the physical ES80
- exact GATT service UUIDs and characteristic UUIDs
- characteristic read/write/notify/indicate properties
- authentication/session handshake used by this Tuya BLE product, if any
- packet framing/checksum and whether the transport matches any known Tuya MCU bridge pattern
- speed data point/characteristic and native cadence/latency/jitter/resolution
- battery data point/characteristic and scaling
- voltage data point/characteristic and scaling if present
- charging-state data point/characteristic if present
- ODO/trip data points and scaling
- mode values and semantics
- lock/light/cruise/start-mode/speed-limit data points and ranges if exposed
- acknowledgement model: direct ack, mirrored state, notification refresh, or other behavior
- firmware/hardware identifiers and production-batch variation
- whether ODO is stored in dashboard MCU, motor controller, BLE module, or another component
- AccessorySetupKit identity/descriptors where applicable

## AOVOPRO ES80 — hardware research order
Use the safety sequence:
1. discover advertisement identity
2. enumerate services/characteristics/properties
3. subscribe/read passively
4. capture stock Tuya behavior while changing one known UI state at a time
5. correlate packets/data points with visible stock-app state
6. decode and document with representative captures
7. write parser/encoder tests
8. only then perform cautious real writes for semantics whose framing/range/acknowledgement are understood

Do not send random bytes to a motorized vehicle.

## AOVOPRO ES80 — battery/range truth gate
Before Nembra exposes authoritative 1% SoC behavior or learned remaining range as production-ready, verify enough real battery evidence to answer:
- is the anchor really measured percentage, bars, voltage, or a Tuya-derived value?
- how frequently can measured anchors legitimately change?
- how does the value behave under load and rest?
- is voltage usable as corroborating evidence without sag-induced oscillation?
- what meaningful percentage-consumption window is large enough to learn distance efficiency without quantization noise?
- does low-SoC usable distance per percentage point differ materially from mid-pack behavior?

If better energy telemetry such as real current/power/energy becomes verified later, document it explicitly before any Wh/mi or energy-based range model is enabled. Never invent unavailable current/watts/power.

# Deferred MAXSHOT V1S Pro evidence

The following findings are preserved because they may remain useful for future MAXSHOT support. They are **not** the primary hardware-validation target now.

## MAXSHOT — VERIFIED / previously captured or directly observed
- The physical controller label was observed as 36 V / 15 A / 350 W. This conflicts with some public 500 W / 42 V marketing, so production-batch identity matters.
- App-level controls observed/validated in the earlier protocol audit include lock, light, units, cruise, mode, start mode, and speed limits.
- Verified Tuya schema findings from the prior audit:
  - DP 13 — cruise (writable)
  - DP 15 — mode: walk / eco / normal / sport (writable)
  - DP 16 — start mode: zero-start / kick-start (writable)
  - DP 21 — current telemetry, 0.01 A scale (telemetry)
  - DP 22 — power in watts (telemetry)
  - DP 25 — controller/fault state (telemetry)
  - DP 101 — speed limit 1, observed schema 5–15 km/h
  - DP 102 — speed limit 2, observed schema 10–24 km/h
  - DP 103 — speed limit 3, observed schema 20–35 km/h
  - DP 104 — auto power-off, observed schema 5–90 min
- **No DP101–103 ↔ DP15 ride-mode mapping was verified.** The three limiter DPs and the four ride-mode values remain independent protocol facts.
- No exposed Tuya DP was verified for phase current, battery-current tuning, field weakening, torque map, acceleration ramp, voltage tuning, or wheel diameter. Do not invent these controls.

## MAXSHOT — VERIFIED generic Tuya FR8016 transport facts from official protocol material
- Serial frame prefix: `55 AA`.
- Frame includes protocol version, command, big-endian payload length, payload, and an additive modulo-256 checksum.
- Module-to-MCU DP write command: `0x06`.
- MCU-to-module DP report command: `0x07`.
- Query-all command: `0x08`.
- MCU version query/report: `0xE8` / `0xE9`.
- OTA forwarding family: `0xEA`–`0xEE`.

These generic facts do **not** establish the iPhone-side GATT UUIDs or prove the same transport applies to the AOVOPRO ES80.

## MAXSHOT — publicly corroborated product functions
Public manual/listing material consistently advertises app control for lock/unlock, cruise, customized speed limit, headlight, ride modes, speed/battery display, and zero/kick start. Mode marketing commonly describes Walk / Eco / D / Sport.

## MAXSHOT — still unknown if/when support resumes
- exact BLE advertisement name(s)
- exact service UUIDs and characteristic UUIDs
- notification/read/write characteristics
- authentication/session handshake
- speed DP/native cadence
- battery/ODO/trip DP identifiers/scaling
- command acknowledgement behavior
- firmware/hardware identifiers for the exact batch
- ODO storage component

## Safety gate for any real write on any scooter
A write can enter a production encoder only after:
1. characteristic and framing are known,
2. command semantic is known,
3. valid range is known,
4. acknowledgement/state confirmation is understood,
5. parser/encoder unit tests cover representative frames,
6. first hardware test is performed stationary/unloaded where appropriate.
