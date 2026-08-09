# NEMBRA V14 ADAPTIVE SWARM PRIORITY CONTROL

This is the durable anti-idle control plane for Nembra. It exists so a large swarm keeps the whole product moving at full useful throughput even when a scarce external gate such as Xcode/macOS signing is queued, pending, rate-limited, unavailable, or owned by another worker.

Live GitHub state outranks stale prose, but this scheduling policy is mandatory whenever it can be followed safely.

## Prime directive

**No useful worker waits behind a scarce gate when another safe, high-value Nembra lane exists.**

A queued/running Xcode job, signing job, review, merge, device install, physical experiment, or another worker's branch is not a reason for the rest of the swarm to poll, idle, or open duplicate validation PRs.

The swarm optimizes **total time-to-closed-product**, not time spent staring at the current P0 blocker.

## Scarce-gate reservation rule

When a scarce gate is pending, reserve only the minimum crew needed to react to it.

Default reservation:
- **1 Integration/Closure owner** protects the exact candidate, watches the gate once at meaningful state changes, and owns composition.
- **0-1 Diagnostic/QA worker** may prepare a bounded response if there is already concrete evidence of a likely failure.
- **0-1 Field/signing owner** may prepare the next exact signing/install step if that work is actually actionable without mutating the frozen candidate.

Unless live evidence proves otherwise, **2-3 workers maximum** should remain attached to one pending external gate.

Everyone else immediately leaves that wait-state and takes a different safe Nembra lane.

Do not create twenty mirrors, twenty `/xcode27` requests, twenty reviews of the same workflow, or twenty speculative fixes around a job that has not produced new evidence.

## One-check wait budget

A worker may check a pending gate once when it first discovers the wait state. After the state is known:

1. record/confirm the exact pending run or blocker on GitHub if needed;
2. do not repeatedly poll it;
3. self-reassign immediately;
4. return only when GitHub shows a meaningful state transition or a durable handoff explicitly requests help.

`queued`, `pending`, `in_progress`, `waiting for runner`, `awaiting review`, and `awaiting physical access` are all **REASSIGN states**, not work states.

## Adaptive priority score

Workers should choose the highest-value safe lane using this order of thought:

1. **Can this lane unblock a real user-visible capability or critical dependency now?**
2. **Can it be completed independently without colliding with an active owner?**
3. **Does it advance a closure rung rather than merely create another PR?**
4. **Does it have immediate local/tooling evidence available, or is it externally waiting?**
5. **Will it move the actual app, truth model, visual quality, runtime, accessibility, or performance?**

External-waiting lanes receive a heavy priority penalty. Independent product lanes receive a strong priority bonus.

## Current product overflow order while Capture is externally blocked

Until the first real stationary passive ES80 artifact exists, Capture remains P0, but **P0 does not monopolize the swarm when its next step is externally waiting**.

When the Capture closure crew is saturated or waiting on Xcode/signing/device/physical access, overflow workers fan out in this order unless live ownership or dependency truth says otherwise:

### P1 — Dashboard / Cockpit masterpiece
Advance the actual rider-facing cockpit toward closure:
- truthful speed authority and stale/unavailable behavior;
- bottom Energy Rail/Horizon integration;
- 60 Hz display implementation/performance where already truth-safe;
- portrait + independently designed landscape;
- motion/haptics only when semantically safe;
- accessibility, outdoor readability, screenshot critique, frame pacing;
- remove generic/Tuya/OEM card behavior.

### P2 — Battery + Range vertical slice
Advance one integrated battery object rather than disconnected widgets:
- `% -> estimated range -> %` interaction;
- learned-range truth/state model;
- unavailable/learning states;
- persistence and history joins;
- real app wiring;
- premium visuals, accessibility, performance and screenshots;
- never invent physical ES80 electrical semantics before evidence.

### P3 — Rides + Records closure
Close remaining product gaps in Rides/Ride Details/Records:
- persistence joins;
- duration/distance/source truth;
- empty/partial/missing states;
- visual and runtime closure;
- screenshots/accessibility/performance.

### P4 — Navigation closure
Advance non-conflicting planning/guidance/reroute/arrival/runtime/UI lanes while respecting active MapKit/shared-state ownership.

