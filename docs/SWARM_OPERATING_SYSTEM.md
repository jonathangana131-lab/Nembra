# NEMBRA SWARM OPERATING SYSTEM
CURRENT_PROTOCOL_VERSION: 11
STATUS: ACTIVE
CODENAME: FEATURE CELL RELEASE FABRIC

Repository: `jonathangana131-lab/Nembra`

V11 is a throughput-architecture rewrite built on V10 Continuous Shift Runtime.

V10 keeps individual workers behaving like long-running engineers. V11 makes 10, 15, 20, or more concurrent strong agents translate into **finished Nembra product** instead of PR sprawl, repeated reconciliation, and a giant single-Xcode acceptance funnel.

Desired individual shift target remains **180+ minutes of continuous useful engineering when meaningful work exists and the outer platform permits it**. This is a behavioral target, not a runtime guarantee. Never attempt to circumvent runtime, context, quota, security, review, or permission boundaries.

## 0. Prime directives

1. **ONE WORKER, ONE FEATURE CELL AT A TIME.**
2. **ONE FEATURE CELL, ONE COHERENT USER-VISIBLE OUTCOME.**
3. **BIG FEATURES MAY HAVE MANY AGENTS WORKING TOGETHER.**
4. **AGENT_COUNT != FEATURE_COUNT.** More agents deepen important features before creating more features.
5. **DO NOT LEAVE A FEATURE HALF-FINISHED TO START SOMETHING SHINY.**
6. **PERFECT THE FEATURE BEFORE THE CELL DISSOLVES.**
7. **DO NOT SPEND FULL XCODE ACCEPTANCE ON EVERY MICRO-PR.**
8. **EXPENSIVE ACCEPTANCE IS BATCHED THROUGH RELEASE TRAINS.**
9. **NON-OVERLAPPING MAIN DRIFT DOES NOT AUTOMATICALLY ERASE VALID FOCUSED EVIDENCE.**
10. **THE FINAL RELEASE TRAIN PROVES THE ACTUAL COMBINED HEAD.**
11. **MORE AGENTS SHOULD CREATE DEPTH, REVIEW, TESTS, PERFORMANCE, ACCESSIBILITY, VISUAL POLISH, AND FASTER DEFECT BURN-DOWN — NOT MORE PRS.**
12. **A CHECKPOINT IS A SAVE POINT, NOT AN ENDPOINT.**
13. **FINAL IS NOT A NORMAL WORKER STATE.**
14. **ONE OPTIONAL SERVICE OR QUOTA MAY NOT STOP DEVELOPMENT.**
15. **NEVER INVENT HARDWARE, TELEMETRY, SIMULATOR, CI, OR PHYSICAL-DEVICE EVIDENCE.**

## 1. Product kernel

Primary physical target: current/newer Tuya-generation **AOVOPRO ES80**.

Permanent truth:
- measured / estimated / displayed / derived / retained / unknown stay distinct;
- Simulator/software proof != physical ES80 verification;
- public/probable protocol evidence != verified physical behavior;
- no unverified motorized-hardware writes;
- automatic rides remain automatic and crash-safe;
- route gaps remain gaps;
- ODO / GPS / recorded route / provider route remain separate evidence;
- battery `% ↔ estimated range` remains a signature interaction;
- range learns from legitimate battery use + trustworthy real distance, never advertised range × percentage;
- stale/weak/provisional/estimated/retained evidence remains qualified or fails closed;
- display animation never becomes telemetry;
- observed peak speed is sampled evidence, not exact continuous physical top speed;
- acceleration timing reflects its real observation clock;
- navigation suggestions do not prove scooter legality/safety;
- package-green does not prove manually wired app-target source visibility;
- current systems UI is not final;
- final visual/motion/haptics/accessibility/performance work is a major release program;
- baseline iPhone 12 / iOS 27 unless policy changes.

Final product target: original Nembra, premium native iOS 27 vehicle software, premium EV-instrumentation quality, signature battery/range, glanceable speed, premium Home, landscape/live cockpit, strong maps/history/stats/navigation, restrained native materials/Liquid Glass, excellent motion/haptics/accessibility. Reject generic Tuya dashboard, card soup, gamer RGB, giant useless black space, debug-first hierarchy, cheap cross-platform feel, fake metrics, and technically-correct-but-mediocre final UI.

## 2. Feature-cell organization

A **Feature Cell** is a temporary cross-functional mini-team dedicated to one feature outcome until that feature is perfected and integrated.

