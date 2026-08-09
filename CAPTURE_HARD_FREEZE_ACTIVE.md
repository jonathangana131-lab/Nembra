# CAPTURE HARD FREEZE — FASTEST PATH TO FIRST ES80 ARTIFACT

This file is the active execution lock for the one-time Nembra Capture utility.

## Frozen candidate
- PR: #833
- exact product head: `8efdc2946f784c2bf2130d4c3447baeb15e895a6`
- exact-head portable/source Capture guards: **7 / 7 SUCCESS**
- current PR-local Xcode run: `31292505064`
- resolver job: `93191988901` — **SUCCESS**
- field-authority tooling job: `93191996586` — **SUCCESS**
- Mac job: `93191996583` — **QUEUED / NON-EVIDENCE** at this checkpoint
- `Capture Simulator Visual Custody Source QA` run `31292505047` / job `93191988843` — **SUCCESS**, including the repaired composed routing source contract
- `21f859aa4c3feaaeed32437bd94be6e7bebcadff` was an intentionally red/misaligned regression checkpoint and is not acceptance
- every Xcode result before exact `8efdc294...` is ancestor evidence only

The exact Capture product head is frozen while current exact-head runtime acceptance is alive. The deployed trusted default-branch workflow content was last changed at `a1433d683fcf1e15f34c38bedac6a8f591723aff`; later `main` movement has been coordination/documentation only unless live GitHub shows otherwise. Always inspect the current workflow before a fresh trusted command.

## Why `8efdc294...` replaced `9c7a2048...`

The product behavior at `9c7a2048...` was already the intended two-layer fail-closed design:
- `NembraApp.resolveLaunchMode(...)` keeps explicit Capture QA first and routes `.selected` plus `.invalid` ordinary Debug-Simulator requests to `.standard` before the embedded `ES80-FINGERPRINT-v1` recipe;
- `AppBootstrap.simulationScenario(...)` maps `.invalid` to the existing `.unsupportedConfiguration` fixture in Debug Simulator, while Release/physical returns `nil`.

A later test-only checkpoint `21f859aa...` accidentally demanded the older removed optional-helper line in `NembraApp.swift`, making the portable gate red despite the stronger composed production path. Exact `8efdc294...` repairs only that regression contract: it verifies the direct launch-mode switch and the bootstrap invalid->unsupported fallback independently. No product/BLE/controller/recorder/ResearchAdmission/signed-field producer/command behavior changed.

All seven portable/source Capture gates on exact `8efdc294...` are terminal green.

## Prime rule

**DO NOT MOVE #833 WHILE CURRENT EXACT-HEAD XCODE RUN `31292505064` / MAC JOB `93191996583` IS QUEUED OR IN PROGRESS, unless a newly demonstrated TODAY blocker requires a bounded repair.**

Do not mutate the Capture flagship for speculative hardening, cosmetics, documentation, duplicate validation, test cleanup, branch hygiene, post-capture security work, or a theoretically stronger implementation while this exact run is alive.

Move the frozen candidate only for a newly demonstrated normal-path TODAY blocker under `CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md`: build/install/launch failure; Capture crash/hang/corruption/mis-target/export failure; application characteristic-write authority; Stationary/Charger Disconnected bypass; an exact-head acceptance false-green/failure; real Accessibility XXXL runtime failure; signed intended-device installation failure; missing package-owned `PRIVATE RESEARCH BUILD / Runtime provenance ready` on the exact retained IPA; or inability to deliberately authorize the exact safe Research Field Build.

Do not issue another `/xcode27` or `/capture-xcode27` merely because the Mac job is queued. After PR-local runtime acceptance, issue exactly one trusted default-branch `/capture-xcode27` for the unchanged current head only if no current-head trusted run already exists.

## What happens when the exact-head run finishes

### If terminal SUCCESS
Do not reopen software polishing. Continue immediately on this same exact accepted source:
1. inspect retained logs, xcresult, screenshots, and build/provenance evidence rather than treating workflow green alone as acceptance;
2. confirm ordinary Home/Dashboard Simulator routing, invalid Simulator unsupported-state routing, true Accessibility XXXL geometry, landscape, Stationary/Charger Disconnected preflight, representative correlation/acquisition/recovery states, Horizon/seal, Capture Complete, Share/Retry, and explicit SIMULATOR/QA labeling;
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

## Physical boundary
This hard freeze does not itself authorize hardware. Physical Experiment One remains **NO-GO / DO NOT RUN** until terminal exact-head trusted acceptance, retained artifact/screenshot inspection, exact signed retained IPA inspection, intended-device installation/runtime rendezvous, fresh Stationary + Charger Disconnected preflight, and the external Final GO record are all complete.
