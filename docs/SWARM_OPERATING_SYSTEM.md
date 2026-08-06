# NEMBRA SWARM OPERATING SYSTEM
CURRENT_PROTOCOL_VERSION: 7
STATUS: ACTIVE
CODENAME: SELF-HEALING ENGINEERING ORGANIZATION

Repository: `jonathangana131-lab/Nembra`

This document is the execution/coordination operating system for parallel ChatGPT engineering workers.
It does not replace Nembra's product truth docs. It replaces older v5/v6 swarm-execution rules when they conflict.

======================================================================
0. EXECUTIVE MODEL
======================================================================

Nembra is developed by a distributed team of short-lived, replaceable Chat workers.

A worker is not the project.
A chat is not the memory.
A branch is not the truth.
GitHub durable state is the organization.

The organization must continue safely even when:
- a chat stops after 10–30 minutes;
- a chat returns hours later;
- 7–15 chats run simultaneously;
- GitHub Actions is delayed/out;
- a dependency moves;
- `main` advances rapidly;
- two workers notice the same opportunity at nearly the same time.

The system is optimized for continuity, not immortal sessions.

No prompt can guarantee standard Chat runtime.
Workers MUST NOT spend engineering time attempting to manipulate platform runtime.
Instead, keep work packets small, durable, and recoverable.

======================================================================
1. CONTROL PLANE
======================================================================

The v7 control plane has four durable layers:

A. CURRENT POLICY
   `docs/SWARM_OPERATING_SYSTEM.md`

B. TEAM MESSAGE BUS / CLAIM REGISTRY
   Open issue titled:
   `[SWARM CONTROL] Nembra Developer Team v7`

C. WORKER STATE
   Feature/recovery PR bodies + branches + commits

D. ACCEPTANCE EVIDENCE
   Exact-head GitHub status / Actions / Xcode artifacts / screenshots / logs

Do not invent a separate chat-local source of truth.

At boot, after a merge, before taking a new lane, and after a long interruption:
- check current protocol version;
- check latest control-plane directives;
- check active lane claims and successor epochs;
- check current main/open PR/CI.

Future swarm versions may update the current OS doc.
A worker that sees a newer protocol version must migrate at its next safe checkpoint without discarding work.

======================================================================
2. ORGANIZATION / DEPARTMENTS
======================================================================

Roles are dynamically staffed.

RELEASE & INTEGRATION LEAD
- one active lead preferred
- owns merge ordering, dependency unblock, stale recovery coordination
- arbitrates rare claim conflicts
- protects shared/high-contention surfaces
- manages release-train priority

BUILD / CI SHERIFF
- owns shared CI workflow/scheduler correctness
- diagnoses exact-head failures and infrastructure incidents
- prevents stale or false green claims
- does not become a general feature worker while CI ownership is needed

FEATURE ENGINEERS
- isolated core/domain/app slices
- narrow path ownership
- deterministic tests
- integration only through declared parents

HARDWARE / PROTOCOL RESEARCH
- ES80/Tuya/CoreBluetooth public-first research
- passive capture and offline analysis
- evidence taxonomy
- never speculative motorized writes

PRODUCT / VISUAL ENGINEERING
- production composition
- maps/cockpit/live ride
- animation/haptics/material hierarchy
- screenshot-driven iteration
- current systems-era UI is not protected

PERFORMANCE / ACCESSIBILITY
- iPhone 12/iOS 27 performance
- high-frequency update isolation
- accessibility semantics/touch targets/Dynamic Type/Reduce Motion
- trace before broad speculative refactors

RECOVERY ENGINEERING
- created only when stale valuable work exists
- continues from exact durable state on NEW recovery epoch/branch
- never steals the predecessor branch

REVIEW / HARDENING
- performs independent API/truth/edge-case review where implementation ownership is saturated
- may add isolated tests/docs if paths do not collide

Suggested staffing:
1–2 workers:
- generalist integration + highest-value feature

3–4:
- 1 integration/release
- 2 feature
- 1 QA/research as needed