Examples:
- Battery Truth + Learned Range
- Navigation + Route Planning
- Navigation + Live Ride Cockpit
- ES80 Passive Capture + CoreBluetooth Adapter
- Automatic Ride Durability
- Ride History + Maps + Statistics
- Home Product Redesign
- Dashboard Product Overhaul

Workers do not abandon a cell because one PR merged. The cell survives implementation, review, QA, product polish, local acceptance, release-train admission, integrated acceptance, merge, and post-merge observation.

## 3. Elastic cell sizing

Cell size is dynamic.

**Small feature: 2–3 agents**
- captain/builder
- reviewer
- verifier

**Medium feature: 4–5 agents**
- captain/builder
- second builder/integration specialist
- red-team reviewer
- verifier
- optional product/performance/accessibility specialist

**Large feature: 6–8 agents**
Appropriate for major cross-cutting outcomes such as Navigation + Live Ride, Battery/Range end-to-end, Production ES80 transport, Ride persistence/location/history, or major Home/Dashboard overhaul.

Possible roles:
1. feature captain / architect
2. implementation builder A
3. implementation builder B
4. red-team reviewer
5. verifier / test engineer
6. product / SwiftUI specialist
7. performance / accessibility specialist
8. integration / build specialist

**Huge flagship feature: 8+ agents** is allowed only when the feature genuinely decomposes into independent subdomains that recombine into one user-visible outcome.

Example `Navigation + Live Ride Cockpit`:
- route-planning builder
- MapKit adapter builder
- navigation-session/reroute builder
- Dashboard integration builder
- product/SwiftUI specialist
- performance/accessibility engineer
- red-team reviewer
- verifier/artifact QA

This remains ONE feature program, not eight random features.

## 4. Scaling by total agent count

Guidelines, not hard caps:

- **6–9 agents:** normally 2 feature cells + release/CI role.
- **10–14 agents:** normally 3 feature cells + Release Commander + CI Sheriff.
- **15–20 agents:** normally 3–4 feature cells; highest-value features become larger cells.
- **20–30 agents:** normally 4–5 feature cells maximum unless architecture genuinely supports more; flagship cells may contain 6–8+ agents.
- **30+ agents:** increase depth first: reviewers, test engineers, performance, accessibility, visual QA, hardware/public research, integration, defect burn-down. Do not automatically increase feature count.

The organization optimizes finished features, not maximum simultaneous feature count.

## 5. One feature at a time

Every worker has:

`FEATURE_CELL_ID`
`FEATURE_ID`
`FEATURE_ROLE`
`FEATURE_LOCK = true`

While `FEATURE_LOCK = true`, the worker may not begin unrelated implementation.

Allowed same-feature work:
- implementation;
- deterministic/adversarial tests;
- API review;
- concurrency/race review;
- product review;
- accessibility;
- performance;
- screenshot/artifact QA;
- build graph/source visibility;
- dependency integration;
- feature-specific docs;
- rollback/recovery analysis.

If CI is waiting, stay inside the same feature and deepen it. Do not escape to another random feature merely to appear busy.

Release Commander may release a worker from a feature only when the feature is merged/perfected, cancelled/superseded, or genuinely externally blocked after all independent work is exhausted.

## 6. Feature mission card

Every cell owns one issue:

`[FEATURE CELL] <feature name>`

Required state:

```md
### V11 FEATURE MISSION
FEATURE_CELL_ID:
FEATURE_ID:
USER_VISIBLE_OUTCOME:
WHY_NOW:
CAPTAIN:
BUILDERS:
REVIEWERS:
VERIFIERS:
SPECIALISTS:
BASELINE_MAIN:
CELL_INTEGRATION_BRANCH:
DELIVERY_BRANCH:
RISK_TIER:
OWNED_PATHS:
SUBDOMAINS:
DEPENDENCIES:
NON_GOALS:
TRUTH_BOUNDARY:
PHYSICAL_BOUNDARY:
DEFINITION_OF_PERFECTION:
CURRENT_PHASE:
KNOWN_DEFECTS:
LOCAL_GATE_STATUS:
TRAIN_ELIGIBILITY:
RELEASE_TRAIN:
STATUS:
```

The mission issue is canonical feature-level memory. Do not spread the complete feature state across dozens of PR comments.

## 7. Subdomains inside large cells

Large cells split ONE feature into subdomains.

Example Navigation + Live Ride:
- A: route planning / MapKit
- B: navigation session / reroute
- C: Dashboard integration
- D: visual/interaction
- E: performance/accessibility

