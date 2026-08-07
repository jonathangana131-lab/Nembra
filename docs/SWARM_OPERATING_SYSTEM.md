# NEMBRA SWARM OPERATING SYSTEM
CURRENT_PROTOCOL_VERSION: 13
STATUS: ACTIVE
CODENAME: EXTREME-QUALITY PRODUCT CLOSURE

Repository: `jonathangana131-lab/Nembra`
Primary physical target: current/newer Tuya-generation **AOVOPRO ES80**
Baseline: **iPhone 12 / iOS 27**

V13 preserves V12's product-first autonomy and minimal bureaucracy, then raises the quality bar and pushes workers to finish capabilities deeper instead of stopping at clean foundations.

## Prime directive

**BUILD NEMBRA INTO EXCEPTIONAL VEHICLE SOFTWARE.**

Optimize wasted effort, duplicate work, unnecessary process, and reasoning stalls — **never product quality**.

A technically correct feature that looks unfinished is unfinished.
A beautiful feature that lies about telemetry is unfinished.
A fast feature that creates fragile architecture is unfinished.
A perfect foundation that never reaches the user is unfinished.

V13 becomes faster through parallelism, evidence reuse, bounded implementation cycles, and less ceremony — not through weaker engineering, weaker testing, uglier UI, or lower acceptance standards.

## Existing workers migrate in place

Existing V12 workers do **not** restart branches or create migration PRs. Keep coherent source/tests/evidence. At the next natural checkpoint, absorb V13's quality/closure rules and continue the same useful capability. Historical V12 evidence remains valid where content is unchanged.

No feature-cell ceremony, epochs, mandatory captains, release-train bureaucracy, migration spam, or status theater returns under V13.

## Primary loop

`UNDERSTAND PRODUCT → INSPECT LIVE GITHUB → FIND HIGHEST-VALUE NON-CONFLICTING PRODUCT GAP → BUILD → TEST → INTEGRATE → RUN → LOOK → FEEL → PROFILE → POLISH → FIX → SHIP → CONTINUE UP THE FEATURE LADDER`

A commit, passing test, PR, review, merge, or correct domain primitive is a checkpoint, not a normal endpoint. Keep working while the outer platform permits and useful work exists.

After each checkpoint ask: **what is the next adjacent step required for this capability to become genuinely excellent in Nembra?**

## Product-closure ladder

Follow meaningful capabilities upward as far as safely possible:

`DOMAIN/TRUTH → INTEGRATION → PERSISTENCE → APP WIRING → USER EXPERIENCE → VISUAL/MOTION → RUNTIME → ACCESSIBILITY → PERFORMANCE → ADVERSARIAL TESTING → FINAL POLISH`

Do not keep polishing a 98% foundation while the production layer above it is 50%, unless the remaining foundation defect actually blocks correctness or safety.

## Simple collaboration

1. Inspect current `main`, active PRs, and changed paths before choosing work.
2. Avoid active file conflicts unless collaboration is clearly intentional.
3. Own one meaningful product capability deeply rather than scattering across unrelated micro-fixes.
4. Split huge features only across genuinely non-overlapping layers.
5. Prefer coherent product slices over PR soup.
6. When another worker already owns a good solution, do not compete; move to an adjacent layer or bottleneck.
7. If GitHub writes are throttled, keep coding/testing/reviewing and batch useful writes rather than retry-spamming.
8. Do not create process artifacts unless they directly help ship Nembra.

## Critical-path gravity

Continuously compare subsystem maturity and prefer work that closes the largest real product gap or unlocks the most downstream capability.

The AOVOPRO ES80 is Nembra's primary real product target. When meaningful non-conflicting work can move ES80 from mature research tooling toward **verified read-only production telemetry**, that work has high priority over marginal hardening of already-mature unrelated foundations.

Do not pile many workers into the same files. Parallelize ES80 work across independent layers such as passive capture, offline protocol analysis, production read-only bridging, telemetry truth, battery/range consumption, cockpit presentation, physical experiment tooling, and adversarial verification.

## Design north star

Nembra should reach the perceived quality, depth, restraint, hierarchy, tactility, and machine/software unity associated with premium **Stark Future / Stark VARG / Stark phone-style vehicle software and Tesla vehicle OS**, while remaining an original Nembra design.

Do **not** clone copyrighted layouts, assets, icons, animations, trade dress, or brand identity.

Desired language:
- modern flat-first precision with selective depth;
- matte/adaptive dark surfaces, excellent typography and spacing;
- restrained color used for meaningful state, not decoration;
- no gamer RGB, neon-ring sci-fi HUD, card soup, glossy battery tubes, debug-dashboard feel, or fake-premium empty black space;
- strong glanceability while riding;
- deliberate normal and accessibility layouts;
- motion that communicates physical/state response rather than decorative movement.

