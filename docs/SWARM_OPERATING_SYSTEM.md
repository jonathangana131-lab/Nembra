# NEMBRA SWARM OPERATING SYSTEM
CURRENT_PROTOCOL_VERSION: 8
STATUS: ACTIVE
CODENAME: QUOTA-INDEPENDENT SELF-HEALING ENGINEERING ORGANIZATION

Repository: `jonathangana131-lab/Nembra`

This document governs parallel ChatGPT engineering workers and supersedes v7 coordination/execution rules when they conflict. Product truth still comes from the current repository, especially `MASTER_CONTINUATION_DIRECTIVE.md`, `PROJECT_STATE.md`, `DECISIONS.md`, `DESIGN_SYSTEM.md`, `PROTOCOL_NOTES.md`, `docs/PRODUCTION_VISUAL_PERFORMANCE_OVERHAUL.md`, and current ES80/battery/ride/navigation/accessibility docs.

V8 exists because v7 survived dead chats and duplicate workers, but a shared Codex automated code-review quota became a team-wide failure point. V8 removes that dependency.

## 0. PRIME DIRECTIVE

**NO SINGLE OPTIONAL EXTERNAL SERVICE MAY STOP NEMBRA DEVELOPMENT.**

A worker must distinguish a PROJECT BLOCKER from ONE TOOL / SERVICE / QUOTA BEING UNAVAILABLE.

These are never, by themselves, valid reasons to stop:
- Codex automated code-review quota exhausted;
- automated review unavailable;
- GitHub Actions queued;
- Xcode runner busy;
- one connector action temporarily rate-limited;
- one GitHub read/write route failing while alternatives remain;
- one PR event skipped;
- one CI run stale;
- one reviewer unavailable.

Never evade a real service quota by rotating accounts, credentials, identities, or other circumvention. V8 bypasses quota dependency architecturally: it simply does not require that optional service.

## 1. PRODUCT KERNEL

Primary physical target: current/newer Tuya-generation **AOVOPRO ES80**.

Nembra must remain a premium native iOS 27 scooter companion, ride computer, evidence system, navigation experience, and truthful vehicle interface.

Permanent rules:
- measured / estimated / displayed / derived / unknown remain distinct;
- never invent telemetry;
- Simulator evidence never becomes physical ES80 proof;
- software implementation never equals physical validation;
- no unverified motorized-hardware writes;
- public/internet research before physical protocol blocking;
- automatic rides remain automatic; no Start Ride workaround;
- ride recovery/history/maps/stats remain truth-preserving;
- battery `% ↔ estimated range` remains a signature interaction;
- range learns from legitimate battery consumption + trustworthy real distance, never advertised range × percent;
- ODO/GPS/route/provider-route evidence remain distinct;
- MapKit cycling suggestions do not prove scooter legality/safety;
- current systems-era UI is not final;
- final visual/interaction/motion/haptics/accessibility/performance work remains a major product program, reasonably half or more of remaining effort after systems mature;
- iPhone 12 / iOS 27 remains the baseline acceptance target unless repository policy changes.

Final experience target: world-class native iOS vehicle software, original Nembra identity, premium EV-instrumentation quality, glanceable/tactile/fluid/fast/accessibile/trustworthy, with no generic Tuya UI, gamer RGB, card soup, debug-first hierarchy, cheap cross-platform look, or giant empty black space accepted as final quality.

## 2. ORGANIZATION

Workers are disposable compute. GitHub durable state is the organization.

Roles:
- RELEASE / INTEGRATION LEAD
- BUILD / CI SHERIFF
- FEATURE ENGINEER
- HARDWARE / PROTOCOL RESEARCH
- PRODUCT / VISUAL ENGINEER
- PERFORMANCE / ACCESSIBILITY ENGINEER
- RECOVERY ENGINEER
- PEER REVIEW / HARDENING ENGINEER

Suggested 7-worker staffing: 1 integration/release, 1 CI/build, 2 feature/domain, 1 product/visual, 1 ES80/protocol or navigation, 1 peer-review/performance/accessibility. Do not manufacture work merely to occupy workers. Prefer finishing/recovering existing work over opening more PRs.

## 3. IDENTITIES / LANES / EPOCHS

WORKER_ID: `chat-<5 lowercase alphanumeric>`
LANE_ID: stable conceptual work name.
EPOCH: ownership generation for a lane.

Highest coherent non-superseded epoch owns the lane. A returning lower-epoch worker MUST yield and pivot.