Each subdomain has one active owner. The Feature Captain owns the integration branch and feature contract. Workers do not edit another active subdomain's files without handoff.

## 8. Branch topology

Prefer:

```text
cell/<feature>/integration
    ↑
    ├─ cell/<feature>/<subdomain-a>/<worker>
    ├─ cell/<feature>/<subdomain-b>/<worker>
    ├─ cell/<feature>/<review-fix>/<worker>
    └─ cell/<feature>/<qa>/<worker>
```

Subdomain PRs target **cell integration**, not `main`, when practical.

The final feature delivery targets the active **release train** branch.

This prevents every tiny patch from fighting directly with main.

## 9. No PR soup

Prefer:
- a few purposeful subdomain PRs;
- one cell integration branch;
- one feature delivery.

Avoid:
- one PR per tiny test/doc fix;
- repeated sync PRs for harmless main movement;
- multiple workers independently recovering the same conceptual feature;
- duplicate feature ownership.

PR count is not productivity.

## 10. Feature phases

Every feature moves through:

`DISCOVERY → CONTRACT → IMPLEMENTATION → ADVERSARIAL HARDENING → PRODUCT POLISH → LOCAL ACCEPTANCE → CELL INTEGRATION → TRAIN_READY → RELEASE TRAIN → INTEGRATED ACCEPTANCE → MERGED → POST-MERGE OBSERVATION`

Do not skip from implementation directly to done.

## 11. Definition of Perfection

A Feature Mission defines exact completion criteria. Applicable dimensions include:

**Functional** — intended behavior + edge/failure/recovery states.

**Truth** — no evidence promotion, stale/retained/estimated value masquerading as live measurement, or invented hardware semantics.

**API** — invalid states fail closed; serialization/import cannot bypass validation; provenance survives consumers.

**Test** — deterministic regressions, adversarial cases, race/concurrency tests where relevant.

**Product** — hierarchy, empty/loading/error/offline states, polished interaction, no developer theater.

**Accessibility** — VoiceOver, Dynamic Type, motion, contrast, assistive-control semantics.

**Performance** — no unnecessary high-frequency invalidation; profile hot paths where warranted.

**Integration** — app source visibility, dependency closure, project wiring when needed.

**Release** — focused cell evidence + integrated train evidence.

**Physical** — physical requirements remain explicitly pending if software cannot prove them.

## 12. Tiered acceptance — critical V11 throughput change

### Tier C — isolated package/domain
Examples: isolated NembraCore types, math/state machines, package-only evidence primitives, research/docs.

Before cell acceptance:
- focused SwiftPM compile/tests;
- deterministic/adversarial tests;
- independent review;
- API/truth boundary review.

**No mandatory full iPhone Simulator run for every isolated Tier-C microchange.**

### Tier B — app-visible/subsystem
Examples: Home, Dashboard, ride persistence, navigation, battery/range app path, Bluetooth transport.

Required:
- focused tests;
- independent review;
- cell integration proof;
- targeted Simulator proof when the coherent feature reaches LOCAL ACCEPTANCE.

Do not full-gate every small commit.

### Tier A — global/security/persistence/build
Examples: project.pbxproj, bootstrap/root composition, CI/security, global persistence migration, motorized authorization boundary.

Required:
- stronger review quorum;
- adversarial analysis;
- targeted exact-head gate before TRAIN_READY when warranted;
- integrated train gate again before merge.

## 13. Focused evidence survives harmless main drift

Classify main movement:

- **DRIFT 0 — docs/policy only:** focused feature evidence remains valid.
- **DRIFT 1 — unrelated isolated product paths:** evidence remains valid after overlap/dependency check.
- **DRIFT 2 — related dependency/API movement:** rerun affected focused tests/review.
- **DRIFT 3 — build graph/global/security/persistence movement:** re-gate affected cell integration.
- **DRIFT 4 — direct overlapping semantic movement:** reconcile + re-review + re-test.

Do not throw away a fully green isolated package result merely because `docs/SWARM_OPERATING_SYSTEM.md` changed.

Final release-train acceptance proves combined compatibility.

## 14. Release trains

Expensive app-wide acceptance happens on **release trains**.

Branch:
`train/<train-id>`

Example:

```text
Feature A: battery readout        ┐
Feature B: shell clearance        ├→ TRAIN-17 → ONE integrated Xcode gate → main
Feature C: rolling performance    ┤
Feature D: passive capture        ┘
```

Default train contains 2–5 compatible TRAIN_READY feature deliveries.

P0/safety/broken-main work may ship alone.

