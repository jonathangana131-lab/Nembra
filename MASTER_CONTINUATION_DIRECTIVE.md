# NEMBRA MASTER CONTINUATION DIRECTIVE

This file is the stable, permanent product and engineering charter for the existing production iOS application **Nembra** in `jonathangana131-lab/Nembra`.

It is intentionally phase-agnostic. Changing milestone state belongs in `PROJECT_STATE.md`; exact resume instructions belong in `CONTINUATION_PROMPT.md`; durable architecture decisions belong in `DECISIONS.md`; hardware/protocol evidence belongs in `PROTOCOL_NOTES.md`; visual principles belong in `DESIGN_SYSTEM.md`.

## 1. Source of truth and recovery

Authoritative order:
1. current source code at the newest relevant GitHub head
2. current open PR / active branch state
3. recent commits
4. current GitHub Actions / Xcode runs
5. `PROJECT_STATE.md` from the active branch
6. `CONTINUATION_PROMPT.md` from the active branch
7. `DECISIONS.md`
8. `PROTOCOL_NOTES.md`
9. `DESIGN_SYSTEM.md`
10. relevant `docs/`
11. this permanent charter

GitHub wins over stale prose. Never move backward because an old document names an earlier phase.

Fresh-chat boot sequence:
- inspect repository/default head
- inspect open PRs, branches, newest commits, and newest Actions/Xcode runs
- identify the actual active branch/PR/head
- only then read project-memory files from that active head
- reconcile documentation against live GitHub
- identify and resume the exact unfinished action
- do not ask the user to summarize the previous chat

## 2. Continuous standard-chat execution

This project is intentionally developed in standard Chat with connected GitHub and external Xcode/GitHub Actions infrastructure.

Before a final response, ask internally: **Is there another concrete tool action that can safely advance Nembra right now?** If yes, do it instead of finalizing.

A phase boundary is an engineering boundary, not a conversation boundary. The normal sequence is implementation → tests → real Simulator evidence → fixes → checkpoint → exact-head gate → merge → inspect fresh main → begin the next meaningful slice.

Do not voluntarily stop merely because a build, screenshot, commit, PR, gate, merge, or phase completed. Git checkpoints protect progress from platform interruption; they are not stopping points.

Narration stays short. Prefer coherent batches of actions and targeted reads. Do not waste the active reasoning window on repeated polling, enormous logs, redundant summaries, fake tests, or meaningless commits. While CI runs externally, do safe independent work in the same slice; check CI again after useful work.

If the platform forcibly terminates execution, the next continuation begins by inspecting live GitHub state and immediately resuming the unfinished operation.

## 3. Product mission and primary vehicle

Product: **Nembra**.

Primary real vehicle and first hardware-validation target: **AOVOPRO ES80**.

The previously modeled **MAXSHOT V1S Pro** remains a deferred/unverified supported profile candidate. Preserve reusable MAXSHOT abstractions, capability-driven architecture, tests, simulation work, and generic vehicle code; do not delete or rebuild accepted systems simply because the primary physical scooter changed.

Future statements that distinguish **implemented in software** from **verified on real hardware** must use the **AOVOPRO ES80** as the primary hardware-validation target unless explicitly discussing another vehicle.

Nembra is a premium native iOS scooter companion platform. It should feel like a focused combination of first-party iOS quality, premium EV software, and serious electric-motorcycle instrumentation while retaining its own identity.

It should feel native, fast, tactile, reliable, fluid, vehicle-focused, deeply interactive, technically honest, and carefully hierarchical. It must not feel like a generic Tuya IoT dashboard, cross-platform port, gamer RGB utility, arbitrary SwiftUI card mosaic, or developer diagnostics surface presented as product UI.

## 4. Platform and architecture

Use current Apple-native technology where appropriate: Swift, SwiftUI, Observation, structured concurrency, CoreBluetooth, CoreLocation, CoreMotion, MapKit, ActivityKit, WidgetKit, App Intents, SwiftData, CloudKit, Sign in with Apple, SF Symbols, modern haptics, accessibility APIs, and current iOS 27 visual/material APIs. Verify current SDK/documentation instead of assuming old API behavior.

Maintain strong separation between:
- presentation/UI
- vehicle domain state
- commands
- telemetry
- Bluetooth transport
- protocol decoding
- ride application runtime
- ride evidence
- persistence
- location/maps/navigation
- battery/range domain
- cloud/community
- simulation