### P5 — Home redesign
Advance Home toward a deliberate Nembra landing surface, not generic cards. Preserve real data/state truth and avoid colliding with an active root-composition owner.

### P6 — Vehicle / Controls
Advance capability-aware vehicle state, truthfully unavailable controls, settings architecture, and product UI without inventing unverified scooter commands.

Workers may skip down the list when a higher lane is already saturated, path-conflicted, dependency-blocked, or cannot make real progress without physical evidence.

## Example allocation for ~20 concurrent chats

This is an example, not a quota. Adapt to live safe lanes.

If Capture is frozen and its exact Xcode Mac job is pending:
- 2 workers: Capture closure / exact-head gate / signing handoff;
- 5-6 workers: Dashboard/Cockpit independent lanes;
- 4-5 workers: Battery/Range independent lanes;
- 2-3 workers: Rides/Records;
- 2 workers: Navigation;
- 1-2 workers: Home / Vehicle-Controls depending on contention;
- 1-2 workers: cross-feature visual QA, accessibility, performance, integration cleanup.

If Xcode returns a failure, only enough workers to own the demonstrated failure move back to Capture. The rest continue their product lanes.

If Xcode returns terminal success, the closure/signing crew moves Capture to signed IPA/install/Final GO. The rest continue product development unless a newly actionable P0 task genuinely requires more parallel capacity.

## Freeze means freeze

When Capture has a TODAY freeze candidate, overflow workers must **not** mutate that candidate for optional hardening or speculative QA merely because they are available.

A frozen candidate exists specifically to let the rest of Nembra keep moving while scarce acceptance runs execute.

New Capture source movement before the first artifact requires a demonstrated TODAY blocker under `CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md`.

## Cross-feature branch isolation

Parallel product development must not destabilize the frozen Capture candidate.

Workers should:
- branch from the correct live base for their feature;
- avoid high-contention root/project files when another owner has them;
- keep feature work mergeable independently;
- hand off exact accepted blobs/tests/findings to an Integration Closer when central composition is required;
- never force unrelated Dashboard/Battery/Home work into the frozen Capture closure branch.

## Adaptive return-to-critical-path rule

A worker returns to a higher-priority blocker only when one of these becomes true:
- new terminal CI/Xcode evidence exists;
- a concrete failing log identifies an actionable defect;
- signing/install/device work becomes immediately executable;
- a physical result arrives;
- an Integration Closer explicitly requests a bounded handoff;
- the worker's current lower-priority lane reaches a safe checkpoint and the higher lane now has unowned actionable work.

Do not stampede back merely because the blocker is important.

## Continuous-execution loop

Every worker runs this loop until the session/tooling ends or no safe useful work exists:

**REFRESH -> SCORE -> CLAIM -> IMPLEMENT -> TEST/INTERACT/CRITIQUE -> PERSIST TO GITHUB -> REFRESH -> REASSIGN**

A PR, commit, merge, green unit test, review, screenshot, queued Xcode run, or completed subtask is never by itself a stop condition.

## What counts as bad swarm behavior

These are explicit V14 failures:
- many workers polling the same queued Xcode run;
- opening duplicate validation mirrors with no new evidence;
- doing speculative P0 hardening while the frozen candidate waits;
- ending a session because the original lane is blocked while another safe product lane exists;
- leaving Dashboard/Battery/Home/Vehicle work idle because Capture is P0;
- confusing worker count with useful parallel throughput;
- creating PR volume without moving closure rungs;
- material findings that exist only in chat.

## What counts as healthy swarm behavior

A healthy large swarm has:
- a tiny crew guarding the true critical path;
- multiple independent product lanes moving continuously;
- little duplicate work;
- few workers attached to external waits;
- clear integration ownership;
- exact-head evidence on critical gates;
- real app screenshots/runtime proof for app-visible work;
- durable GitHub handoffs;
- immediate reallocation whenever a dependency changes.

## GO meaning under adaptive priority

`GO` means work, not watch.

After fresh GitHub inspection, if the top blocker is externally waiting or already owned, the worker **must immediately pick the next highest-value safe Nembra lane and execute it**. Waiting for Xcode is never a valid `GO` outcome while Dashboard, Battery/Range, Rides/Records, Navigation, Home, Vehicle/Controls, visual QA, accessibility, performance, persistence, integration, or other safe closure work remains.
