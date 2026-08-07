# AOVOPRO ES80 — First Physical Capture

Status: **prepared procedure only — not yet verified on physical hardware**

Primary target: newer Tuya-generation AOVOPRO ES80

This procedure defines **one** minimal physical experiment. Its purpose is to move Nembra from software-only passive capture toward observed physical advertisement/GATT/value evidence without sending an unknown application characteristic write or pretending that a broad-scan candidate is already a verified ES80 identity.

It is intentionally stationary and foreground-only. It is not a riding test, battery-decoding test, command test, or proof of any Tuya DP semantic.

## Run gate

Do not run this experiment until all of the following are true:

- the accepted passive-capture parent includes the hardened finite acquisition, target attribution, immutable artifact-read boundary, and same-target terminal-callback quarantine used by the current recovery line;
- the product-facing Nembra Capture shell has been reconciled onto that accepted parent and has passed its exact-head iPhone 12 / iOS 27 app gate;
- any known shell blockers that could misstate evidence continuity or artifact finalization have been closed;
- the exact Nembra build/commit used on the phone is known;
- the capture can be exported unchanged for offline analysis.

If the stationary-capture manifest/sidecar capability lands first, use it and preserve it with the exact capture JSON. Do not weaken provenance by manually editing the raw capture artifact.

A green Simulator/package run is software evidence only. It does not satisfy this physical run gate by itself.

## Safety boundary

For this experiment:

- scooter remains powered on and **stationary** for the entire capture;
- charger remains **disconnected**;
- rear wheel remains on the ground and no throttle/brake/control experiment is performed;
- Nembra performs only discovery, permitted reads, and permitted notification/indication subscriptions;
- do not send any unknown characteristic-value write;
- do not use a `.write` / `.writeWithoutResponse` property as authorization;
- do not enable lock, light, cruise, speed-limit, start-mode, or motor commands from Nembra;
- do not switch to the stock Tuya/AOVOPRO app on the same iPhone during the capture;
- do not lock the iPhone, background Nembra, or let the screen auto-lock during the capture;
- if Bluetooth, the app, or the selected connection becomes unavailable before finite acquisition is ready, treat the attempt as incomplete rather than filling the gap with assumptions.

The current capture path is foreground research software. This first experiment therefore keeps the iPhone unlocked, screen on, and Nembra Capture visible for a short stationary session.

## Physical setup

1. Place the ES80 on stable level ground in a safe area away from traffic.
2. Power the scooter on normally.
3. Leave the charger disconnected.
4. Keep the scooter untouched for about 30 seconds before opening the capture flow so transient power-on behavior can settle.
5. Use the accepted Nembra Capture build on the iPhone 12.
6. Keep only the physical target scooter intentionally under test. Nearby BLE devices may remain present; they are candidates only.
7. If a second device is available, it may display the legitimate stock app **for reference only**. Do not require a second device for this first fingerprint capture, and do not claim Nembra is sniffing the stock app's private session.

## Exact capture procedure

1. Open **Nembra Capture** and keep it foregrounded.
2. Start one broad foreground scan with advertisement-cadence duplication left at its normal/off setting.
3. Observe the candidate list. Use legitimate physical correlation to choose the likely scooter; do not select by local name alone.
4. Record the candidate's displayed short identifier in the experiment provenance/manifest, but classify it as an **observed CoreBluetooth candidate identifier**, not permanent scooter identity.
5. Select that exact candidate and start the target-scoped capture.
6. Keep the scooter stationary while Nembra performs finite service / included-service / characteristic / descriptor discovery plus only GATT-permitted reads/subscriptions.
7. Wait until Nembra reports that the finite passive acquisition is complete/ready. If it fails closed, times out, disconnects before readiness, or becomes ambiguous, stop. Preserve the failed artifact only as failure evidence; do not use it to claim a service/field is absent.
8. After readiness, leave the healthy foreground session running for **60 seconds** without touching scooter controls.
9. Finish Capture **once** while still stationary.
10. Export the prepared versioned JSON unchanged. If the provenance sidecar/manifest capability is available, export/preserve it with the exact JSON bytes.
11. End the experiment. Do not immediately add a decoder or send a write from the phone.

## What to preserve

Keep together:

- exact versioned capture JSON bytes;
- exact Nembra Git commit/build identity;
- selected observed CoreBluetooth peripheral identifier;
- capture start/end context;
- explicit state: `stationary`, `charger disconnected`, `foreground`, `screen remained on`;
- any generated stationary-capture manifest/sidecar;
- any failure diagnostic shown by Nembra;
- no manually reconstructed packet data.

If a second reference device was used, record that setup separately. A stock-app number remains a correlation anchor only; it is not raw protocol proof.

## Offline acceptance questions

The first artifact is useful if offline tooling can answer these questions from captured evidence without inventing semantics:

1. Which advertisement identifiers/data were actually observed for the selected target?
2. Which GATT services, included services, characteristics, descriptors, and characteristic properties were observed?
3. Does the physical target expose a researched transport candidate such as modern Tuya `FD50`, legacy `1910`, or something else?
4. Which characteristics produced read responses and which produced subscription updates?
5. Which raw value streams changed or repeated during the stationary 60-second window?
6. Were there any continuity breaks, topology invalidations, acquisition failures, or target-attribution ambiguities?
7. Does the artifact contain enough explicit target evidence to distinguish `target absent/unknown` from `target observed but no candidate match`?

These answers may promote facts only to **OBSERVED ON PHYSICAL TARGET** / **PHYSICAL EVIDENCE PRESENT** where the raw artifact supports them. They do not yet establish battery, voltage, current, watts, speed, odometer, charging, command, or acknowledgement semantics.

## Pass / fail result

### PASS — usable first physical fingerprint

Only if:

- finite acquisition reached the controller's accepted ready state;
- export completed from one immutable target-scoped artifact;
- target attribution is non-ambiguous under the capture/analyzer policy;
- no capture-integrity failure occurred;
- the phone stayed foreground with no known suspension/background gap;
- the raw artifact can be opened by Nembra's offline tooling.

A pass means: **Nembra has a usable passive physical fingerprint artifact for the selected observed target.**

It does **not** mean: **Nembra has decoded the ES80 protocol.**

### FAIL / RETRY REQUIRED

Retry later with a fresh session if:

- the selected candidate was physically ambiguous;
- finite acquisition never became ready;
- capture failed closed;
- the phone locked/backgrounded or continuity is uncertain;
- Bluetooth became unavailable during the required acquisition window;
- export failed or the raw file changed after export;
- provenance cannot be tied to the exact build and selected observed target.

Do not patch a failed artifact into a pass.

## Next step is evidence-driven

Do **not** preselect a battery/current/power DP before reviewing this artifact.

After offline analysis, choose exactly one next correlation experiment based on the strongest observed raw stream and transport evidence. For example, if a stable target-scoped value stream exists and the physical setup can legitimately expose a known stock-app reference on a second device, the next experiment can correlate one safe stationary state change or one reference value against that stream.

Until raw source, scaling, units, signedness, cadence, and provenance are verified, stock-app battery %, voltage, amps, and watts remain correlation anchors rather than production telemetry authority.