SwiftUI views do not become BLE protocol implementations. Use capability-driven vehicle profiles/services. Simulation and hardware share the same high-level production domain interfaces. Avoid giant global invalidation trees; keep high-frequency rendering localized.

## 5. Truthfulness model

Never fabricate speed, battery percentage, range, voltage, current, power, throttle, torque, motor/controller temperature, regen, phase current, acceleration source, GPS quality, Bluetooth acknowledgements, protocol semantics, or route geometry.

Conceptually distinguish **measured**, **estimated**, **interpolated for display**, **derived**, and **unknown**. Interpolated frames are never telemetry evidence. Motion estimates never silently become authoritative scooter speed. Disconnect never manufactures a zero measurement.

Simulator success is software/runtime evidence, not real AOVOPRO ES80 hardware validation. Keep **implemented in software** separate from **verified on real hardware**.

## 6. AOVOPRO ES80 BLE / Tuya protocol safety

The AOVOPRO ES80 is the primary real protocol research target. Preserve generic transport/profile abstractions so MAXSHOT and other scooters can remain future capability profiles.

Real motorized-hardware writes require evidence. Follow discover → observe → subscribe → read → capture → correlate with known stock-app behavior → decode → validate → cautiously write.

Track findings as VERIFIED / PROBABLE / UNKNOWN. Never send random bytes.

Primary ES80 hardware research includes advertisement identity, services, characteristics/properties, notification behavior, speed cadence/latency/jitter/resolution, packet framing/checksums, read/write behavior, acknowledgements, firmware behavior, Tuya data-point semantics, battery/ODO/trip/mode/lock/light/cruise/start-mode/limits, and AccessorySetupKit identity/descriptors where applicable.

Only expose vehicle controls verified to exist. Command UI should prefer requested → pending → scooter acknowledgement/state update → confirmed. A tap is never proof the scooter changed.

MAXSHOT-specific hardware validation is deferred. Preserve its existing notes/code as unverified/deferred evidence rather than treating it as the first physical target.

## 7. Dashboard, speed, rolling values, and mode personality

Landscape Dashboard is a signature purpose-built cockpit, not portrait Home rotated. It should prioritize truthful huge speed, ride mode, battery, range estimate when legitimate, live trip distance, ride duration, connection/model identity, navigation when active, and useful scooter state. State-changing controls should not encourage manipulation while moving.

Determine scientifically which trustworthy source gives the best real-time speed. Measure AOVOPRO ES80 BLE and GPS behavior; Core Motion may provide short-horizon responsiveness clues but cannot drift into authoritative speed. Measurement rate and display rate are distinct. A 60 Hz display may interpolate 10 real packets/sec, but those intermediate frames are not packets and never feed ride evidence.

Important changing values such as MPH, trip, ODO, battery percentage, and estimated range should support polished rolling behavior with stable width, correct direction, no flicker/geometry jumps, interruption-safe transitions, accessibility, Reduce Motion support, and excellent performance.

Confirmed ride mode may subtly change cockpit personality. Walk/Eco/Drive/Sport can alter presentation hierarchy/energy, not imply unverified power, torque, acceleration, range, or speed-limit behavior.

## 8. Battery evidence, displayed SoC, and signature battery instrument

Battery is a major Nembra system and must use one authoritative battery domain across Home, landscape Dashboard, live ride, ride history, future Live Activity, widgets, vehicle detail, and charging state.

For the AOVOPRO ES80, the stock Tuya application visibly reports battery percentage. Reverse engineering must explicitly determine the source and behavior of that value:
- which BLE/Tuya data point or characteristic supplies battery information
- whether the scooter directly transmits a true 0–100 percentage
- percentage resolution and quantization
- update frequency and latency
- behavior while riding
- whether values jump in large increments
- whether voltage is also exposed
- whether charging state is exposed
- whether Tuya calculates percentage rather than receiving it directly
- behavior under acceleration/load and after stopping

Do not assume Tuya's displayed percentage is raw 1%-resolution hardware telemetry until packet evidence proves it.

Maintain distinct concepts:
- **RAW BATTERY EVIDENCE**
- **MEASURED SoC**
- **ESTIMATED SoC**
- **DISPLAYED / ANIMATED SoC**
- **UNKNOWN**

Presentation interpolation or estimation never becomes hardware evidence and must not be persisted as if the scooter measured it.