## Visual acceptance is engineering

For app-visible work:

`SIMULATOR → INTERACT → SCREENSHOT → CRITIQUE → REDESIGN → IMPLEMENT → SCREENSHOT → COMPARE → PROFILE → ACCESSIBILITY → FIX → REPEAT`

A screen is not excellent because it compiles. Running SwiftUI in the target Simulator is the visual source of truth. Generated concept art/static mockups are references, not runtime acceptance evidence.

## Home

Home should feel like opening a premium vehicle companion, not a settings page. Quickly communicate vehicle identity, connection/recovery, battery/range, confirmed mode, known state/controls where legitimate, current trip context, recent ride, and at most one clear action when something actually needs attention.

Keep it compact, confident, tactile, non-duplicative, and visually integrated with the vehicle rather than stacking generic cards.

## Live Ride / Dashboard — flagship surface

The riding cockpit is a signature Nembra experience. It should feel physically connected to the scooter.

Prioritize:
- huge truthful speed;
- signature propulsion/power visualization;
- battery ↔ learned range;
- confirmed ride mode;
- ride distance and observed duration;
- navigation integrated into the same cockpit when active;
- connection/vehicle truth without clutter;
- legitimate peak information;
- sparse safe controls.

Use one dominant primary instrument, a small number of secondary instruments, and context-sensitive detail. Speed, propulsion, battery/range, navigation, mode, and trip context should feel like one machine interface, not unrelated widgets.

## Signature propulsion / power gauge

Build a premium Tesla/Stark-inspired but original Nembra propulsion visualization near the speed instrumentation. It may be a restrained band, arc, line, field, or another original form, but it must be extremely fluid, glanceable, and mechanically connected in feel.

Use the strongest **verified** production signal available. Candidate future physical sources include watts/power, current/amps, voltage, or a safely derived value only after raw source, scaling, units, signedness, cadence, continuity, and provenance are verified.

The target generation's stock Tuya app has been observed displaying battery %, voltage, current/amps, and watts/power. Those are correlation anchors until Nembra verifies underlying transport/DP semantics.

Do **not** label the visualization `throttle` unless a real throttle/demand signal is physically verified. Until then it is propulsion/power.

### Measurement clock vs display clock

The scooter does not need to publish at 60 Hz for the cockpit to render at 60 Hz.

Keep separate:
1. **measurement clock** — accepted physical samples at their real cadence;
2. **display clock** — render-only motion at display refresh rate.

Use a retargetable, bounded, critically-damped or equivalently robust presentation model so gauge motion continuously approaches the latest accepted sample without visual jitter or misleading overshoot.

Interpolated display frames must never become telemetry evidence, persisted samples, acceleration evidence, peak evidence, battery-energy evidence, range-learning evidence, or protocol truth.

Do not extrapolate indefinitely through a data gap. Stale/interrupted/disconnected evidence must transition to truthful retained/unavailable presentation.

### Learned observed full-power envelope

After current/power semantics are physically verified, Nembra may learn a stable per-scooter visual full-power scale from repeated authoritative observations.

This is **not** rated/certified motor maximum. Use concepts like `learned observed power ceiling`, `observed full-power region`, or `learned gauge scale`.

Requirements:
- repeated robust evidence, not one spike;
- high-percentile/sustained upper-envelope behavior plus restrained visual headroom;
- hysteresis so the gauge does not resize constantly;
- upward adaptation when stronger repeated evidence appears;
- much slower evidence-heavy downward adaptation;
- scooter-identity binding;
- mode-specific envelopes only when mode identity is trustworthy;
- preserve real measured watts/amps even when normalized presentation is used;
- do not normalize away low-battery/thermal reduction and call it rated full power.

When accepted live output is legitimately near the learned observed ceiling, the gauge should reach or nearly reach its edge so sustained hard/pinned acceleration visually reads as full output rather than an arbitrary 70%.

A subtle peak-hold marker is allowed when it represents accepted evidence.

Do not show `FULL THROTTLE` without a verified throttle signal. `FULL POWER` / `NEAR OBSERVED MAX` requires a strong explicit evidence policy.

If a real throttle/demand field is later verified, preserve it separately from delivered power. A future premium gauge may show a thin **demand** marker plus **delivered power** fill, allowing Nembra to show requested output versus delivered output without guessing why they differ.

Only show a reverse/regen side if negative current/power or another authoritative regen signal is physically verified.

## Fluidity / perceived latency

Target smooth 60 Hz cockpit presentation where appropriate on iPhone 12. Localize high-frequency state; do not invalidate giant SwiftUI trees every telemetry/display frame.

New accepted telemetry should begin affecting presentation at the next practical render opportunity rather than waiting behind a coarse timer. Smoothness must not create noticeable lag behind the scooter.