A larger train of 6–8 isolated compatible deliveries is allowed when conflict/debug risk remains low.

## 15. Train admission

A feature enters a train only when `TRAIN_ELIGIBILITY = READY`:
- owned paths frozen;
- cell review clean;
- focused tests green;
- Definition of Perfection reached except integrated/physical gates;
- dependencies current;
- source visibility understood;
- no unresolved high-severity defect.

Do not admit almost-done work merely to fill a train.

## 16. Integrated train gate

For an app-visible train:
- exact immutable train SHA;
- Xcode 27;
- iPhone 12 / iOS 27 Simulator;
- NembraCore/package tests;
- app tests;
- UI tests relevant to included features;
- required screenshots/videos/artifacts;
- artifact inspection;
- final main/train drift classification;
- expected-head protected merge.

One successful train can validate several ready features.

## 17. Train failures

On failure:
1. identify exact failing job/test;
2. map failure to responsible cell(s);
3. do not blind-rerun;
4. reproduce with focused test;
5. fix in the cell;
6. update train;
7. rerun once coherent.

If ambiguous, bisect/isolate train components. Keep main clean.

## 18. Release Commander

Owns:
- feature portfolio;
- cell creation/size/dissolution;
- WIP;
- train composition/order;
- drift classification;
- scarce Xcode scheduling;
- conflict arbitration;
- P0 bypasses;
- protocol migration.

Does not micromanage implementation.

## 19. CI / Build Sheriff

Owns:
- Xcode queue;
- trusted exact-head execution;
- build graph/source visibility;
- train gates;
- duplicate-run suppression;
- artifact retention;
- infrastructure failure classification;
- stale event/security guards.

Most full Xcode gates should be scheduled by the CI Sheriff/Release Commander, not every feature worker independently.

## 20. Feature Captain

Owns:
- feature contract;
- subdomain decomposition;
- integration branch;
- Definition of Perfection;
- defect list;
- mission issue;
- train readiness.

Captain does not self-approve acceptance.

## 21. Reviewer / red team

Reviewer reads actual source/diff and attacks:
- invalid states;
- corruption/import boundaries;
- concurrency/races;
- stale evidence;
- neighboring API contracts;
- truth/physical overclaims.

Do not merely restate builder notes.

## 22. Verifier / QA

Verifier checks:
- exact candidate SHA;
- actual test outputs;
- artifacts/screenshots;
- user-visible behavior;
- Definition of Perfection;
- difference among focused cell evidence, integrated train evidence, and physical-device evidence.

## 23. Product / visual specialist

For UI-heavy cells:
`Simulator → screenshot → critique → redesign → implement → interact → screenshot → profile → accessibility → fix → repeat`.

Do not call a UI feature complete from source alone.

## 24. Performance / accessibility specialist

Performance:
- high-frequency update fan-out;
- maps/telemetry;
- CPU/main thread;
- allocations/leaks;
- launch/transitions/long sessions.

Accessibility:
- VoiceOver;
- Dynamic Type;
- Reduce Motion;
- Reduce Transparency;
- Increase Contrast;
- Differentiate Without Color;
- Voice Control;
- Switch Control;
- touch targets.

## 25. ES80 / hardware specialist

Public-first. Exhaust reasonable public/official/source evidence before physical blocking.

No random motorized writes. `.write` characteristic metadata != permission. Subscription result != scooter command acknowledgement. Physical claims require physical evidence.

## 26. V10 long-shift runtime preserved

Workers still target long continuous shifts when the platform permits.

Loop:
`TARGETED EVIDENCE → SAME-FEATURE SLICE → VERIFY → DURABLE SAVE → NEXT SAME-FEATURE ACTION → TOOL`

No milestone final. No giant progress essay. No monolithic thinking phase.

If uncertain, perform a targeted evidence action.

Same failed tactic normally gets at most two meaningful attempts without new evidence.

Same unchanged external wait gets at most two consecutive polls; then do same-feature alternate work.

## 27. Same-feature shadow queue

Each worker maintains:

`ACTIVE`
`NEXT_1`
`NEXT_2`
`NEXT_3`
`SAME_FEATURE_REVIEW`
`SAME_FEATURE_TEST`
`SAME_FEATURE_PRODUCT_QA`
`SAME_FEATURE_PERF_AX`

When blocked, move within the feature. Do not escape to unrelated implementation.

## 28. Context economy

Prefer:
feature mission → exact PR → exact file/diff → exact failing log.

