# PROTOCOL NOTES — MAXSHOT V1S Pro / YouFS / Tuya

This document deliberately separates facts from hypotheses. Never promote a hypothesis to a real write command without a capture or authoritative schema proving it.

## VERIFIED / previously captured or directly observed
- The user's physical controller label was observed as 36 V / 15 A / 350 W. This conflicts with some public 500 W / 42 V marketing, so production-batch identity matters.
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
- **No DP101–103 ↔ DP15 ride-mode mapping has been verified.** The three limiter DPs and the four ride-mode values are currently modeled as independent protocol facts. Do not assume limit 1 = Eco, limit 2 = Normal, or limit 3 = Sport simply because the ranges look plausible.
- No exposed Tuya DP was verified for phase current, battery-current tuning, field weakening, torque map, acceleration ramp, voltage tuning, or wheel diameter. Do not invent these controls.

## VERIFIED generic Tuya FR8016 transport facts from official protocol material
- Serial frame prefix: `55 AA`.
- Frame includes protocol version, command, big-endian payload length, payload, and an additive modulo-256 checksum.
- Module-to-MCU DP write command: `0x06`.
- MCU-to-module DP report command: `0x07`.
- Query-all command: `0x08`.
- MCU version query/report: `0xE8` / `0xE9`.
- OTA forwarding family: `0xEA`–`0xEE`.

These generic facts do **not** establish the iPhone-side GATT UUIDs or prove that every optional command is enabled on this scooter.

## PUBLICLY CORROBORATED PRODUCT FUNCTIONS
Public manual/listing material consistently advertises app control for lock/unlock, cruise, customized speed limit, headlight, ride modes, speed/battery display, and zero/kick start. Mode marketing commonly describes Walk / Eco / D / Sport.

## UNKNOWN — hardware capture required
- Exact BLE advertisement name(s) for this physical unit
- Exact service UUIDs and characteristic UUIDs
- Which characteristic(s) notify/read/write
- Authentication/session handshake used by the Tuya BLE product
- Speed DP identifier and native report cadence on this unit
- Battery/ODO/trip DP identifiers and scaling on this unit
- Whether command acknowledgement is direct, mirrored state, or refresh-based
- Firmware/hardware identifiers for the user's exact production batch
- Whether ODO is stored in dashboard MCU, motor controller, or another component

## PROBABLE, NOT YET PROVEN
- The official YouFs-A store description says the speed of each gear can be adjusted. This supports the idea that limiter settings relate to gears/modes in some YouFS products, but it does **not** establish which of DP101/102/103 maps to which DP15 mode on this MAXSHOT batch.
- A correspondence between the three speed-limit slots and some subset of the four ride modes is plausible, but unobserved. It is intentionally absent from production behavior until captured.
- The dashboard/BLE family is related to YouFS-Z1 / Tuya FR8016 architecture seen in public references.
- Scooter ODO is likely available as a device DP because Tuya presents it, but the exact DP/scale must be captured before production parsing.

## Safety gate for real writes
A write can enter the production encoder only after:
1. characteristic and framing are known,
2. command semantic is known,
3. valid range is known,
4. acknowledgement/state confirmation is understood,
5. parser/encoder unit tests cover representative frames,
6. first hardware test is performed stationary/unloaded where appropriate.
