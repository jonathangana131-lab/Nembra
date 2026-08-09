# CAPTURE HARD FREEZE — FASTEST PATH TO FIRST ES80 ARTIFACT

This file is the active execution lock for the one-time Nembra Capture utility.

## Frozen candidate
- PR: #833
- exact product head: `9c7a204862aeb35b7d70df4f5b7799395ea8acc5`
- exact-head portable/source Capture guards: **7 / 7 SUCCESS**
- current PR-local Xcode run: `31292341850`
- resolver job: `93191550740` — **SUCCESS**
- field-authority tooling job: `93191561328` — **SUCCESS**
- Mac job: `93191561344` — **QUEUED / NON-EVIDENCE** at this checkpoint
- `Capture Simulator Visual Custody Source QA` run `31292341832` — **SUCCESS**, including the exact routing source contract
- every Xcode result on `856011c543fc73e8f554dc23eecf180c3f11272a` or earlier is ancestor evidence only

The exact Capture product head is frozen while current exact-head runtime acceptance is alive. The deployed trusted default-branch workflow content was last changed at `a1433d683fcf1e15f34c38bedac6a8f591723aff` to use authenticated `github.actor == github.repository_owner` after a demonstrated App-mediated owner-command false-negative. Later `main` movement has been coordination/documentation only unless live GitHub shows otherwise; always inspect the current workflow before a fresh trusted command.

## Why `9c7a2048...` replaced `856011c...`

`856011c...` correctly made explicit Capture QA win first and routed both valid and invalid ordinary Simulator requests to `.standard` before the embedded `ES80-FINGERPRINT-v1` recipe. The standard bootstrap path still intentionally collapsed `.invalid` to `nil`, however, so an invalid explicit Simulator QA request produced the generic unverified standard runtime rather than the existing truthful unsupported-configuration fixture.

Exact `9c7a2048...` adds one Debug-Simulator-only fail-closed completion in `NembraApp/App/AppBootstrap.swift`: `.invalid` resolves to `.unsupportedConfiguration`; `.disabled` remains `nil`; Release/physical builds still return `nil` for `.invalid`. The result is an explicit inert unsupported state for malformed QA requests without widening any physical field route.

No BLE/controller/recorder/ResearchAdmission/signed-field producer/command behavior changed. All seven portable/source Capture gates on exact `9c7a2048...` are terminal green.

## Prime rule

**DO NOT MOVE #833 WHILE CURRENT EXACT-HEAD XCODE RUN `31292341850` / MAC JOB `93191561344` IS QUEUED OR IN PROGRESS, unless a newly demonstrated TODAY blocker requires a bounded repair.**

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