Branches:
- `parallel/<lane>/<WORKER_ID>`
- `parallel/recover-<lane>/<WORKER_ID>`
- `parallel/integrate-<lane>/<WORKER_ID>`

Never hijack or force-push another worker's branch.

## 4. V8 CONTROL PLANE

Current policy: `docs/SWARM_OPERATING_SYSTEM.md`.
Current control issue: open issue titled `[SWARM CONTROL] Nembra Developer Team v8`.

PR body + branch + commits are the worker's primary durable state. The control issue is for ownership and organization-level messages, not routine narration. This replaces the v7 pattern that grew to hundreds of control-plane comments.

Use these message types when needed:
- `### V8 CLAIM`
- `### V8 TAKEOVER`
- `### V8 HANDOFF`
- `### V8 RELEASE`
- `### V8 GLOBAL DIRECTIVE`
- `### V8 SERVICE INCIDENT`

Routine checkpoints belong primarily in the PR body/commits.

## 5. CLAIM FIRST, EDIT SECOND

Before deep edits:
1. inspect current main;
2. inspect relevant open PRs;
3. inspect recent v8 claims;
4. identify intended paths;
5. post CLAIM;
6. re-read recent claims for race;
7. only then edit.

Earlier meaningful incumbent wins. Later duplicate pivots to review, tests, dependency work, another subsystem, or stale-lane recovery. Never fight for ownership.

## 6. LOCK CLASSES

CLASS A — EXCLUSIVE:
- `Nembra.xcodeproj/project.pbxproj`
- app bootstrap/root composition
- global navigation shell
- shared persistence factories
- global environment wiring
- GitHub workflow/scheduler files
- permanent global policy docs

CLASS B — SUBSYSTEM:
- Home
- Dashboard
- ride persistence
- battery truth chain
- adaptive range
- navigation
- Bluetooth capture / production transport

CLASS C — ADDITIVE:
- isolated NembraCore type/tests
- isolated research/audit docs
- independent fixtures
- non-overlapping package work

Class A gets extra review rigor. No drive-by edits into another active Class A lane.

## 7. MICROBURST LIVENESS

Assume any chat may disappear. Target atomic packet: roughly 5–12 minutes.

Loop:
TARGETED READ → ONE PACKET → FOCUSED VERIFY → COMMIT/PUSH → UPDATE PR STATE → IMMEDIATELY NEXT PACKET.

Create durable state early. Do not hold large irreplaceable work only in chat context. Do not create meaningless heartbeat commits.

## 8. SERVICE-STATE MACHINE

Every shared dependency is classified independently:
`HEALTHY / DEGRADED / EXHAUSTED / UNAVAILABLE / UNKNOWN`.

Services include:
- GitHub metadata/API reads;
- GitHub writes;
- automated Codex code review;
- GitHub Actions;
- self-hosted Xcode 27 runner;
- web/public research;
- Simulator/device tooling;
- physical ES80 access.

A failure in one service changes only work that truly depends on it. Never flatten one outage into “GitHub is broken” unless GitHub itself is genuinely unavailable.

## 9. AUTOMATED CODE REVIEW — HARD RULE

**AUTOMATED CODEX CODE REVIEW IS OPTIONAL. IT IS NOT A MERGE GATE. IT IS NOT A LIVENESS REQUIREMENT.**

Initial v8 mode:
`AUTOMATED_CODE_REVIEW_MODE = DISABLED_BY_DEFAULT`

Workers MUST NOT request or repeatedly retry automated Codex Code Review unless the Integration Lead / CI Sheriff explicitly allocates it to a specific high-risk PR, the service is known available, and it adds value beyond peer review + tests.

If a PR receives `You have reached your Codex usage limits for code reviews`:
1. record `AUTOMATED_REVIEW = UNAVAILABLE_QUOTA`;
2. do not retry;
3. do not wait;
4. do not ask the user to buy credits;
5. do not stop;
6. continue under V8 PEER REVIEW MODE.

Never attempt quota circumvention.

## 10. V8 PEER REVIEW MODE

Peer review uses ordinary repository reads/diffs + engineering reasoning and does not depend on the automated Codex Code Review product.

A peer review records reviewer, PR, exact head, scope/files/contracts/evidence inspected, blocker/important/nonblocking findings, verdict, and truth boundary.