If ES80 hardware proves a useful true 0–100 percentage, use it as authoritative SoC, update immediately on new measurements, and animate visual changes through rolling integer transitions without fabricating intermediate telemetry packets.

If authoritative percentage is real but slow/coarse, Nembra may maintain a live **estimated** SoC between measured anchors using only legitimate evidence such as prior measured percentages, elapsed ride time, real distance, learned consumption, verified voltage, and empirically supported mode effects. Reconcile gently at new measured anchors unless safety requires immediate correction.

If voltage is exposed, research the real ES80 battery configuration/chemistry and handle voltage sag, load/rest recovery, filtering, and hysteresis. Hard acceleration must not cause absurd visible battery oscillation. Never linearly map instantaneous sagging voltage to precise SoC or range without evidence.

If only bars are exposed, do not fabricate precise percentage.

Battery history may retain measured start/end SoC, verified voltage evidence, lowest meaningful observed voltage, distance, duration, mode evidence, and other legitimate inputs. Do not persist every display-estimated frame as telemetry.

Battery becomes a signature visual system during the mandatory Production Visual Overhaul: large crisp percentage/range, premium original EV-style battery graphic, synchronized smooth fill, rolling integer changes, excellent low-battery behavior, verified charging treatment, no generic Tuya progress bar, and no fake precision.

## 9. Tesla-style adaptive remaining range — original Nembra behavior

Estimated remaining range is a serious Nembra vertical slice, not a formula in a SwiftUI view.

The primary battery instrument must be directly tappable to toggle:
- **battery percentage**
- **estimated remaining range**

Example interaction: battery icon + `73%` → tap → battery icon + `8.4 mi` → tap → `73%`.

The battery fill continues to represent charge level in both modes. The user's selected representation should remain consistent across relevant Home, Dashboard, and live-ride surfaces where appropriate. Do not require Settings for this toggle. A future secondary/long-press interaction may open detailed Battery information.

Use Tesla as an interaction/quality reference only; do not pixel-copy Tesla UI. Nembra must have its own iOS 27 visual language.

Never estimate range as advertised manufacturer range × battery percentage. Learn the real usable range of **this particular ES80** from actual riding and battery consumption.

When percentage is the best available evidence, learn from meaningful battery windows rather than noisy 1% changes. Evidence may relate actual distance to authoritative percentage consumed across useful windows such as 5%, 10%, 20%, or larger, with the exact minimum window chosen only after real ES80 battery behavior is measured.

Range prediction should combine:
- recent riding behavior for responsiveness
- long-term learned ES80 behavior for stability
- authoritative battery percentage
- verified battery voltage where available
- real distance and recent distance
- recent battery consumption
- current/recent speed
- verified ride mode only when its effect is empirically supported
- legitimate elevation/hill evidence where location/elevation quality supports it
- historical efficiency and observed aging

Never invent unavailable current, watts, power, Wh/mi, or other sensors just to improve the model.

Maintain one domain model conceptually containing:
- `RAW BATTERY EVIDENCE`
- `MEASURED SOC`
- `ESTIMATED SOC`
- `DISPLAY SOC`
- `EFFICIENCY MODEL`
- `ESTIMATED RANGE`
- `RANGE CONFIDENCE`

The range estimator must include smoothing, hysteresis, recent-vs-historical weighting, outlier rejection, minimum useful evidence windows, confidence, and special low-battery handling. It should adapt while riding without oscillating wildly.

Cold start must be conservative and explicitly low-confidence internally. As useful ES80 history accumulates, progressively replace provisional behavior with learned real-world behavior. Internal/product states may include Learning, Low confidence, Normal confidence, and High confidence; normal cockpit UI need not spam technical confidence numbers.

Persist the learning evidence across launches. Bad/incomplete rides must not poison the model.

Low SoC may be nonlinear. If real ES80 testing shows 20→0 behaves differently from 80→60, model that behavior and bias conservative near cutoff rather than stranding the rider.

Over time Nembra may estimate typical full-charge range and gradual degradation from sufficient history. Prefer honest outputs such as `Typical full-charge range 11.2 mi`; do not claim precise battery State of Health unless genuine capacity/energy evidence supports it.

If verified current/power/energy telemetry later exists, the architecture may evolve toward energy-based efficiency such as Wh/mi. Do not calculate or show fake Wh/mi before the required inputs exist.

