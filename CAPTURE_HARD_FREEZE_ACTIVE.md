# CAPTURE HARD FREEZE — FASTEST PATH TO FIRST ES80 ARTIFACT

This file is the active execution lock for the one-time Nembra Capture utility.

## Frozen candidate
- PR: #833
- exact product head: `1810663e0a0793a2ee34b8186fc2471dfe65e24c`
- exact-head portable/source Capture guards: **7 / 7 SUCCESS**
- current PR-local Xcode run: `31291911371`
- resolver job: `93190441213` — **SUCCESS**, resolved the immutable PR head
- field-authority tooling job: `93190446883` — **SUCCESS**
- Mac job: `93190446876` — **QUEUED / NON-EVIDENCE** at this checkpoint
- ancestor `91fd9438d588d532618dd270777f64bdc74ad40a` PR-local Mac run `31291413734` — **CANCELLED / NON-EVIDENCE** after the legitimate head move
- ancestor trusted run `31291409838` resolved `91fd9438...` only and cannot accept the current head

The exact Capture product head is frozen while current exact-head runtime acceptance is alive. The deployed trusted default-branch workflow content was last changed at `a1433d683fcf1e15f34c38bedac6a8f591723aff` to use authenticated `github.actor == github.repository_owner` after a demonstrated App-mediated owner-command false-negative. Later `main` movement has been coordination/documentation only unless live GitHub shows otherwise; always inspect the current workflow before a fresh trusted command.

## Why `1810663e...` replaced `91fd9438...`

`91fd9438...` fixed one demonstrated TODAY acceptance false-path: explicit `--es80-passive-capture-simulator-qa` now beats the embedded `ES80-FINGERPRINT-v1` field recipe only under `DEBUG && targetEnvironment(simulator)`.

Fresh exact-source review then found the adjacent ordinary-Simulator path was still wrong. The same recipe-bound Debug app is used by Home/Dashboard UI tests and the retained 11-state Simulator screenshot matrix. Those launches use `NEMBRA_SIMULATION_SCENARIO`, not the Capture-QA argument. On `91fd...`, the embedded field recipe could still route those ordinary Simulator launches into private/physical Capture.

The direct fast-forward repair from `91fd9438... -> 1810663e...` changes only:
- `NembraApp/App/NembraApp.swift` — under Debug Simulator, explicit Capture QA wins first, then a valid `AppBootstrap.simulationScenario(...)` returns `.standard`, then the embedded field recipe is evaluated; Release/physical builds compile both Simulator overrides out;
- `scripts/ci/tests/test_xcode27_simulator_capture_recipe_provenance.py` — binds the ordinary `SIMCTL_CHILD_NEMBRA_SIMULATION_SCENARIO` harness to that precedence.

No BLE/controller/recorder/ResearchAdmission/signed-field producer/command behavior changed. All seven portable/source Capture gates on exact `1810663e...` are terminal green, including the executed Simulator recipe/route regression.

## Prime rule

**DO NOT MOVE #833 WHILE CURRENT EXACT-HEAD XCODE RUN `31291911371` / MAC JOB `93190446876` IS QUEUED OR IN PROGRESS, unless a newly demonstrated TODAY blocker requires a bounded repair.**

Do not mutate the Capture flagship for speculative hardening, cosmetics, documentation, duplicate validation, test cleanup, branch hygiene, post-capture security work, or a theoretically stronger implementation while this exact run is alive.

Move the frozen candidate only for a newly demonstrated normal-path TODAY blocker under `CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md`: build/install/launch failure; Capture crash/hang/corruption/mis-target/export failure; application characteristic-write authority; Stationary/Charger Disconnected bypass; an exact-head acceptance false-green/failure; real Accessibility XXXL runtime failure; signed intended-device installation failure; missing package-owned `PRIVATE RESEARCH BUILD / Runtime provenance ready` on the exact retained IPA; or inability to deliberately authorize the exact safe Research Field Build.

Do not issue another `/xcode27` or `/capture-xcode27` merely because the Mac job is queued. After PR-local runtime acceptance, issue exactly one trusted default-branch `/capture-xcode27` for the unchanged current head only if no current-head trusted run already exists.

## What happens when the exact-head run finishes

### If terminal SUCCESS
Do not reopen software polishing. Continue immediately on this same exact accepted source:
1. inspect retained logs, xcresult, screenshots, and build/provenance evidence rather than treating workflow green alone as acceptance;
2. confirm ordinary Home/Dashboard Simulator routing, true Accessibility XXXL geometry, landscape, Stationary/Charger Disconnected preflight, representative correlation/acquisition/recovery states, Horizon/seal, Capture Complete, Share/Retry, and explicit SIMULATOR/QA labeling;
3. earn the trusted default-branch exact-head command gate on the same unchanged SHA;
4. produce one exact signed `ES80-FINGERPRINT-v1` private Research Field Build via `scripts/ci/xcode27_today_research_field_candidate.sh` on the private signing surface;
5. independently inspect retained IPA signing/provisioning/intended-device membership and exact source/build/build-instance/recipe/executable/Info.plist/evidence-record/IPA hashes;
6. install exactly that retained IPA without rebuilding or re-exporting using `docs/ES80_TODAY_EXACT_RETAINED_IPA_INSTALL.md`;
7. launch from the Home Screen and require package-owned `PRIVATE RESEARCH BUILD / Runtime provenance ready`; visible recipe/build/source/build-instance must rendezvous exactly with retained inspection evidence before any scan;
8. complete the external TODAY Final GO record from independently checked retained evidence;
9. only then run the one-time stationary, charger-disconnected, passive/read-only ES80 capture, observe at least 60 seconds after accepted Ready, seal Horizon, and preserve the exact raw Share artifact unchanged.

### If terminal FAILURE
Only the demonstrated failing step becomes Capture work. Assign the minimum crew needed to repair that exact failure, compose one bounded fix, freeze the new exact SHA, and run one new exact-head acceptance. All unrelated findings remain deferred.

### If cancelled or skipped
First determine why. A stale-head janitor cancellation after a legitimate #833 move is expected non-evidence. A cancelled/skipped run on an unchanged exact current head is not green and must be diagnosed before another command is issued. Do not create duplicate Mac work merely because a run is queued.

## Everyone else
All workers not required for the exact Capture reaction crew should work on the actual Nembra product under `ADAPTIVE_SWARM_PRIORITY.md`.

Current overflow priority:
1. Dashboard / Cockpit
2. Battery + Range
3. Rides + Records
4. Navigation
5. Home
6. Vehicle / Controls

Do not open duplicate exact-head validation PRs. Do not create new Capture work simply because Capture is P0 while the final exact gate is legitimately waiting on the scarce Mac runner.

## Capture product scope
Capture is the measuring instrument that unlocks first physical ES80 truth. It must be safe, truthful, app-visible, understandable, accessible, and capable of producing one trustworthy immutable Bluetooth artifact. It must not become a second generic debug console or a reason to defer the real Nembra riding product.

## Physical boundary
This hard freeze does not itself authorize hardware. Physical Experiment One remains **NO-GO / DO NOT RUN** until terminal exact-head trusted acceptance, retained artifact/screenshot inspection, exact signed retained IPA inspection, intended-device installation/runtime rendezvous, fresh Stationary + Charger Disconnected preflight, and the external Final GO record are all complete.
