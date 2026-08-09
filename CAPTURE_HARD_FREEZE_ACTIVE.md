# CAPTURE HARD FREEZE — FASTEST PATH TO FIRST ES80 ARTIFACT

This file is the active execution lock for the one-time Nembra Capture utility.

## Frozen candidate
- PR: #833
- exact product head: `91fd9438d588d532618dd270777f64bdc74ad40a`
- trusted exact-head Xcode run: `31291409838`
- trusted resolver job: `93189117656` — **SUCCESS**, resolved PR #833 to exact `91fd9438d588d532618dd270777f64bdc74ad40a`
- trusted Mac job: `93189125612` — **QUEUED** at this checkpoint
- exact-head portable/source guards on `91fd9438...`: **7 / 7 SUCCESS**
- supporting PR-local Xcode run: `31291413734` — resolver + field-authority tooling green; Mac job queued; supporting only, not final authority

The exact Capture product head is frozen while the trusted Mac job is alive. The trusted run was instantiated under default-branch trust root `d423790f6a2e17c69e856e86ae06ee41556e6a72`, where the exact owner-comment predicate actually admitted this command and the resolver bound the live same-repo PR head correctly. Current `main` later advanced the trusted workflow to `a1433d683fcf1e15f34c38bedac6a8f591723aff` only to repair an App-mediated owner-command **false-negative** by using authenticated `github.actor`; that does not reveal a false-positive in the already-admitted `d423...` run or invalidate its exact-head binding.

## Why `91fd9438...` replaced the prior frozen head

The previous `67263e6a5d5aed9e08f3b9d331d3b7afc83a79b9` candidate exposed one demonstrated TODAY acceptance false-path: the embedded `ES80-FINGERPRINT-v1` field recipe could route a Debug Simulator build into the field-Capture path before an explicit synthetic Simulator-QA launch request was evaluated. That stole the retained visual state matrix rather than testing its requested synthetic states.

The bounded repair from `67263e6a... -> 91fd9438...` is exactly two files:
- `NembraApp/App/NembraApp.swift`
- `scripts/ci/tests/test_xcode27_simulator_capture_recipe_provenance.py`

Explicit synthetic QA now wins only under `DEBUG && targetEnvironment(simulator)`. Release/physical builds compile that override out and remain recipe-bound to the field Capture route. No BLE/controller/recorder/command behavior changed. The queue janitor correctly cancelled stale acceptance work for the old head after this movement; those cancellations are non-evidence, not product failures.

## Prime rule

**DO NOT MOVE #833 WHILE TRUSTED RUN `31291409838` / MAC JOB `93189125612` IS QUEUED OR IN PROGRESS.**

Do not mutate the Capture flagship for speculative hardening, cosmetics, documentation, duplicate validation, test cleanup, branch hygiene, post-capture security work, or a theoretically stronger implementation while this exact run is alive.

Move the frozen candidate only for a newly demonstrated normal-path TODAY blocker under `CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md`: build/install/launch failure; Capture crash/hang/corruption/mis-target/export failure; application characteristic-write authority; Stationary/Charger Disconnected bypass; an exact-head acceptance false-green/failure; real Accessibility XXXL runtime failure; signed intended-device installation failure; missing package-owned `PRIVATE RESEARCH BUILD / Runtime provenance ready` on the exact retained IPA; or inability to deliberately authorize the exact safe Research Field Build.

## What happens when the trusted run finishes

### If terminal SUCCESS
Do not reopen software polishing. Continue immediately on this same exact accepted source:
1. inspect retained trusted logs, xcresult, screenshots, and build/provenance evidence rather than treating workflow green alone as acceptance;
2. confirm true Accessibility XXXL geometry, landscape, Stationary/Charger Disconnected preflight, representative correlation/acquisition/recovery states, Horizon/seal, Capture Complete, Share/Retry, and explicit SIMULATOR/QA labeling;
3. produce one exact signed `ES80-FINGERPRINT-v1` private Research Field Build via `scripts/ci/xcode27_today_research_field_candidate.sh` on the private signing surface;
4. independently inspect retained IPA signing/provisioning/intended-device membership and exact source/build/build-instance/recipe/executable/Info.plist/evidence-record/IPA hashes;
5. install exactly that retained IPA without rebuilding or re-exporting using `docs/ES80_TODAY_EXACT_RETAINED_IPA_INSTALL.md`;
6. launch from the Home Screen and require package-owned `PRIVATE RESEARCH BUILD / Runtime provenance ready`; visible recipe/build/source/build-instance must rendezvous exactly with retained inspection evidence before any scan;
7. complete the external TODAY Final GO record from independently checked retained evidence;
8. only then run the one-time stationary, charger-disconnected, passive/read-only ES80 capture, observe at least 60 seconds after accepted Ready, seal Horizon, and preserve the exact raw Share artifact unchanged.

### If terminal FAILURE
Only the demonstrated failing step becomes Capture work. Assign the minimum crew needed to repair that exact failure, compose one bounded fix, freeze the new exact SHA, and run one new exact-head trusted acceptance. All unrelated findings remain deferred.

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