Reviewer rules:
- do not edit worker-owned files unless ownership transfers;
- review exact head;
- read actual source/diff, not PR prose only;
- inspect neighboring contracts and tests;
- distinguish software semantics from hardware proof.

Acceptance review by effect:
- docs/research: owner self-review + currentness/isolation; peer optional unless risky factual claim;
- isolated code: at least one independent peer where practical + focused deterministic tests + exact-head repository gate when required by effect;
- cross-domain/product: at least one strong peer + dependency/consumer review + exact-head Xcode/Simulator;
- Class A / CI / persistence / security / global composition: two independent peers where practical + adversarial/static matrix + exact-head appropriate CI + official platform/security docs where applicable.

Automated Codex review may supplement this but never gates it.

## 11. REVIEW BUDGET

If automated review is ever re-enabled, only Integration Lead/CI Sheriff allocates it.

Priority:
- R0 security / CI trust boundary / destructive persistence
- R1 global composition / motorized-command safety
- R2 complex cross-domain merge-ready feature
- R3 normal isolated feature
- R4 docs/audits

R3/R4 should normally consume zero automated review quota.

## 12. GITHUB API / CONNECTOR THROTTLING MODE

If reads are rate-limited/throttled:
- stop repeated broad searches;
- use exact known PR/file/branch refs;
- batch reads;
- reuse fresh durable facts within the packet;
- switch to local code/test/review work;
- inspect only relevant logs/files;
- re-check GitHub naturally at the next checkpoint.

Do not hammer retry loops. A rate limit on one route is not a project blocker.

## 13. GITHUB WRITE-DEGRADED MODE

If writes temporarily fail but reads/local tooling work:
- do not start a huge unpushable rewrite;
- complete at most one small coherent local packet;
- preserve a patch/diff locally when possible;
- pivot to read-only review, research, test diagnosis, or other reconstructable work;
- retry writes only at natural checkpoints, never tight-loop.

If all durable-write paths remain unavailable and the chat may die, prefer reconstructable read-only work over accumulating large uncheckpointed source changes.

## 14. ACTIONS / XCODE QUEUE MODE

Xcode is a scarce acceptance resource. Do not gate every micro-commit. Use focused/local/package tests during development; request exact-head Xcode at a coherent acceptance checkpoint.

When queued:
- freeze candidate SHA when practical;
- perform useful read-only same-lane work;
- avoid trivial head churn;
- do not busy-poll;
- do not request duplicate runs.

Queued is not green. Resolver success is not Simulator success. Skipped is not acceptance. Green ancestor is not green final head.

Long runner outage may leave a feature as `software candidate, acceptance pending`; the team continues other safe work without fabricating merge proof.

## 15. CI FAILURE MODE

On failure: inspect exact failing job/step, inspect narrow log region, reproduce with cheapest relevant focused test, fix evidence-backed cause, rerun once on new coherent exact head. Never blind-rerun repeatedly. Distinguish infrastructure failure from code failure.

## 16. CONTROL-PLANE OUTAGE MODE

If control comments cannot be written, ownership fallback order is: incumbent open PR, branch name + PR body state, latest durable commit/PR update, then control issue once available. Do not create duplicate implementation merely because the message bus is temporarily unavailable.

## 17. V8 WORKER STATE

Every active v8 worker PR maintains:

### V8 WORKER STATE
PROTOCOL_VERSION: 8
WORKER_ID:
ROLE:
LANE_ID:
EPOCH:
CONTROL_CLAIM:
CURRENT_HEAD:
BASE_OR_PARENT:
OWNED_PATHS:
LOCK_CLASS:
LAST_KNOWN_GREEN:
CURRENT_STATE:
NEXT_PACKET:
DEPENDENCIES:
KNOWN_OVERLAP:
CI_STATE:
AUTOMATED_REVIEW_STATE:
PEER_REVIEW_STATE:
SERVICE_DEGRADATIONS:
BLOCKED_ON:
HARDWARE_STATUS:
HANDOFF_READY: false

`BLOCKED_ON` lists only real blockers to the lane's next meaningful action. Unavailable optional code review is not a blocker. Preserve V5/V7 state as history.

## 18. STALE / RECOVERY

ACTIVE: durable movement within ~15 minutes OR active queued/running acceptance OR explicit long operation.
QUIET: ~15–25 minutes.
SUSPECTED DEAD: ~25–35 minutes with no durable movement and no active operation.
RECOVERY ELIGIBLE: ~35+ minutes for ordinary lanes; Class A use extra caution (~45 min or coordinator decision).

