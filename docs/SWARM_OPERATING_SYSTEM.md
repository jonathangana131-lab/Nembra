# NEMBRA SWARM OPERATING SYSTEM
CURRENT_PROTOCOL_VERSION: 12
STATUS: ACTIVE
CODENAME: PRODUCT-FIRST AUTONOMOUS SOL

Repository: `jonathangana131-lab/Nembra`

V12 deliberately removes most V11 swarm bureaucracy. The goal is to let strong GPT-5.6 SOL workers spend their context and runtime building Nembra instead of managing a complex organization.

## Prime directive

**BUILD NEMBRA.**

Workers should spend the overwhelming majority of useful effort on product code, tests, runtime validation, visual polish, performance, accessibility, necessary protocol/Bluetooth research, and safe integration.

Do not spend large amounts of time creating control-plane prose, migration chatter, feature-cell ceremony, release-train bureaucracy, role systems, epochs, or status artifacts.

## Simple collaboration

1. Inspect current `main` and active PRs before choosing work.
2. Avoid editing files another active worker is already changing unless collaboration is clearly intentional.
3. Own one meaningful feature/subfeature until it is genuinely strong.
4. Large features may naturally split across workers by non-overlapping subdomains.
5. Prefer a few coherent PRs over many tiny PRs.
6. Do not create process artifacts unless they directly help ship product work.
7. If GitHub content writes are throttled, keep coding/reviewing/testing and batch the next useful write instead of retry-spamming.
8. After finishing a feature, inspect current `main` and choose the next important safe task.

No Feature Cell registration, epoch bookkeeping, release-train ceremony, mandatory captains, migration comments, or worker-state blocks are required under V12.

Historical V7–V11 issues/PRs remain evidence only. Existing workers migrate in place: keep current branch/source/tests, stop adding V11 ceremony, and continue actual product work.

## Long-run behavior

Keep working as long as the outer platform permits and useful work exists. Commit/test/PR/review/merge/subtask completion is not a reason to voluntarily stop. A checkpoint is not an endpoint.

Avoid monolithic reasoning stalls. Turn uncertainty into targeted source reads, tests, logs, official docs, or runtime evidence. Do not endlessly poll or repeat the same failed tactic; change approach after two attempts without new evidence. Keep commentary short to preserve context for engineering.

## Product target

Primary physical target: current/newer Tuya-generation **AOVOPRO ES80**.

Nembra must become premium native iOS 27 vehicle software for an iPhone 12 baseline: fast, original, trustworthy, tactile, glanceable, polished, native, and accessible.

Reject generic Tuya-dashboard feel, cheap cross-platform styling, card soup, gamer RGB, giant empty black areas, debug-first UI, developer jargon, fake precision, invented hardware behavior, or technically-correct-but-mediocre final screens.

### Home
Quickly communicate scooter identity, connection, battery, range, ride mode, known lock/vehicle state, issue/recovery action, trip context, and recent ride. Premium, compact, clear, non-duplicative.

### Live Ride / Dashboard
Landscape cockpit quality. Huge truthful speed, battery/range, mode, trip distance, ride duration, connection/identity, navigation when active, and useful safe controls. Measurement and presentation interpolation stay separate.

### Battery
Keep raw evidence, verified evidence, measured SoC, estimated SoC, display SoC, retained/last-known SoC, and unavailable/unknown distinct. Never present retained or estimated data as fresh measurement. Battery visuals should be signature-quality and truthful.

### Battery % ↔ Range
Primary interaction like `73% ↔ 8.4 mi`. Battery fill still means charge. Range learns from legitimate battery consumption + trustworthy real distance. Never manufacturer advertised range × battery percentage. Handle cold start, stale evidence, gaps, incomplete rides, outliers, confidence, low SoC, reconnects, and scooter identity. No fake Wh/mi without verified electrical semantics.

### Automatic rides
No manual Start Ride workaround replacing the architecture. Survive disconnect/reconnect/process interruption/crash/relaunch/partial route capture/duplicate completion. Require durable session identity, crash-safe recovery, idempotent completion, explicit gaps, no invented continuity, immutable history, and no resurrection of completed rides.

### History / statistics
Premium logbook, deterministic stats from valid evidence. Keep ODO, GPS distance, recorded route geometry, provider route distance, and imported/estimated values separate.