Deterministic range-model tests must eventually cover: no history, normal efficiency, high consumption, very efficient riding, sudden style changes, noisy/sparse percentage updates, reconnect gaps, incomplete rides, low battery, long-term aging, and voltage sag when voltage exists. Tests must prove adaptation, stability, evidence integrity, historical learning, and conservative weak-confidence behavior.

## 10. Automatic rides, recovery, history, and reconciliation

Ride tracking is central and should not require remembering a Start button. Preserve the accepted `RideEngine` architecture and robust automatic state machine semantics. Use authoritative scooter/GPS/ODO/motion evidence according to injected policy.

Ride lifetime is application/domain lifetime, not SwiftUI view lifetime. Normal app backgrounding, screen locking, and process recovery must not silently split one legitimate ride. Persist enough state for crash recovery and preserve durable ride identity where valid.

Completed rides are immutable high-quality records containing only available evidence. Never claim unavailable route, battery, duration, distance, or telemetry.

ODO is critical. Prefer authoritative scooter ODO where verified. Track source coverage separately; never blindly average ODO, GPS, and integrated speed. Reconciliation must be policy-driven and truth-preserving.

Live distance may update visually smoothly while underlying evidence remains separate. Display interpolation never becomes accumulated evidence.

Eventually provide trustworthy period statistics only from real persisted rides.

## 11. Maps and navigation

Use native MapKit. Live ride maps may show route behind the rider, smooth position, heading-aware camera, recentering, and ride metrics when real coordinates exist. Completed ride maps may show recorded route/start/end and evidence-backed metrics. No recorded coordinates means no fake geometry.

Navigation is deeply integrated with landscape Dashboard. Starting navigation should rearrange the cockpit dynamically while keeping speed primary. Ending navigation restores the normal cockpit smoothly. Research current Apple routing APIs. Never claim a walking/cycling route is guaranteed legal or suitable for an e-scooter.

Background location is tied to legitimate ride behavior; do not run highest-accuracy GPS continuously when not needed.

## 12. Background Bluetooth and reconnect

After legitimate initial configuration, reconnect to a known AOVOPRO ES80 as automatically as iOS permits. Research current iOS 27 behavior for `bluetooth-central`, CoreBluetooth preservation/restoration, known peripherals, pending connections, restored subscriptions, relaunch, eviction, reboot, Bluetooth toggles, and force-quit. Explicitly document platform limitations rather than promising impossible behavior.

## 13. Acceleration tests and drive visualization

Eventually support polished 0–10/15/20/top-speed tests using the best verified evidence combination and detect invalid rolling starts, interruptions, connection failures, and weak measurement conditions. Never report fake precision.

If real throttle/power/current exists, an EV-style intensity visualization may represent it. Otherwise use honest derived terms such as Acceleration, Deceleration, or Drive Intensity rather than falsely labeling a gauge Throttle or Power.

## 14. Home, vehicle graphics, community, privacy, and cloud

Portrait Home should rapidly answer scooter identity, connection, lock, battery/range, mode, current status, ride/trip context, and recent ride context. Avoid card soup and decorative art that displaces important state.

Vehicle graphics must be original and based on real hardware references; do not invent physical features. Use them purposefully for identity/state, not as implementation proof.

Community/leaderboards may eventually show safe aggregate rank, chosen identity, vehicle, distance/time/rides. Precise routes, home, exact start/end, and full GPS history are private by default. Exact route sharing requires deliberate user choice.

Public rankings should not blindly trust editable local values; apply evidence-backed anti-cheat when justified, without overbuilding it before core product quality.

Core scooter control and local ride history must remain offline-capable and should not require social login. For cloud/community identity prefer Apple-native approaches such as Sign in with Apple and CloudKit where appropriate.

## 15. System integration

Once core behavior is excellent, add Live Activities, Lock Screen/Dynamic Island, widgets, App Intents, Shortcuts, Spotlight, and Controls only where they provide genuine value. Battery/range representation should derive from the same authoritative domain across those surfaces rather than duplicating formulas.

## 16. Simulation and diagnostics

Maintain a strong Simulator backend that drives the real production UI/domain path and covers disconnected/connecting/connected/reconnecting/stopped/riding, speed, battery, ODO/trip, modes, light/lock/cruise/start mode/limits, rides, GPS routes, disconnect gaps, recovery, navigation, acceleration tests, battery/range learning, and errors as those systems exist.

Simulation records must never contaminate production records.

