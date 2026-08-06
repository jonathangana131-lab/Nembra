# Speed telemetry architecture

Updated: 2026-08-06

## Non-negotiable truth model

Nembra keeps these layers separate:

1. **Raw evidence** — immutable speed samples emitted by BLE, Core Location, or a bounded motion-assisted estimator.
2. **Benchmark/quality diagnostics** — cadence, jitter, empirical resolution, delivery latency when a source timestamp exists, and rejected/out-of-order counts.
3. **Fusion/estimation** — future logic that may choose or combine evidence for a best current estimate.
4. **Display interpolation** — render-time animation that may visually move between trustworthy estimates at the display refresh rate.

Display interpolation must never be fed back into raw telemetry, ride evidence, benchmark statistics, odometer reconciliation, or acceleration-test timing as though it were measured data.

## Raw sample contract

`SpeedTelemetrySample` records:

- source (`scooterBluetooth`, `gps`, `motionAssist`)
- provenance (`absoluteMeasurement` or `shortHorizonEstimate`)
- SI speed in meters/second
- monotonic receive timestamp in uptime nanoseconds
- wall-clock receive date
- optional source measurement date
- optional speed accuracy in meters/second

BLE and GPS samples are required to be absolute measurements. Motion assist is structurally restricted to `shortHorizonEstimate`; it cannot claim authoritative speed.

The monotonic timestamp is the source of truth for arrival ordering and interval measurements. Wall-clock time is never used to calculate packet cadence because the user/system can adjust wall time.

A raw sample's `receivedAtUptimeNanoseconds` means **when that packet/evidence entered Nembra**, not how much simulated ride time or trip distance the packet represents. Producers and renderers that compare uptime must share the same process monotonic clock domain.

## Benchmark output

`TelemetryBenchmarkCollector` uses constant memory and reports:

- accepted sample count
- rejected sample count
- interval count
- observed duration
- effective sample rate (Hz)
- mean/min/max arrival interval
- interval jitter (population standard deviation)
- duplicate speed-value count
- smallest observed nonzero speed step
- delivery-latency sample count
- mean/min/max delivery latency
- delivery-latency standard deviation

A collector is source-specific; trying to mix GPS into a BLE collector is rejected.

Out-of-order or duplicate monotonic timestamps are rejected rather than silently reordering history.

## Latency limitations

A BLE notification that contains no device-side measurement timestamp does **not** let Nembra claim end-to-end sensor latency. In that case we can truthfully measure arrival cadence/jitter and app-side processing latency later, but not the controller's internal sampling delay.

Core Location can expose a measurement timestamp, so delivery latency can be estimated by comparing that timestamp with receive time. Negative wall-clock deltas are treated as unknown, not as negative latency.

## Simulation

`SimulatedScooterService` conforms to the same `SpeedTelemetryProvider` contract future real BLE will use.

Important behavior:

- subscribing does not replay cached vehicle speed as a new measurement
- `simulateRide` emits one raw scooter-Bluetooth sample per simulated measurement step
- the raw sample receive timestamp comes from the process monotonic uptime clock used by the Dashboard renderer
- supplied `elapsedSeconds` advances simulated ride distance/time evidence only; it never pretends that a packet arrived minutes later than it actually did
- if two simulated samples occur within one clock tick, the service advances the second timestamp by the minimum amount required to preserve strict monotonic ordering
- numeric overflow inputs are rejected before they can poison odometer/trip state

This preserves truthful raw-arrival semantics while allowing ride-distance fixtures to jump forward deterministically. A regression test checks that a simulated raw sample lands within the real process-uptime window around its emission.

Simulation timing is not MAXSHOT timing. It exists to exercise the presentation system before physical scooter packet cadence is captured.

## Real-hardware benchmark procedure (pending hardware access)

For each source, capture a long enough steady run to characterize it rather than judging from a few packets. Record at minimum:

- stationary behavior
- walking/very-low-speed behavior
- launch acceleration
- steady mid-speed riding
- deceleration to zero
- reconnect after brief signal loss

For scooter BLE, measure notification arrival intervals and speed quantization first. Do not assume 5 Hz, 10 Hz, 20 Hz, or another cadence before observing it.

For GPS, record `speed`, `speedAccuracy`, source timestamp, receive timestamp, low-speed invalid/negative-speed behavior, and weak-signal behavior.

For Core Motion, evaluate only bounded short-horizon assistance around authoritative BLE/GPS samples. Never integrate acceleration indefinitely into an absolute speed claim.

## Dashboard decision gate

No interpolation/fusion constants should be tuned to imaginary MAXSHOT packet rates. The eventual Dashboard strategy must be selected from measured hardware traces. A 60/120 Hz visual render loop may interpolate between reliable estimates, but the raw evidence cadence remains exactly what the sensors produced.

## Render-only interpolation

`SpeedDisplayInterpolator` is intentionally conservative:

- the first authoritative speed sample renders immediately rather than animating from a fake zero
- a new sample arriving mid-transition starts from the exact currently rendered value
- acceleration and deceleration are both bounded between the previous visual value and newest measurement; no overshoot
- repeated measured values create no fake animation
- zero-duration transitions snap exactly to the newest measurement
- out-of-order measurements are rejected
- motion-assisted estimates cannot enter this authoritative interpolator
- every `SpeedDisplayFrame` carries both the visual value and the latest measured value, plus an origin flag (`measured` vs `visuallyInterpolated`)

The interpolator does not predict future speed. Final transition duration is supplied by its caller and must be tuned from real MAXSHOT benchmark traces plus iPhone 12 Simulator/device visual QA. No production timing constant is claimed yet.

## Phase 10 Dashboard presentation policy

`SpeedInstrumentModel` and `DashboardSpeedInstrumentView` are the iOS presentation boundary around the core interpolator.

Rules:

- ordinary/unverified production launch injects `SpeedInstrumentInterpolationPolicy.disabled`; real MAXSHOT samples therefore snap until hardware timing is measured
- explicit Simulator QA launch injects `.simulatorQA` only to exercise visual behavior; its constants are test presentation values, not hardware claims
- the speed subtree may render on a SwiftUI animation timeline capped at 60 Hz while a transition is active
- that timeline is paused when no interpolation window is active, avoiding a permanent whole-app/high-frequency refresh loop
- Dashboard side rails, controls, ride logic, distance, history, and safety continue to consume confirmed/raw domain state rather than interpolated frames
- a telemetry gap beyond the injected continuous-sample limit snaps instead of visually bridging missing evidence
- VoiceOver announces the newest authoritative/confirmed speed, never an interpolated midpoint that no sensor measured

The Simulator and the Dashboard renderer must use the same monotonic uptime clock domain. This is required for an animation window to represent elapsed render time correctly.

## Rolling numeric presentation

`RollingNumberModel` consumes a display value after speed interpolation; it does not consume raw sensor packets directly. It produces a fixed-width digit transition plan for SwiftUI.

Rules:

- integer slots are reserved even when leading digits are visually hidden, preventing width jumps
- fractional digit count is fixed by the chosen layout
- upward values drive upward digit motion, including carry transitions such as 19→20
- downward values drive downward digit motion, including borrow transitions such as 20→19
- leading slots appear/disappear within reserved geometry for transitions such as 9↔10
- equal values create no digit motion
- the model has no animation duration, easing, sensor source, or persistence semantics
- final SwiftUI timing remains a runtime design decision validated on iPhone 12/iOS 27

This is presentation state only. It must never be fed into telemetry benchmarks, acceleration timing, ride distance, odometer reconciliation, or persistence as a measurement.
