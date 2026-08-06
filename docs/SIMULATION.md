# Simulation workflow

Nembra's Simulator backend conforms to the same `ScooterService` contract as the future Bluetooth implementation. Simulation is development/QA evidence only and is never allowed to masquerade as real MAXSHOT telemetry or production ride history.

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

When `cold-disconnected` is explicitly reconnected in simulation, the simulated successful handshake fills previously unknown vehicle fields from the connected-stopped QA fixture. A reconnect from a retained-data state preserves retained values and fills only genuinely missing fields; it does not reset battery/odometer/trip/mode to generic defaults. This is simulator behavior only, not a claim about MAXSHOT packet order.

## Why launch configuration instead of a fake production control panel?

The normal vehicle UI should not contain developer-only switches just to make screenshots easy. Launch scenarios provide reproducible states for Simulator screenshots and UI tests without contaminating the product hierarchy.

Future protocol diagnostics can have an explicit developer/advanced area once real Bluetooth inspection begins.

## Command-safety behavior

Simulation intentionally models conservative command semantics: one state-changing command at a time, delayed acknowledgement, command failure if the link drops before confirmation, and connection-generation invalidation so a fast reconnect cannot validate an old write. This is part of QA, not merely animation latency.

## Raw speed evidence and clock truth

The simulator emits an opt-in raw `SpeedTelemetrySample` stream for telemetry/application QA.

- only samples created after subscription are emitted; cached `VehicleState.speedKilometersPerHour` is never replayed as if a new packet arrived;
- `receivedAtUptimeNanoseconds` represents actual process-monotonic packet arrival ordering used by the application/render pipeline;
- simulator ride `elapsedSeconds` may advance scenario distance/odometer fixtures, but it **does not manufacture packet-arrival time**;
- back-to-back simulated packets remain strictly monotonic without pretending the scenario's ride-duration delta elapsed in real process time;
- deterministic cadence/jitter benchmark tests that need synthetic timing construct explicit raw telemetry samples with synthetic timestamps rather than making `SimulatedScooterService` lie about arrival time.

This keeps the same raw-speed truth boundary used by the production service contract.

## Phase 12 automatic-ride QA

Explicit simulation now exercises the same root-owned ride application path used by future production composition.

- `AppRuntime` shares one `ScooterService` instance between `VehicleStore` and `RideApplicationStore`.
- the ride store registers both state and raw-speed streams before startup returns.
- the `riding` QA scenario emits one fresh authoritative packet after launch so automatic detection is driven by the real application path instead of cached vehicle state.
- Simulator ride-detection thresholds are injected QA fixtures only; ordinary unverified production launch keeps automatic ride detection disabled.
- state/control acknowledgements cannot replay a previous raw-speed packet into ride evidence.
- reconnect ordering across independent state/raw-speed streams is explicitly tested.

### Isolated Simulator persistence

Phase 12 intentionally persists Simulator ride recovery/history for relaunch QA, but it is physically namespaced away from future production records.

A test may set:

`NEMBRA_SIMULATION_STORAGE_NAMESPACE=<unique namespace>`

The UI relaunch test uses a unique namespace so one run cannot inherit another run's ride journal/history. The persisted record is still explicitly simulation data; it must never be surfaced as real-user production ride history.

The accepted Xcode 27/iOS 27 UI test proves:

1. explicit `riding` launch reaches `Riding automatically` through fresh raw evidence;
2. the app process is terminated;
3. the same scenario/storage namespace is relaunched;
4. the durable session is restored and returns as `Ride resumed` after fresh evidence.

This is real iOS Simulator application/recovery evidence, not physical MAXSHOT background-Bluetooth validation and not a claim that iOS can relaunch after every real-world termination condition.