Developer diagnostics may expose peripheral identity, RSSI, services, characteristics, notifications, packet rate/data, decoded packets, latency, reconnect history, firmware, and raw battery evidence. Normal users should not need diagnostics UI.

## 17. Performance and accessibility

Explicit baseline: iPhone 12. Target excellent 60 Hz behavior. Pay special attention to huge Dashboard speed, rolling digits, live telemetry, battery/range transitions, maps/route drawing, long ride lists, charts, and background work. Avoid giant SwiftUI invalidation trees, full-screen timer refreshes, excessive blur, unnecessary `GeometryReader` nesting, main-thread protocol parsing, and needless high-frequency published state. Profile real bottlenecks rather than imagined ones.

Maintain VoiceOver, useful labels, touch targets, contrast, sensible Dynamic Type, Reduce Motion, and orientation behavior. Specialized Dashboard typography can be visually custom while exposing correct accessibility semantics.

## 18. Error states

Polish truthful states for Bluetooth off, scooter unavailable/out of range, denied Bluetooth/location permission, poor GPS, battery evidence unavailable/stale, low range confidence, cloud unavailable, malformed packet, unsupported firmware/characteristic, command timeout, interrupted/recovered ride, ODO discrepancy, and persistence failure. Never hide meaningful uncertainty behind fake Connected/Success UI.

## 19. Mandatory Xcode / Simulator QA

For important vertical slices use the real loop: research → design → architect → implement → build → run → interact → capture → inspect → fix → edge-test → profile if relevant → test → checkpoint/push → accept → merge → continue.

Use iPhone 12 / iOS 27 Simulator evidence. Source review alone is not acceptance. Compile success alone is not acceptance. One attractive screenshot is not acceptance.

Inspect real screenshots for clipping, hierarchy, typography, cramped rails, wasted space, excessive empty areas, card soup, awkward materials, safe areas, tiny controls, inconsistent spacing, weak speed dominance, ugly transitions, and imbalance. Visible problems should be fixed rather than rationalized.

GitHub-hosted `xcode-27` is authoritative remote Mac/Simulator evidence when direct interactive Xcode tooling is unavailable, but it is not physical AOVOPRO ES80 BLE/GPS validation or physical iPhone 12 performance profiling.

## 20. Mandatory Production Visual Overhaul release gate

Current systems-era Home/Dashboard/history UI is intermediate functional implementation, not final visual acceptance.

Once enough truthful foundational dependencies exist—especially battery/SoC, adaptive range, live ride/trip state, maps/navigation, completed rides, and confirmed vehicle/error states—perform a dedicated major product-design overhaul.

Final target: world-class native iOS 27, premium EV instrumentation, huge gorgeous rolling MPH, signature tappable battery/range instrument, dynamic navigation cockpit, elegant ride metrics, polished mode personality, original scooter-aware visuals, restrained native depth/materials, excellent typography/animation/haptics/accessibility, minimal wasted space, no developer-dashboard appearance, no giant empty black regions, no generic card mosaic, and no placeholder rails.

Required loop for each major screen: current real Simulator screenshot → critique → redesign → implement → run → screenshot → critique → repeat.

Cover Home, Dashboard with/without navigation, active ride, battery/% ↔ range toggle, charging/low-battery, ride history/details/maps/stats, leaderboard when present, controls/settings, and major error/recovery states.

A technically correct screen that looks mediocre is not final.

## 21. GitHub workflow and completion

Use meaningful branches for major slices; keep `main` stable; use meaningful commits; push/checkpoint often enough to survive platform interruption; use PRs and exact-head gates where useful. Do not merge merely because code compiles. Merge only after required current-lineage tests/QA pass.

After merge, immediately inspect fresh `main` and begin the next meaningful slice unless a real dependency blocks it.

Nembra is not complete because menus exist. Product completion eventually requires strong native architecture, verified AOVOPRO ES80 support, truthful protocol integration, excellent Home/Dashboard, responsive speed/rolling instruments, battery/adaptive range, automatic rides and crash recovery, background continuity within iOS limits, ODO reconciliation, maps/routes/navigation, statistics, acceleration tests, appropriate cloud/community/privacy/anti-cheat, diagnostics, offline behavior, errors, accessibility, performance, automated tests, real Simulator QA, real ES80 hardware validation, final visual overhaul, and release documentation.

Maintain separate completion labels for **APP IMPLEMENTATION COMPLETE** and **HARDWARE VALIDATION COMPLETE**. Never falsely claim either.