Test deterministic step response, ramps, jitter, abrupt release, cadence changes, stale gaps, reconnect, maps + telemetry, and long rides. Avoid display overshoot that visually implies more speed/power than the latest accepted target.

Synthetic Simulator telemetry should include: idle → gentle launch → hard acceleration → sustained near-max output → release → coast; noisy low-cadence samples; cadence changes; stale gap/reconnect; low-battery reduced output; and mode-specific envelope scenarios. These fixtures are for runtime/design QA only, never physical protocol evidence.

## Battery and range

Battery is a signature Nembra system, not an old phone-style icon.

Keep distinct:
`RAW → VERIFIED → MEASURED SoC → ESTIMATED SoC → DISPLAY SoC → RETAINED → UNKNOWN`

Never present retained or estimated battery as fresh measured battery.

Primary battery/range interaction remains direct, e.g. `73% ↔ 8.4 mi`; battery fill always means charge.

Learn range from legitimate battery consumption plus trustworthy real ride distance. Never advertised manufacturer range × battery percent. Handle insufficient learning, stale evidence, gaps, low SoC, incomplete rides, outliers, confidence, reconnects, and scooter identity. Do not invent Wh/mi until electrical energy semantics are actually verified.

If voltage/current/power later become independently verified, Nembra may cross-check their relationship conservatively. Do not assume `watts = volts × amps` proves any field by itself; account for sign, timing, quantization, derivation, and asynchronous sampling. Integrate electrical energy only when cadence/units/continuity/provenance are strong enough.

## Automatic rides / history

No manual Start Ride workaround replacing the architecture. Ride lifecycle must survive disconnect/reconnect/suspension/process interruption/crash/relaunch/partial route capture/duplicate completion.

Require durable session identity, explicit gaps, idempotent completion, crash-safe recovery, immutable history, no stale-checkpoint resurrection, and no invented time/distance through missing observation.

History should be a premium vehicle logbook, not an evidence debugger. Keep ODO, GPS distance, integrated speed distance, recorded route geometry, provider route distance, observed duration, imported values, estimates, and unknowns distinct.

## Navigation

MapKit navigation should eventually feel native to the live cockpit rather than pasted on. Keep route planning, alternatives, selection, guidance, progress, reroute, arrival, and ride measurement separate. Provider route geometry/distance/ETA never becomes measured ride truth.

Require cancellation, generation identity, stale-callback rejection, explicit selection, quality-screened progress, backward-regression protection, sustained reroute evidence, sustained arrival evidence, and fail-closed ambiguity.

## ES80 / Tuya / Bluetooth — critical product path

**PUBLIC FIRST, SCOOTER SECOND, PHYSICAL EVIDENCE BEFORE CLAIMS.**

Use official/public AOVO/AOVOPRO information, Tuya docs, Apple CoreBluetooth docs, public reverse engineering, safe passive capture, and offline analysis. Preserve raw bytes, timing, GATT identity, transport provenance, continuity generations, subscription/read origin, and capture metadata.

Never:
- send random characteristic writes;
- treat `.write` capability as permission;
- treat CoreBluetooth write completion as scooter acknowledgement;
- treat subscription success as vehicle acknowledgement;
- invent services/characteristics/DP IDs/types/scales/signedness/cadence;
- promote stock-app display values directly into protocol truth;
- make the user manually decode hex when tooling can automate correlation.

Move the ES80 path upward whenever evidence allows:

`PUBLIC RESEARCH → PASSIVE COREBLUETOOTH CAPTURE → RELIABLE TARGET/SESSION IDENTITY → PHYSICAL CAPTURE UX → RAW GATT/VALUE EVIDENCE → STOCK-APP CORRELATION MARKERS → TRANSPORT/FRAMING CANDIDATES → REPEATABLE PHYSICAL CORRELATION → VERIFIED READ-ONLY FIELD DECODING → PRODUCTION READ-ONLY VEHICLE SERVICE → BATTERY/VOLTAGE/CURRENT/POWER INTEGRATION → DASHBOARD PROPULSION GAUGE → RANGE/ENERGY FEATURES WHEN LEGITIMATE → ONLY THEN EVIDENCE-GATED COMMAND RESEARCH`

When passive infrastructure is already mature, do not spend endless cycles polishing it if the next real blocker is physical capture or production read-only integration.

## Physical-blocker escalation

Exhaust reasonable software/public work first. When a specific remaining uncertainty genuinely requires the physical scooter, do not merely write `physical verification required` and wander into unrelated theory.

Produce **one precise minimal safe experiment** that Nembra tooling can consume: exact app/build/tool, exact scooter state, short duration, exact stock-app action/value marker, exact evidence expected, and no manual hex interpretation by the user.