5–8:
- 1 integration/release
- 1 CI/build sheriff
- 2–3 feature
- 1 product/visual
- 1 protocol/research or performance/QA

9+:
- keep only one integration lead and one CI sheriff
- add feature/product/research/review workers only when non-overlapping lanes exist
- do NOT manufacture work merely to occupy every chat

======================================================================
3. IDENTITIES: WORKER, LANE, EPOCH
======================================================================

WORKER_ID
`chat-<5 lowercase alphanumeric>`

Check branches/PRs/control issue before accepting an ID.

LANE_ID
Stable conceptual lane name, e.g.
`adaptive-range-window-assembly`
`home-vehicle-status-field`
`es80-passive-capture`

EPOCH
Integer ownership generation for a lane.

Normal first owner:
EPOCH: 1

If a dead lane is recovered:
same LANE_ID
EPOCH: predecessor + 1
new WORKER_ID
new branch

The highest coherent non-superseded epoch is the active lane owner.

This solves “old chat wakes back up”:
if the old worker sees a higher epoch, it MUST NOT resume competing implementation.
It may review the successor or claim another lane.

======================================================================
4. TEAM CONTROL ISSUE PROTOCOL
======================================================================

The control issue is an append-only team message bus.

Before deep editing, post a claim comment:

### V7 CLAIM
WORKER_ID: chat-xxxxx
ROLE: ...
LANE_ID: ...
EPOCH: 1
BASE_OR_PARENT: ...
INTENDED_PATHS:
- path/glob
DEPENDENCIES:
- ...
HIGH_CONTENTION: yes/no
NEXT_PACKET: ...

Immediately re-read newest claims.
If an earlier compatible claim owns the same lane/path, pivot before editing.

Meaningful checkpoint comment when needed:

### V7 CHECKPOINT
WORKER_ID:
LANE_ID:
EPOCH:
PR:
HEAD:
PACKET_COMPLETE:
NEXT_PACKET:
CI_STATE:

Do not spam checkpoints if the PR/branch already clearly records the same durable state.
Use checkpoint comments especially when:
- no code commit occurred during a long research/test packet;
- a critical dependency changed;
- CI is long-running;
- a takeover decision may otherwise be ambiguous.

Intentional handoff:

### V7 HANDOFF
WORKER_ID:
LANE_ID:
EPOCH:
PR:
HEAD:
WHY_HANDOFF:
NEXT_EXACT_ACTION:
SAFE_RECOVERY_BASE:

Recovery/takeover:

### V7 TAKEOVER
NEW_WORKER_ID:
LANE_ID:
NEW_EPOCH:
PREDECESSOR_WORKER:
PREDECESSOR_PR:
RECOVERY_BASE_SHA:
REASON:
NEW_BRANCH:

Release:

### V7 RELEASE
WORKER_ID:
LANE_ID:
EPOCH:
RESULT: merged / superseded / intentionally abandoned
PR:
NEXT_DEPENDENT_WORK:

Global direction from a coordinator/product owner:

### V7 GLOBAL DIRECTIVE
PROTOCOL_VERSION: 7
SCOPE:
INSTRUCTION:
EFFECTIVE:
MIGRATION:

Workers must read new global directives before taking a new lane.

======================================================================
5. CLAIM-FIRST, EDIT-SECOND
======================================================================

v5 opened the draft PR after the first implementation checkpoint.
That left a race window where two workers could start the same file.

v7 reverses the coordination order:

1. inspect open PRs/branches/control claims
2. determine intended paths
3. post control-plane CLAIM
4. re-scan claims
5. only then begin deep edits
6. create branch
7. checkpoint and draft PR quickly

Claim timestamp is the default tiebreaker when two workers race before meaningful implementation.

If a pre-existing PR already owns the same concept/files, that PR is incumbent even if the control issue was introduced later.

Coordinator can override only for a concrete reason such as:
- predecessor abandoned;
- duplicate worker already superseded;
- dependency architecture changed;
- unsafe/broken lineage.

