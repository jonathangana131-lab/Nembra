# AOVOPRO ES80 Battery + Adaptive Range

Status: permanent product/engineering contract. Hardware behavior remains unverified until real ES80 captures prove it.

## Product target

The AOVOPRO ES80 is Nembra's primary real scooter target. Battery/range must become one of Nembra's signature systems and must feel like a premium EV instrument while remaining technically honest.

The stock Tuya app visibly shows a battery percentage. That observation proves a user-facing percentage exists somewhere in the stock stack; it does **not** prove the scooter directly transmits a true 1%-resolution 0–100 SoC.

## Hardware battery investigation

Real ES80 capture must determine:
- BLE/Tuya DP or characteristic carrying battery information
- whether percentage is transmitted directly or derived by Tuya
- percentage resolution/quantization
- update frequency and latency
- whether it updates while riding
- whether it freezes then jumps several points
- whether pack voltage is exposed
- whether charging state is exposed
- behavior under acceleration/load
- recovery after stopping/rest
- low-SoC/cutoff behavior
- firmware/batch differences

Do not promote any of those items to VERIFIED without packet/GATT evidence.

## One battery/range domain

All relevant product surfaces derive from one authoritative battery/range domain:
- portrait Home
- landscape Dashboard
- live ride
- ride history
- future Live Activity
- future widgets
- vehicle detail
- charging state

Conceptually preserve:
- RAW BATTERY EVIDENCE
- MEASURED SOC
- ESTIMATED SOC
- DISPLAY SOC
- EFFICIENCY MODEL
- ESTIMATED RANGE
- RANGE CONFIDENCE
- UNKNOWN

Presentation animation/estimation must never contaminate raw telemetry evidence.

## Measured versus displayed SoC

If hardware proves a true/useful 0–100 percentage:
- use it as authoritative measured SoC
- accept new anchors immediately
- animate visual transitions through integer rolling values where appropriate
- synchronize battery-fill animation
- never fabricate intermediate telemetry packets

If authoritative percentage is legitimate but slow/coarse:
- the display layer may estimate smoothly between measured anchors
- the estimator may use only legitimate evidence such as previous measured anchors, elapsed ride time, real distance, verified voltage, learned consumption, and empirically supported mode behavior
- classify the live value internally as ESTIMATED
- reconcile gently to new measured anchors unless safety requires immediate correction
- do not persist every display-estimated percentage as hardware telemetry

If only bars exist, do not invent precise percentage.

## Voltage and sag

If verified voltage exists, research the real ES80 pack configuration/chemistry before using it for SoC/range corroboration.

Under load, visible battery must not bounce absurdly because of voltage sag. Use evidence-backed filtering/hysteresis/rest behavior as appropriate. Never directly convert an instantaneous sagging voltage reading into precise SoC or remaining range.

## Interactive primary battery instrument

Normal tap toggles the primary battery readout:

`73%` ↔ `8.4 mi`

Requirements:
- battery graphic/fill continues representing charge level in both modes
- transition is immediate, elegant, native, and interruption-safe
- use rolling numeric transitions where appropriate
- selected representation should remain consistent across Home, Dashboard, and live ride where appropriate
- no Settings trip is required for the toggle
- a future long-press/secondary interaction may open detailed Battery information

Tesla is a quality/interaction reference only. Nembra must use an original iOS 27 design rather than pixel-copying Tesla.

## Range is learned, not advertised

Never use `advertised range × battery percentage` as the final algorithm.

Core question:

> How much real distance has this specific ES80 historically traveled for the battery energy/percentage it consumed under conditions similar to right now?

When percentage is the best battery evidence, learn from actual distance versus authoritative percentage consumed over meaningful windows. Avoid using one tiny 1% movement as a decisive efficiency sample because quantization/noise can dominate it.

Candidate useful windows may be 5%, 10%, 20%, or larger, but the actual minimum window must be chosen after real ES80 percentage behavior is measured.

## Recent + historical model

Range prediction should combine:
- recent riding behavior for responsiveness
- long-term learned ES80 behavior for stability
- authoritative battery percentage
- real distance
- recent ride distance
- recent battery consumption
- current/recent speed when legitimate
- verified ride mode only when its effect is empirically supported
- legitimate elevation/hill evidence where route/elevation quality supports it
- verified voltage evidence where available
- historical ES80 efficiency
- observed aging/degradation

Do not invent motor current, watts, power, energy, or Wh/mi if the vehicle does not expose the required evidence.

If future verified battery current/power/energy exists, architecture may evolve toward energy-based efficiency.

## Adaptive behavior while riding

Range should respond to material changes in riding style/conditions. Aggressive/uphill riding may progressively reduce predicted remaining distance; slower/more efficient riding may improve it.

Do not let ordinary riding produce wild oscillation. The range estimator must include:
- smoothing
- hysteresis
- recent-vs-historical weighting
- outlier rejection
- minimum useful evidence windows
- confidence
- low-battery handling

Large corrections may happen when new evidence proves the previous estimate wrong, but the normal experience should feel stable and trustworthy.

## Learning this specific scooter

Persist learning across app launches. Over time Nembra may learn:
- typical full-charge real range
- distance per meaningful battery-consumption unit/window
- recent degradation
- efficiency by legitimate speed behavior
- efficiency by verified ride mode
- low-battery behavior
- reserve/cutoff behavior

An older ES80 that now realistically travels less should not continue receiving a manufacturer-era optimistic estimate.

Bad/incomplete rides must not poison the model.

## Degradation language

Do not claim precise battery State of Health unless real capacity/energy evidence supports it.

Prefer evidence-backed outputs such as:

`Typical full-charge range 11.2 mi`

rather than:

`Battery health 83.4%`

when that precision is not justified.

## Low-battery behavior

Do not assume every percentage point contains equal usable energy.

If real ES80 testing shows 20→0 behaves materially differently from 80→60, learn/model the nonlinear region. At very low SoC, slightly conservative range is preferable to an optimistic number that strands the rider.

## Confidence and cold start

With little/no history, range is provisional. Internally support confidence states such as:
- Learning
- Low confidence
- Normal confidence
- High confidence

Normal Dashboard UI need not show technical confidence numbers, but detailed Battery UI may expose confidence elegantly.

As real evidence accumulates, progressively replace provisional behavior with learned behavior.

## Ride-history learning evidence

Where legitimately available, completed rides may contribute:
- measured starting SoC
- measured ending SoC
- distance
- duration
- battery consumed across useful windows
- verified mode evidence
- speed behavior
- route/elevation evidence where legitimate
- verified voltage evidence

Estimated display trajectories may be persisted separately only if genuinely useful and never as measured hardware telemetry.

## Deterministic testing

Treat adaptive range as its own serious vertical slice. Deterministic tests must cover at least:
- new scooter / no history
- normal efficiency
- high-consumption riding
- very efficient riding
- sudden riding-style change
- noisy battery percentage
- sparse battery anchors
- reconnect gaps
- incomplete rides
- low battery
- aging over many rides
- voltage sag when voltage exists

Verify that the model:
- adapts
- does not oscillate excessively
- never uses fake evidence
- improves with useful history
- persists learning
- rejects bad/incomplete evidence
- remains conservative when confidence is weak

## Final design target

Battery/range belongs in the mandatory Production Visual Overhaul. Final experience target:
- large crisp battery percentage or estimated miles
- tap to switch `% ↔ range`
- rolling numeric changes
- premium original EV-style charge graphic
- synchronized smooth fill
- excellent low-battery treatment
- verified charging treatment
- stable learned range
- no generic Tuya progress bar
- no fake precision