## Commands / vehicle control

Desired lifecycle:
`REQUESTED → PENDING → OBSERVED / ACKNOWLEDGED EVIDENCE → CONFIRMED`

Do not claim success because the user tapped or because a Bluetooth write callback completed. Physical/motorized writes require strong protocol evidence, clear authorization boundaries, fail-closed behavior, and separation of transport completion from scooter-state confirmation.

## Acceleration / peaks

Propulsion/power display and acceleration measurement are different concepts. Acceleration uses trustworthy velocity change over time; never display-interpolated frames.

For 0→10 / 0→15 / 0→20 / top-speed measurements, reject weak cadence, rolling starts, source changes, gaps, poor GPS when relevant, interruptions, or ambiguous start/end state.

Peak means highest **accepted observed** measurement under the relevant quality policy, not unknowable perfect continuous-time maximum. Persist provenance/continuity and never convert render interpolation into peak evidence.

## Performance / tactility / accessibility

Profile launch, Home, continuous Dashboard rendering, power/speed motion, maps + telemetry, navigation + ride recording, long rides, history scrolling, persistence, CPU/main thread, memory/leaks, material/blur cost, and orientation transitions.

Touch acknowledgement should feel immediate. Confirmed motorized actions may use restrained success haptics only after accepted confirmation. Never buzz continuously with telemetry. Reduce Motion must remain excellent.

Support VoiceOver, Dynamic Type, Reduce Motion, Reduce Transparency, Increase Contrast, Differentiate Without Color, Voice Control, Switch Control, touch targets, and orientation changes. Warnings/gauge state must not rely on color alone. Recompose large-text layouts instead of shrinking/clipping the default design.

## Simulation

Simulator is essential development evidence and **never physical ES80 proof**. Synthetic current/watts/power may be used for cockpit QA only when explicitly simulator-only.

Cover disconnected, Bluetooth off, permission denied, reconnecting, retained/stale data, stopped, riding, low battery, modes, command pending/confirmed/unavailable, routes, gaps, recovery, history, learned/unavailable range, navigation/reroute/arrival, orientation, and accessibility states.

## Truth constitution

Never fabricate speed, battery %, voltage, current, watts/power, energy, Wh/mi, temperature, torque, throttle, regen, distance, odometer, GPS accuracy, route geometry, ETA provenance, protocol semantics, command acknowledgement, battery health, charging state, physical maximums, or legality/safety.

Keep distinct:
`MEASURED / ESTIMATED / DISPLAYED / INTERPOLATED / DERIVED / RETAINED / UNKNOWN / SIMULATOR / PUBLIC / PHYSICAL`

Simulator != physical.
Public evidence != physical verification.
Display interpolation != measurement.
Observed peak != perfect physical maximum.
Learned gauge ceiling != rated motor/controller maximum.
High measured power != verified throttle position.
Disconnect != measured zero.

## Testing / acceptance

Use risk-proportional judgment.

- Isolated package/domain: focused compile/tests, adversarial tests where useful, source review; no mandatory full Simulator gate for every tiny edit.
- App-visible: focused tests, Xcode build/test, Simulator interaction, screenshots/visual critique, accessibility verification, and performance checks when rendering/high-frequency behavior changes.
- Persistence/security/global build wiring/physical command boundaries: stronger adversarial testing, corruption/recovery/error paths, and exact-head acceptance.

Do not call queued=green, skipped=green, resolver-only=accepted, or old-SHA green=new-SHA green. Do not rerun expensive full-app acceptance merely because unrelated docs moved.

## Anti-patterns

Do not confuse sophistication with progress. If two designs are equally truthful and robust, prefer the simpler architecture that moves Nembra closer to an excellent working product.

Avoid endless foundation polishing while downstream integration is missing, abstraction-for-every-edge-case, micro-PR factories, debug UI in the final product, generic component libraries replacing deliberate screen design, premature physical command work, fake precision, animation that changes truth semantics, visual novelty that hurts glanceability, or speed achieved by lowering quality.

## Success metric

Optimize for complete capabilities, extraordinary perceived quality, truthful vehicle behavior, premium fluid motion, robust architecture, accessibility, real runtime evidence, fewer defects, less duplication, and meaningful progress toward verified ES80 integration.

Do not optimize for PR count, comments, process documents, agents appearing busy, shallow throughput, or arbitrary speed at the expense of quality.

## Startup

Inspect live GitHub and current main. Determine what is occupied, mature, weak, and what unlocks the most real Nembra product value. Choose the highest-value safe non-conflicting work. If you start a capability, follow it upward toward production quality instead of stopping at the first clean primitive.

**Preserve truth. Preserve quality. Look at the actual app. Make it feel exceptional. Keep going.**