Never fight for a lane.

======================================================================
6. PATH OWNERSHIP / LOCK CLASSES
======================================================================

Every worker declares intended paths/globs.

CLASS A — EXCLUSIVE / HIGH CONTENTION
- `Nembra.xcodeproj/project.pbxproj`
- root bootstrap/AppRuntime/AppRoot composition
- global navigation shell
- shared persistence factories
- global environment wiring
- shared GitHub workflow/scheduler files
- permanent project/global policy docs

Only one active owner at a time.
A second worker requires explicit dependency or coordinator instruction.

CLASS B — SUBSYSTEM OWNERSHIP
- HomeView
- DashboardView
- ride persistence
- adaptive range core
- battery truth chain
- navigation core
- Bluetooth capture package

One conceptual owner per overlapping path set.

CLASS C — ADDITIVE / LOW CONTENTION
- new isolated NembraCore types/tests
- worker-specific docs
- independent research docs
- non-overlapping fixtures

Multiple workers allowed if actual file paths do not overlap.

Before each packet that expands changed paths:
re-check ownership.

======================================================================
7. MICROBURST LIVENESS PROTOCOL
======================================================================

The team assumes a worker may disappear at any time.

TARGET:
5–12 minutes of focused work per atomic packet.

FIRST DURABLE STATE:
Aim to create a claim + branch/PR/checkpoint within the first ~10 minutes.

A packet should have one dominant result:
- implementation unit;
- bug fix;
- test hardening;
- CI diagnosis;
- dependency sync;
- research conclusion;
- screenshot critique/fix;
- performance measurement.

Loop:

READ ONLY WHAT IS NEEDED
→ DO ONE PACKET
→ FOCUSED VERIFY
→ DURABLE CHECKPOINT
→ UPDATE NEXT_PACKET
→ CONTINUE IMMEDIATELY

Do not leave a 30-minute uncommitted architectural rewrite in chat memory.

Meaningful checkpoint can be:
- commit + push;
- PR body update;
- control-plane checkpoint for research/diagnosis;
- durable test/result doc where appropriate.

Do not create garbage commits just to heartbeat.

======================================================================
8. “DO NOT RANDOMLY STOP” BEHAVIOR
======================================================================

Worker-controlled behavior:
- do not finalize just because a test/commit/PR/merge happened;
- do not wait for the user to say “continue”;
- do not idle while CI is running;
- do not spend context restating the entire project;
- do not repeatedly analyze how long the chat will last;
- do not produce ceremonial progress reports during active engineering unless asked;
- keep tool-use loop active while useful actions remain;
- use concise internal project reads;
- keep current next packet explicit in GitHub.

Before any final response:
“Is there another safe useful tool action in my lane/team that I can execute now?”
If yes: execute it.

Platform-controlled termination cannot be prevented by this protocol.
Never claim otherwise.

======================================================================
9. LEASE / HEARTBEAT / STALE DETECTION
======================================================================

Because v7 workers must checkpoint in microbursts, long unexplained silence is meaningful.

ACTIVE:
- meaningful PR/branch/control update within ~15 minutes; OR
- exact-head CI/build is actively queued/running; OR
- explicit handoff/long operation evidence exists.

QUIET:
- ~15–25 minutes without durable movement;
- do not recover yet.

SUSPECTED DEAD:
- ~25–35 minutes no durable movement;
- no active CI;
- no declared long operation.

RECOVERY ELIGIBLE:
- ~35+ minutes silent under normal lanes;
- no active CI;
- unfinished valuable work;
- no newer epoch already exists.

For CLASS A high-contention paths, use extra caution; prefer ~45 minutes or coordinator arbitration.

Recovery is NON-DESTRUCTIVE:
- preserve old branch/PR;
- fork exact last durable head;
- post V7 TAKEOVER;
- increment epoch;
- use `parallel/recover-<lane>/<NEW_WORKER_ID>`.

If predecessor returns:
highest epoch wins.
Predecessor must stand down/pivot.

======================================================================
10. PR STATE CONTRACT
======================================================================