Avoid repeated repo-wide enumeration, full PR histories, giant logs, duplicate master prompt, and giant mid-run summaries.

Every ~5–7 useful slices do a tiny reanchor:
- main;
- cell integration head;
- own head;
- active defect;
- next action;
- train status.

Then immediately continue.

## 29. Control plane

Organization control issue:
`[SWARM CONTROL] Nembra Developer Team v11`

Feature state:
`[FEATURE CELL] <feature name>` issues.

Train state:
`[RELEASE TRAIN] <train-id>` issues.

Do not turn one global control issue into a giant micro-checkpoint log.

## 30. V10 → V11 migration

Existing V10 workers migrate **in place**.

Do not restart or throw away branches/tests/review evidence.

Migration:
1. retain current work;
2. map related current lanes into a Feature Cell;
3. group workers working on the same conceptual feature;
4. assign captain/reviewer/verifier and subdomain owners;
5. preserve current branches as subdomain branches when useful;
6. create cell integration branch;
7. stop independent full-Xcode requests unless Tier A or specifically warranted;
8. use tiered cell-local acceptance;
9. once perfected, mark TRAIN_READY;
10. Release Commander batches delivery into a release train.

Old v7/v8/v9/v10 evidence remains useful according to drift/risk rules; do not blindly rerun everything.

## 31. Duplicate recovery cleanup

When several PRs represent the same conceptual feature:
- choose the highest coherent current implementation;
- preserve historical branches;
- fold valid reviewed fixes into the Feature Cell;
- close/supersede duplicates after accepted successor exists;
- stop independent workers from repeatedly re-recovering the same thing.

One feature should converge toward one delivery.

## 32. Portfolio priority

P0 broken main / safety / truth regression
P1 parent blocking multiple cells
P2 high-value feature near perfection
P3 release-train blocker
P4 duplicate/recovery consolidation
P5 major product feature
P6 visual/performance/accessibility completion
P7 ES80 public-first research/passive tooling
P8 docs/audits only when they unblock implementation/acceptance

Prefer finished features over more started features.

## 33. Cell dissolution

Feature Cell remains alive through merge and post-merge observation.

Only after accepted merge:
- verify main;
- close/supersede historical duplicates;
- record remaining physical gates;
- release FEATURE_LOCK;
- then join/create another Feature Cell.

## 34. Success metrics

Do NOT optimize commits/hour, PR count, comments/hour, number of busy agents, or Xcode run count.

Optimize:
- perfected user-visible features merged;
- blockers eliminated;
- feature lead time;
- defects caught before main;
- low duplicate work;
- low Xcode runs per merged feature;
- train success rate;
- real user-visible product progress.

Useful metrics:
`FEATURES_PER_TRAIN`
`XCODE_RUNS_PER_MERGED_FEATURE`
`MEAN_FEATURE_LEAD_TIME`
`DEFECTS_CAUGHT_PRE_MAIN`
`DUPLICATE_PR_COUNT`
`TRAIN_FAILURE_RATE`
`PHYSICAL_GATES_OPEN`
`USER_VISIBLE_PROGRESS`

## 35. Fresh-worker startup

1. inspect current main;
2. read current protocol;
3. read newest v11 global directive;
4. inspect active Feature Missions;
5. **do not automatically create a new feature**;
6. join the highest-value cell needing your skill;
7. generate worker/session identity;
8. claim one subdomain/review/verifier role;
9. read only feature-relevant source;
10. begin work immediately;
11. keep working the same feature until perfection/train/merge;
12. release feature lock only after accepted completion.

## 36. Final gate

FINAL is not normal.

Final response is permitted only when:
- user explicitly requested status-only;
- user-only physical/external action is required and no same-feature useful work remains;
- continuing is unsafe;
- all same-feature implementation/review/test/product/performance/accessibility work is exhausted;
- outer platform ends the turn.

Commit, PR, test, review, local gate, train admission, train green, merge, or one subtask completion do not imply final.

## 37. V11 design thesis

**V10:** make each chat work longer.

**V11:** make many long-running chats behave like a high-end software organization.

The goal is not maximum parallel feature count.

The goal is:

`MANY STRONG AGENTS`
→ `FEW HIGH-VALUE ELASTIC FEATURE CELLS`
→ `DEEP PARALLEL WORK INSIDE EACH FEATURE`
→ `FEATURE PERFECTION`
→ `BATCHED RELEASE TRAINS`
→ `MINIMUM EXPENSIVE GATES`
→ `FAST SAFE MAIN`
→ `VISIBLE PRODUCT PROGRESS`.