Recovery preserves predecessor, identifies exact durable SHA, posts TAKEOVER, increments epoch, creates a NEW recovery branch, reconciles minimally, and continues the exact next packet. Returning lower epoch yields.

A quota warning is not proof a worker is dead; check whether it continued via other tools before takeover.

## 19. WORK SELECTION

P0 broken main / safety / truth regression
P1 parent blocking multiple dependents
P2 near-ready/recoverable PR
P3 diagnosed failed acceptance
P4 required dependency/main reconciliation
P5 high-value product/system feature
P6 visual/performance/accessibility implementation
P7 ES80 public-first research/passive tooling
P8 review/test hardening

Prefer WIP reduction. If many PRs wait on the same scarce service, stop creating more immediate demand for that service and shift workers to peer review, deterministic hardening, independent subsystems, product/visual work, public research, and dependency cleanup.

## 20. DEPENDENCY DAG

Dependent PR records parent PR, branch, and exact SHA. Parent movement triggers narrow reconcile only when semantically needed or before acceptance. Parent merge triggers fresh-main retarget/reconcile and exact-final-head re-gate where required. Do not duplicate parent code.

## 21. RELEASE / INTEGRATION LEAD

Integration Lead manages merge/dependency order, claim races, scarce resource budgets, service incidents, near-ready work, docs-only main-sync churn, historical-lane cleanup, and future protocol migrations. It must keep optional-tool outages from becoming organization outages.

Workers may merge ordinary isolated work when the v8 acceptance contract is satisfied and ownership is clear.

## 22. CI SHERIFF

CI Sheriff owns workflow/scheduler architecture, trusted self-hosted Xcode admission, runner backlog, duplicate-gate suppression, filtered/skipped vs real acceptance, Xcode priority, and automated review allocation only if that optional service is ever enabled.

Security requirement: untrusted fork/PR-controlled workflow bytes must never gain arbitrary execution on persistent self-hosted runner before trusted same-repository/current-head admission.

## 23. ES80 / HARDWARE PROGRAM

Public first, scooter second. Exhaust official AOVOPRO/AOVO material, Tuya docs, Apple CoreBluetooth/AccessorySetupKit docs, public reverse engineering, component/module docs, regulatory/source material, safe passive capture, and offline analysis before physical blocking.

Evidence classes: DIRECT PHYSICAL / APP OBSERVATION; VERIFIED PUBLIC; CORROBORATED / PROBABLE; GENERIC TUYA/FAMILY FACT; SIMULATOR / SOFTWARE FIXTURE; UNKNOWN / PHYSICAL VERIFICATION REQUIRED.

No candidate UUID/DP/encryption theory authorizes motorized writes. Characteristic `.write` property is metadata, not permission. Subscription success is not scooter-command acknowledgement. The user should not be asked to decode hex.

## 24. BATTERY / RANGE

Pipeline:
RAW EVIDENCE → CLASSIFIED/VERIFIED EVIDENCE → MEASURED SOC → ESTIMATED SOC → DISPLAY SOC → LEARNING WINDOWS → EFFICIENCY MODEL → ESTIMATED RANGE → PRESENTATION.

Display animation frames never become hardware evidence. Stock-app-visible numbers do not become raw verified ES80 telemetry without source proof.

Learned range uses meaningful authoritative battery consumption, trustworthy distance, continuity/truth gates, recent + historical behavior, confidence, outlier rejection, and exclusion of incomplete/bad rides. Never manufacturer-range multiplication. Numeric range presentation fails closed when evidence/currentness/authority is insufficient.

## 25. SPEED / RIDE / NAVIGATION TRUTH

Speed: authoritative measurement is separate from motion assist/presentation interpolation; serialization cannot bypass evidence validation; observed peak is sampled evidence, not perfect continuous-time top speed; acceleration timing must state its clock/evidence basis and never overclaim physical crossing time.

Rides: automatic, crash-safe, transport gaps explicit, ODO/GPS/route sources distinct, recovery never invents continuity.

Navigation: provider route is planning evidence, route selection is explicit, stale async requests fail closed, suggestions do not prove scooter legality, route geometry/ETA never becomes measured ride-history distance.

## 26. PRODUCT VISUAL / PERFORMANCE PROGRAM

Current UI is a functional baseline, not protected final composition.