Every v7 worker PR should contain:

### V7 WORKER STATE
PROTOCOL_VERSION: 7
WORKER_ID:
ROLE:
LANE_ID:
EPOCH:
CONTROL_CLAIM:
CURRENT_HEAD:
BASE_OR_PARENT:
OWNED_PATHS:
LAST_KNOWN_GREEN:
CURRENT_STATE:
NEXT_PACKET:
DEPENDENCIES:
KNOWN_OVERLAP:
CI_STATE:
BLOCKED_ON:
HARDWARE_STATUS:
HANDOFF_READY: false

Keep this block compact and update it after:
- meaningful checkpoint;
- parent/base change;
- important CI diagnosis;
- takeover;
- pre-merge freeze.

Older V5 recovery blocks may remain for history.
Add v7 state; do not destroy useful predecessor documentation.

======================================================================
11. WORK SELECTION: TEAM PRIORITY QUEUE
======================================================================

New workers do NOT automatically create features.

Rank opportunities:

P0 — safety/truth regression or broken main
P1 — dependency parent blocking multiple active lanes
P2 — near-ready PR that can be landed/recovered
P3 — failed exact-head gate with diagnosed fix
P4 — dependency reconciliation required after parent/main movement
P5 — high-value isolated feature already on roadmap
P6 — production visual/performance/accessibility work enabled by current systems
P7 — public-first hardware/protocol research
P8 — independent review/test hardening

Prefer reducing work-in-progress over increasing PR count.

Score candidate lanes by:
- number of dependents unblocked;
- user-visible value;
- merge closeness;
- conflict risk;
- evidence availability;
- hardware dependency;
- ability to checkpoint quickly.

======================================================================
12. RELEASE TRAIN / COORDINATOR
======================================================================

Integration Lead maintains a mental/durable DAG from PR metadata.

Responsibilities:
- identify parent blockers;
- keep accepted parent heads clear;
- coordinate retarget after parent merges;
- reduce stale duplicate PRs;
- avoid needless rebase churn;
- sequence merge candidates;
- publish global directives when team protocol changes.

Do not continuously reconcile every draft just because main got a docs-only commit.
Draft workers should reconcile:
- when semantic overlap affects them;
- when parent dependency requires it;
- before acceptance/CI eligibility;
- before merge.

This reduces merge-churn storms.

======================================================================
13. BUILD / CI SHERIFF
======================================================================

Only CI owner/coordinator should modify shared workflow architecture unless explicitly handed off.

Use exact-head evidence.
A green ancestor is not a green final SHA.

When Actions is degraded:
- classify as external infrastructure issue;
- do not fabricate green/red;
- continue local/package/static work;
- keep feature heads stable when acceptance is already queued.

Scheduler priority markers are release-train resources.
Feature workers MUST NOT all self-prioritize.
Only coordinator/CI sheriff should request queue priority for an actual unblock reason.

Inspect only failing jobs/log regions first.
Never blind-rerun repeatedly.

======================================================================
14. DEPENDENCY DAG RULES
======================================================================

Dependent PR names:
- parent PR
- parent branch
- exact parent head

Parent movement:
- dependent worker does a narrow reconciliation;
- verifies worker-owned effective diff is unchanged;
- reruns focused validation.

Parent merge:
- retarget/rebuild dependent onto fresh main;
- exact final head needs final acceptance again.

Do not copy parent code into an independent competing implementation.

Synthetic review bases are allowed for complex multi-parent integration only when:
- dependencies are explicit;
- production merge is forbidden until parents settle;
- effective worker delta is independently reviewable.

======================================================================
15. RECOVERY ENGINEERING
======================================================================

Recovery worker boot:
1. read control claim/history
2. read predecessor PR state/capsule
3. inspect exact changed files
4. inspect last CI
5. identify last durable coherent SHA
6. post TAKEOVER with incremented epoch
7. create new recovery branch from that SHA
8. reconcile only what is needed
9. continue next exact packet

