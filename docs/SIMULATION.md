# Simulation workflow

Nembra's Simulator backend conforms to the same `ScooterService` contract as the future Bluetooth implementation. Simulation state is development evidence only and must never be persisted into real ride history.

Simulation is **opt-in only**. An ordinary app launch does not use this backend; it uses the hardware-gated `UnverifiedScooterService` until the real MAXSHOT Bluetooth configuration is verified.

## Launch scenarios

For Xcode/Simulator QA, set either the environment variable:

`NEMBRA_SIMULATION_SCENARIO=<scenario>`

or a launch argument:

`--nembra-simulation=<scenario>`

Configuration is intentionally fail-closed. The environment variable has priority when present; if its value is invalid, Nembra does **not** fall through to a launch argument. Missing values, unknown scenario names, and duplicate simulation launch arguments are rejected. In those cases the app uses the hardware-gated unverified production service rather than guessing a QA state.

Supported Home-focused scenarios:

- `cold-disconnected` — no cached telemetry; mode/battery/vehicle values remain unknown
- `reconnecting` — last-known telemetry exists while the connection is recovering
- `connected-stopped` — normal connected stationary vehicle
- `riding` — connected vehicle with nonzero speed/power and headlight on
- `low-battery` — connected, locked, low-battery Eco state
- `bluetooth-off` — Bluetooth powered off; no fake retry success
- `permission-denied` — Bluetooth permission denied; Home offers the app Settings recovery path
- `scooter-unavailable` — scooter not found with retained last-known vehicle data; explicit retry can recover in simulation
- `unsupported-configuration` — unknown/unverified hardware or firmware; controls remain unavailable

Disconnected/reconnecting/error launch scenarios deliberately disable the default automatic connect call so those states remain stable long enough for UI inspection. Connected scenarios begin connected.

When `cold-disconnected` is explicitly reconnected in simulation, the simulated successful handshake fills previously unknown vehicle fields from the connected-stopped QA fixture. A reconnect from a retained-data state preserves the retained values and fills only genuinely missing fields; it does not reset battery/odometer/trip/mode to generic defaults. This is simulator behavior only, not a claim about MAXSHOT packet order.

## Why launch configuration instead of a fake production control panel?

The normal vehicle UI should not contain developer-only switches just to make screenshots easy. Launch scenarios provide reproducible states for Simulator screenshots and UI tests without contaminating the product hierarchy.

Future protocol diagnostics can have an explicit developer/advanced area once real Bluetooth inspection begins.

## Command-safety behavior
Simulation intentionally models conservative command semantics: one state-changing command at a time, delayed acknowledgement, command failure if the link drops before confirmation, and connection-generation invalidation so a fast reconnect cannot validate an old write. This is part of QA, not merely animation latency.


## Raw speed evidence
The simulator also emits an opt-in raw `SpeedTelemetrySample` stream for telemetry benchmarking. It emits only samples created after subscription; it does not replay the cached `VehicleState.speedKilometersPerHour` as if a new BLE packet arrived. Simulation timestamps are monotonic and deterministic so cadence/jitter tests can be repeatable.