Required loop:
REAL iPHONE 12 / iOS 27 SIMULATOR → SCREENSHOT → CRITIQUE → REDESIGN → IMPLEMENT → INTERACT → SCREENSHOT → PROFILE → ACCESSIBILITY → FIX → REPEAT.

Major targets: premium Home hierarchy, signature landscape cockpit, battery/range interaction, live ride + navigation, Ride History/Details/maps/stats, charging/low-battery/reconnect/error/learning states, cohesive motion/haptics, polished orientation continuity.

Performance: 60 Hz where appropriate; narrow high-frequency observation; no telemetry invalidating whole screen; avoid excessive blur/material work; profile maps/routes/history/navigation + telemetry, launch, transitions, long sessions, memory/leaks; physical iPhone where Simulator cannot prove behavior.

Accessibility: VoiceOver, Dynamic Type, Reduce Motion, Reduce Transparency, Increase Contrast, Differentiate Without Color, Voice Control, Switch Control, touch targets, and physical-device validation where required.

## 27. CONTEXT ECONOMY

DO exact file/PR reads, narrow diffs, focused logs, concise PR state, reuse current packet facts, batch related reads/writes, and load only relevant product docs after boot.

DO NOT repeatedly enumerate all PRs, reread the whole OS every packet, dump giant logs, repeatedly fetch unchanged files, maintain a second roadmap in chat, narrate every tool call, or request automated reviews on every PR.

## 28. FINAL MERGE GATE BY EFFECT

Docs/research: current, isolated, source claims checked, no fabricated Xcode requirement.

Isolated package/domain code: deterministic tests, independent peer review where practical, exact-head repository/Xcode gate when repository policy/effect requires it.

App/UI/integration: focused tests, peer review, exact final head Xcode 27/iPhone 12/iOS 27 Simulator, screenshots/artifacts where visual, accessibility/performance evidence appropriate to change.

Class A/security/persistence: stronger adversarial review, two peers where practical, exact-head gate, official docs/security contract as relevant, expected-head merge protection.

Physical claims: software gates never substitute for required physical ES80/iPhone proof.

Automated Codex Code Review is optional and not part of the required gate.

## 29. MIGRATING V7 → V8

Existing worker:
1. DO NOT restart.
2. DO NOT abandon/recreate branch.
3. preserve V5/V7 history.
4. read current v8 OS.
5. keep current lane/epoch unless superseded.
6. add/update `### V8 WORKER STATE`.
7. set `AUTOMATED_REVIEW_STATE` accurately.
8. if code-review quota is exhausted, switch immediately to peer-review mode.
9. remove automated code review from `BLOCKED_ON`.
10. continue from exact durable head.
11. do not re-request automated review.
12. after merge/release, use v8 control plane/work queue.

Migration changes organization mechanics, not product semantics.

## 30. LEGITIMATE STOP CONDITIONS

Intentional stop only when:
A. a truly user-only external fact/action is required AND no independent useful work exists;
B. next action would be unsafe;
C. all available tool/service paths needed for ANY useful work are unavailable;
D. all meaningful work is actively owned and even review/research would duplicate it;
E. platform externally ends the run.

NOT stop conditions: Codex review quota, queued CI, one connector error, one stale run, one merge, one completed packet, one reviewer unavailable.

Before final response ask: `Is there any safe useful tool action available under current service states?` If yes, execute it.

## 31. V8 BOOT ALGORITHM

1. inspect live main;
2. read CURRENT_PROTOCOL_VERSION;
3. read newest v8 control issue GLOBAL DIRECTIVE / service incident;
4. inspect only relevant/recent open PRs;
5. determine service states;
6. generate unique WORKER_ID;
7. choose role;
8. select highest-value unowned/recoverable lane;
9. identify paths + lock class;
10. post V8 CLAIM;
11. re-scan recent claims;
12. branch;
13. execute first 5–12 minute packet;
14. focused verify;
15. push durable checkpoint;
16. open/update PR with V8 WORKER STATE;
17. request NO automated Codex review by default;
18. obtain peer review + tests appropriate to risk;
19. use exact-head Xcode only at coherent acceptance checkpoint;
20. if any optional service fails, enter its degraded mode and KEEP WORKING;
21. merge with expected-head protection when actual acceptance contract is satisfied;
22. release lane;
23. inspect fresh team and immediately continue safe work.

DO NOT BEGIN WITH A GIANT PLAN. START WITH LIVE TOOLS. DO NOT ASK THE USER TO BABYSIT THE TEAM.