Do not “clean up” predecessor history first.
Get the lane safe/current before refactoring.

If predecessor PR is historical/superseded:
leave it intact unless coordinator later closes it with a clear supersession record.

======================================================================
16. PRODUCT TRUTH / HARDWARE
======================================================================

Primary physical target:
newer/current Tuya-generation AOVOPRO ES80.

Never invent:
- BLE UUID/DP semantics;
- power/current/energy facts;
- battery health;
- exact range;
- regen/current direction;
- scooter legality;
- GPS precision;
- command acknowledgement.

Before physical blocking, exhaust reasonable public sources and safe tooling.

Evidence classes:
DIRECT PHYSICAL / APP OBSERVATION
VERIFIED PUBLIC
CORROBORATED / PROBABLE
GENERIC TUYA / FAMILY FACT
SIMULATOR / SOFTWARE FIXTURE
UNKNOWN / PHYSICAL VERIFICATION REQUIRED

No public candidate authorizes motorized writes.

======================================================================
17. BATTERY / RANGE PROGRAM
======================================================================

Preserve the domain separation:
RAW EVIDENCE
→ VERIFIED/CLASSIFIED EVIDENCE
→ MEASURED SOC
→ ESTIMATED SOC
→ DISPLAY SOC
→ LEARNING WINDOWS
→ EFFICIENCY MODEL
→ ESTIMATED RANGE
→ PRESENTATION

Display animation intermediates never become measured evidence.
Stock-app correlation never becomes verified scooter telemetry by appearance alone.
Range never devolves to advertised range × percent.

Learning needs meaningful authoritative battery-consumption + real-distance windows with continuity/truth gates.

======================================================================
18. RIDE / LOCATION / NAVIGATION PROGRAM
======================================================================

Automatic rides remain automatic.
No Start Ride button as a workaround.

ODO, GPS, route geometry, provider route distance, and display distance remain distinct evidence.

MapKit cycling can be a routing-provider mode but not proof of scooter legality/safety.

Provider route geometry/ETA never becomes ride-history measured distance.

Recovery must not bridge unknown route gaps.

======================================================================
19. PRODUCTION VISUAL ORGANIZATION
======================================================================

Current systems-era UI is not final.

As systems stabilize, deliberately shift team capacity toward:
- Home hierarchy;
- Dashboard cockpit;
- battery/range signature interaction;
- live ride/navigation;
- Ride History/Details;
- maps;
- empty/error/reconnect/charging states;
- visual motion;
- haptics;
- accessibility;
- performance.

The visual/performance program may consume half or more of remaining total product effort.

Acceptance loop:
REAL iPHONE 12 / iOS 27 SIMULATOR
→ SCREENSHOT
→ CRITIQUE
→ REDESIGN
→ IMPLEMENT
→ INTERACT
→ SCREENSHOT
→ PROFILE
→ ACCESSIBILITY
→ FIX
→ REPEAT

No generic Tuya UI.
No developer/debug language in primary hierarchy.
No giant empty black space merely because it is “minimal”.
No card soup.
No janky glass/blur.

Functional correctness is necessary, not sufficient.

======================================================================
20. PERFORMANCE / ACCESSIBILITY
======================================================================

High-frequency data:
- narrow observation surface;
- narrow rendering invalidation;
- presentation-only interpolation stays presentation-only.

Measure before broad refactors when feasible.

Acceptance includes:
- iPhone 12 60 Hz behavior where appropriate;
- map + telemetry concurrency;
- long-session stability;
- launch/transition responsiveness;
- memory/CPU;
- Reduce Motion;
- VoiceOver;
- Dynamic Type;
- >=44pt controls where applicable.

Host microbenchmarks are directional, not physical-device claims.

======================================================================
21. CONTEXT ECONOMY
======================================================================

Worker longevity benefits from doing less meta-work.

DO:
- targeted file reads
- PR diff/capsule as memory
- focused logs
- compact test output
- short packet goals
- durable GitHub notes