### Location / routes
Quality-screen accepted GPS evidence. Route gaps remain gaps. Never fabricate continuity. Background location only when legitimately justified.

### Navigation
Use MapKit appropriately. Separate route planning, alternatives, selection, ride evidence, navigation progress, reroute, and provider ETA/distance. Provider route distance never becomes measured ride distance. Need cancellation, stale-callback protection, route generation identity, explicit selection, deterministic tests, quality-screened progress, sustained reroute evidence, and fail-closed ambiguity. Navigation + live ride should eventually be one excellent Dashboard experience.

### ES80 / Bluetooth
**PUBLIC FIRST, SCOOTER SECOND.** Use official/public AOVO/AOVOPRO, Tuya, Apple CoreBluetooth docs, public reverse engineering, safe passive capture, and offline analysis. Preserve raw evidence/provenance. No random writes, no `.write` capability interpreted as permission, no subscription success called a command acknowledgement, no invented DP meanings/scaling/cadence/units.

### Commands
Desired lifecycle: requested → pending → observed/acknowledged evidence → confirmed. Do not claim success merely because the user tapped. Motorized/safety-relevant writes require strong evidence and authorization boundaries.

### Acceleration / peak speed
Only report when observation quality is sufficient. Reject rolling starts, weak cadence, source switches, transport gaps, interruptions, or weak GPS when relevant. Peak means highest accepted observed sample, not perfect continuous physical maximum.

### Simulation
Simulator is development evidence, not physical scooter proof. Cover disconnected, Bluetooth off, permission denied, reconnecting, stopped, riding, low battery, retained battery, mode changes, commands, route recording, gaps, recovery, history, learned/unavailable range, navigation/reroute, orientation, and accessibility.

### Visual program
For UI work: `SIMULATOR → SCREENSHOT → CRITIQUE → REDESIGN → IMPLEMENT → INTERACT → SCREENSHOT → COMPARE → PROFILE → ACCESSIBILITY → FIX → REPEAT`.

### Performance
iPhone 12 baseline. Localize high-frequency updates. Measure launch, Home, Dashboard, rolling numbers, maps+telemetry, navigation+telemetry, long rides, history, persistence, CPU/main thread, memory/leaks.

### Accessibility
Support VoiceOver, Dynamic Type, Reduce Motion, Reduce Transparency, Increase Contrast, Differentiate Without Color, Voice Control, Switch Control, touch targets, and orientation changes.

### Privacy
Core control/history offline-capable where practical. Precise route/start/end/GPS data private by default.

## Truth constitution

Never fabricate speed, battery %, voltage, current, watts/power, energy, Wh/mi, temperature, torque, throttle, regen, distance, odometer, GPS accuracy, route geometry, protocol semantics, command acknowledgement, battery health, charging state, or route legality/safety.

Keep distinct: `MEASURED / ESTIMATED / DISPLAYED / DERIVED / RETAINED / UNKNOWN / SIMULATOR / PUBLIC / PHYSICAL`.

Simulator != physical. Public evidence != physical verification. Disconnect != measured zero.

## Testing / acceptance

Use judgment proportional to risk.

- Isolated package/domain changes: focused compile/tests, adversarial tests when useful, source review. No mandatory full Simulator gate for every tiny edit.
- App-visible changes: focused tests, Xcode build/test, Simulator interaction, screenshots when visual behavior changes.
- Persistence/security/global build wiring/motorized boundaries: stronger adversarial testing and exact-head acceptance.

Do not rerun expensive full-app acceptance merely because unrelated docs changed. Never call queued/skipped/resolver-only work accepted, and never treat a green old SHA as proof for a changed SHA.

## GitHub throttle

On secondary content-creation throttling: stop retry-spamming, continue useful work, batch pending writes, retry naturally later, and do not mistake temporary throttle for permanent permission loss.

## Success metric

Optimize for finished app capability, correctness, product quality, performance, accessibility, fewer defects, less duplication, and visible Nembra progress — not PR count, comments, control artifacts, or agents appearing busy.

## Startup

Inspect live GitHub. Understand what is occupied and genuinely unfinished. Choose the highest-value safe work and engineer it. Do not wait for the user to say continue. Do not spend the turn designing another swarm system.

**Build Nembra.**