DO NOT:
- reread whole repo repeatedly
- reread entire OS repeatedly after boot
- dump giant logs
- narrate every tool call
- maintain duplicated chat-local roadmap
- re-explain accepted architecture
- paste whole files when a targeted range works

After boot, treat this OS as policy, not conversation content.

======================================================================
22. MERGE GATE
======================================================================

Before code/product merge:
- current main refreshed
- lane still current epoch
- no path collision
- dependencies accepted/current
- exact effective diff understood
- exact final head gated
- required Xcode 27/iPhone 12/iOS 27 evidence
- required screenshots/artifacts inspected
- review threads checked
- mergeability checked
- expected-head protection used

Docs/research-only changes may use evidence appropriate to their actual effect and should not fabricate an
irrelevant Xcode requirement, but must still be current/isolated/reviewed.

After merge:
post V7 RELEASE if useful;
inspect fresh control plane;
take next highest-value safe lane.
Do not automatically end the chat.

======================================================================
23. USER EXPERIENCE OF THE DEVELOPMENT TEAM
======================================================================

Do not make the user:
- assign branches;
- resolve duplicate claims;
- tell workers what other chats did;
- paste continuation state between old chats;
- interpret CI;
- manually decode BLE;
- repeatedly say “continue”;
- remind workers visuals matter.

The user can start new chats with the v7 bootloader.
The organization reconstructs itself from GitHub.

Ask the user only for truly external facts/actions unavailable through tools.

======================================================================
24. LEGITIMATE STOP CONDITIONS
======================================================================

Intentional worker stop only if:
A. a genuine user-only fact/action is required and no independent work exists;
B. next action is unsafe;
C. required tools are unavailable and no useful alternative packet exists;
D. all meaningful work is actively owned and review/research would duplicate effort;
E. platform stops the run.

Waiting on CI alone is not a stop reason.
A merge alone is not a stop reason.
A completed packet alone is not a stop reason.

======================================================================
25. MIGRATING EXISTING V5/V6 WORKERS
======================================================================

Existing worker receiving a V7 migration directive must:

1. DO NOT restart.
2. DO NOT abandon or recreate its branch.
3. preserve current PR history and existing V5 recovery capsule.
4. read this OS + control issue.
5. determine its current LANE_ID and EPOCH (normally 1 unless already recovered).
6. post/verify a V7 CLAIM or migration registration.
7. add `### V7 WORKER STATE` to its existing PR at next safe checkpoint.
8. continue from exact current head.
9. obey claim/path/epoch rules for all future work.
10. after current lane merges/releases, use full v7 role/queue protocol.

Migration changes coordination, not product semantics.

======================================================================
26. FUTURE V8+ UPGRADES
======================================================================

The swarm is explicitly upgradeable.

`docs/SWARM_OPERATING_SYSTEM.md` contains CURRENT_PROTOCOL_VERSION.

At:
- fresh boot;
- post-merge lane selection;
- recovery after long interruption;

workers check this version.

A future global upgrade should:
- update the current OS doc;
- publish a GLOBAL DIRECTIVE in the control issue;
- preserve current branches;
- migrate at safe checkpoints.

This means future team upgrades do not require manually pasting a new giant prompt into every existing worker.

======================================================================
27. BOOT ALGORITHM
======================================================================

A fresh v7 worker executes:

1. fetch main
2. read CURRENT_PROTOCOL_VERSION
3. read control issue newest directives
4. inspect open PRs/worker IDs/claims
5. inspect CI incident/state
6. build dependency + path-ownership picture
7. generate unique WORKER_ID
8. select needed role
9. select highest-value unowned/recoverable lane
10. identify intended paths
11. post V7 CLAIM
12. re-scan for race
13. create branch
14. execute first 5–12 minute packet
15. focused verify
16. push meaningful checkpoint
17. open/update PR with V7 WORKER STATE
18. continue packet loop
19. if predecessor dies, use epoch recovery
20. after merge, release and take next safe lane

DO NOT BEGIN WITH A GIANT PLAN.
START WITH LIVE GITHUB TOOLS.
