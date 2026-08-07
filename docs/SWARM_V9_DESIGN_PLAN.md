# NEMBRA SWARM v9 — LONG-HORIZON ENGINEERING MESH

STATUS: **DESIGN / NOT ACTIVE**

This document plans the next generation after v8. It is intentionally not current operating policy until a later explicit protocol migration lands on `main`.

## 0. Goal

Turn many strong reasoning/coding chats into a coherent senior engineering organization that keeps useful work moving for as long as the platform permits, minimizes voluntary premature final answers, and makes any individual session cheap to replace.

No prompt can guarantee that one standard Chat session stays alive for hours. No repository policy can override an outer platform runtime, resource cap, or forced termination. V9 therefore has two separate goals:

1. aggressively eliminate worker-controlled premature stopping;
2. make externally terminated workers almost disposable.

Desired behavior: **work-until-no-safe-work-or-platform-kill**, not “promise an immortal chat.”

## 1. Model / reasoning quality

Use v9 with the strongest coding/reasoning configuration available to the user. High-effort reasoning is preferred for architect, integration, security, persistence, CI, and critical-review roles when the product exposes such a setting.

The prompt itself cannot force an unavailable model, hidden reasoning mode, or product tier. Workers must never pretend otherwise.

## 2. Organization upgrade

V8 provides self-healing workers and quota-independent degraded modes.

V9 adds:
- explicit long-horizon session controller;
- hard work-in-progress governance;
- builder/reviewer/verifier separation;
- release-train ownership;
- long-session context-pressure management;
- shadow-work queues so external waits do not become final answers;
- packet-sequence resume pointers;
- role-specialized staffing for 10–20 concurrent chats;
- organization-level throughput optimization instead of “every chat opens a PR.”

Target organization resembles:
- Chief Architect / Release Commander
- Build / CI / DevEx
- Domain Feature Squads
- Product / SwiftUI Design
- Navigation
- ES80 / Bluetooth Research
- Performance
- Accessibility / Interaction
- Verification / Artifact QA
- Adversarial / Truth Review
- Recovery / Triage

## 3. Suggested staffing at 12–16 concurrent chats

- 1 Chief Architect / Release Commander
- 1 Build / CI / DevEx engineer
- 3–4 domain builders: battery/range, rides/history/location, navigation, ES80/Bluetooth
- 2 product/visual builders: Home/Dashboard/live ride/navigation/history
- 2 independent reviewers/red-team engineers
- 1 performance engineer
- 1 accessibility/interaction engineer
- 1 recovery/triage engineer

Extra chats beyond useful implementation capacity become reviewers, test designers, research workers, artifact inspectors, dependency unblockers, or recovery workers. They do **not** create random features merely to remain busy.

## 4. Hard WIP governor

Default target:

`MAX_ACTIVE_IMPLEMENTATION_LANES = 7`

Fifteen chats must not create fifteen implementation PRs.

When implementation WIP reaches the cap, incoming workers must prefer review, verification, test hardening, research, stale recovery, or merge preparation.

When the repository already has many open active code PRs, use a default arrival policy of roughly:
- 70% close/recover/review existing WIP;
- <=30% start genuinely new implementation.

The desired metric is not “PRs created per hour.” It is **validated useful work merged and blockers removed per hour**.

## 5. Builder / Reviewer / Verifier triads

Critical work separates responsibilities.

### Builder
- owns source changes;
- writes focused tests;
- keeps exact durable worker state;
- never self-declares final acceptance merely because its own tests passed.

### Reviewer
- owns no builder files unless ownership transfers;
- reads exact source/diff;
- attacks semantics, API boundaries, concurrency, persistence, corruption, security, and truth claims;
- produces exact-head findings.

### Verifier
- inspects exact-head CI, jobs, artifacts, screenshots, runtime evidence, and final SHA;
- checks that the stated acceptance claim matches the actual evidence.

Class A / safety-critical work should prefer one builder + two independent reviewers + verifier when practical.

Automated Codex Code Review remains optional and non-gating.

## 6. Long-horizon session state machine

Every v9 worker conceptually runs:

`BOOT → CLAIMED → WORKING → CHECKPOINTING → WORKING → ... → ACCEPTANCE → RELEASE → NEXT_LANE → WORKING`

If an external service blocks the immediate next action:

`WORKING → WAITING_ON_SERVICE → SHADOW_WORK → WORKING`

**FINAL RESPONSE IS NOT A NORMAL STATE.**

Final is permitted only from:
- `HARD_BLOCKED`
- `NO_SAFE_WORK`
- `USER_INPUT_REQUIRED`
- external platform termination

A commit, push, PR, merge, test run, screenshot, review, CI start, CI queue, phase completion, or one finished packet never transitions the worker to final by itself.

## 7. No ceremonial final rule

V9 explicitly forbids the failure mode:

> “I finished this checkpoint. Here’s what I did...”

followed by a final response while useful work still exists.

Short commentary between tool calls is fine when useful, but commentary must not replace the next tool action.

Before final-answering, the worker must evaluate:
1. current state;
2. current `PRIMARY_NEXT`;
3. whether `PRIMARY_NEXT` can safely be executed now;
4. whether any shadow or team work is available.

If a safe useful action exists, **perform it instead of final-answering**.

Progress/status summaries are produced when the user explicitly asks for status or when a legitimate stop condition is reached.

## 8. Long-session work cadence

Use repeating macrocycles.

### Macrocycle
1. 1–3 targeted reads;
2. one coherent implementation/research objective;
3. focused verification;
4. durable push/checkpoint;
5. update tiny state block;
6. select next packet immediately.

Target atomic packet: roughly **5–12 minutes**.

Target macrocycle: **2–4 packets before a targeted context refresh**.

Avoid:
- giant 30-minute orientation phases;
- repeated full-repo searches;
- giant narration;
- constant control-plane comments;
- rereading the whole master prompt repeatedly;
- busy polling;
- keeping large uncheckpointed source changes only in chat context.

This does not guarantee long platform runtime, but it reduces context pressure and voluntary stop triggers while continuously creating durable progress.

## 9. Shadow-work queue

Each worker keeps 2–3 safe same-lane fallback tasks.

Example:

`PRIMARY_NEXT: fix exact failing test`

`SHADOW_1: inspect neighboring consumer contract for same bug family`

`SHADOW_2: add deterministic adversarial regression`

`SHADOW_3: inspect current exact-head artifact/screenshots`

If CI, runner, reviewer, or another service blocks `PRIMARY_NEXT`, the worker takes shadow work instead of final-answering.

If same-lane shadow work is exhausted, it may perform read-only peer review or verification for another lane without stealing implementation ownership.

## 10. Context-pressure governor

Long sessions fail cognitively when too much stale duplicated context is carried in chat.

V9 workers should:
- keep canonical state in GitHub, not conversation memory;
- reload only changed facts after merges/dependency movement;
- use exact PR worker state as working memory;
- summarize long logs into durable findings;
- keep `PRIMARY_NEXT` and shadow tasks concise;
- prefer exact file/symbol/log reads over broad repository scans;
- avoid rereading the OS every packet.

Every ~4 macrocycles, or after major main/parent movement, perform a small context refresh:
1. fresh main SHA;
2. current lane head;
3. parent/base;
4. newest relevant PR state;
5. service states;
6. next three actions.

Do not reload historical detail unless the current decision requires it.

## 11. V9 worker state

```text
### V9 WORKER STATE
PROTOCOL_VERSION: 9
WORKER_ID:
SESSION_ID:
ROLE:
LANE_ID:
EPOCH:
CURRENT_HEAD:
BASE_OR_PARENT:
OWNED_PATHS:
RISK_CLASS:
LAST_PACKET_SEQ:
LAST_PACKET_RESULT:
PRIMARY_NEXT:
SHADOW_1:
SHADOW_2:
SHADOW_3:
LAST_DURABLE_PACKET:
LAST_KNOWN_GREEN:
PEER_REVIEW:
VERIFICATION:
SERVICE_STATES:
DEPENDENCIES:
KNOWN_OVERLAP:
HARD_BLOCKER:
HANDOFF_READY:
```

## 12. Packet sequence / resume pointer

Every durable packet has a monotonic `PACKET_SEQ`.

PR body records:

```text
LAST_PACKET_SEQ: 17
LAST_PACKET_RESULT: ...
NEXT_PACKET_SEQ: 18
NEXT_EXACT_ACTION: ...
```

If a chat dies, a successor does not need its conversation. It needs:
- lane;
- epoch;
- exact head;
- packet sequence;
- next exact action;
- dependencies/service state.

This is how a replacement chat behaves like the same engineer continuing the job.

## 13. Lease / death detection

Do not recover merely because a chat is quiet.

Suggested defaults:
- ACTIVE: durable movement in normal microburst window, active CI, or explicit long operation;
- QUIET: ~15–25 minutes;
- SUSPECTED DEAD: ~25–35 minutes;
- RECOVERABLE: ~35+ minutes for ordinary lanes;
- Class A: prefer ~45+ minutes or coordinator decision.

Takeover increments `EPOCH` and creates a new recovery branch.
Returning lower epoch yields.

V9 additionally records predecessor `SESSION_ID` and `LAST_PACKET_SEQ` so takeover provenance is exact.

## 14. Service-outage router

Every unavailable service maps to alternative productive work.

- Automated review quota → peer review / verifier
- Xcode queue → shadow work / review / test hardening / artifact inspection
- GitHub API throttle → targeted reads, reduced query cadence, local/focused work
- GitHub write failure → at most one small reconstructable local packet, then read-only work
- Web unavailable → repository/source work
- Simulator unavailable → code/tests/review; runtime acceptance stays pending
- Physical ES80 unavailable → public-first research, capture tooling, UI, navigation, software truth work

No single service outage collapses the whole organization into waiting.

## 15. Review quorum

Suggested default:

### Class C isolated
- one independent reviewer

### Class B subsystem
- one strong independent reviewer
- verifier on exact acceptance

### Class B cross-domain
- two independent reviewers where feasible
- verifier

### Class A / persistence / CI security / motorized-write boundary
- two independent reviewers
- one adversarial/red-team pass
- verifier
- exact-head acceptance
- official platform/security references where relevant

This avoids dependence on limited automated review services.

## 16. Release train

Chief Architect / Release Commander classifies active work:
- `READY`
- `NEXT`
- `WAITING_PARENT`
- `WAITING_ACCEPTANCE`
- `HARDWARE_GATED`
- `SUPERSEDED`

New workers prioritize:
1. unblock a READY parent;
2. close an exact acceptance issue;
3. recover stale near-ready work;
4. merge verified work;
5. only then create new implementation.

The organization should reduce unresolved WIP over time rather than endlessly grow the PR graph.

## 17. Post-merge autonomy

After merge:
1. release current lane;
2. refresh main;
3. inspect team/release train;
4. select the highest-value safe next role/lane;
5. claim it;
6. continue working.

Do not final-answer “PR merged successfully” while another safe useful action is available.

## 18. Product-quality organization

V9 preserves the full Nembra product constitution.

Systems engineering is not equivalent to finished product. Completion still requires:
- trustworthy real ES80 integration;
- accepted battery/range live path;
- navigation/live ride integration;
- the large production visual overhaul;
- performance/accessibility acceptance;
- required physical verification.

As domain foundations land, staffing should deliberately move toward product/visual/performance/accessibility rather than leaving them as late polish.

## 19. Senior-engineer behavior contract

Every worker should behave like a strong senior/staff engineer:
- skeptical of its own assumptions;
- reads actual code;
- tests edge cases;
- never invents evidence;
- surfaces uncertainty clearly;
- avoids scope creep;
- protects ownership boundaries;
- measures performance instead of guessing;
- uses current official platform docs for risky APIs/security;
- reviews before claiming completion;
- leaves a precise continuation pointer;
- optimizes team throughput, not personal PR size.

## 20. What V9 cannot promise

V9 cannot guarantee:
- one standard Chat stays alive for hours;
- a particular hidden model/reasoning configuration;
- unlimited API/CI/tool quotas;
- background execution after the platform ends the run.

It can be engineered to make:
- voluntary premature stops rare;
- context exhaustion less likely;
- waiting time productive;
- replacement seamless;
- 10–20 chats behave more like one coordinated engineering organization;
- the organization continue for hours/days even when individuals die.

## 21. Activation criteria

Do not activate V9 until:
1. V8 has demonstrated workers continue through automated-review quota exhaustion;
2. the v8 control plane remains manageable;
3. current workers can migrate in place;
4. V9 bootloader + final OS are complete;
5. migration directive is ready;
6. WIP governor and reviewer/verifier roles are explicit;
7. no active Class-A lane would be disrupted.

Activation sequence later:
- merge final v9 OS to `main`;
- create v9 control issue;
- publish global migration directive to v8 issue;
- existing workers preserve branches and migrate at next safe checkpoint;
- only new chats need the v9 bootloader.

## 22. Main thesis

**Do not try to make one chat immortal.**

Make each chat:
- reluctant to voluntarily stop;
- cheap to replace;
- specialized;
- stateful through GitHub;
- equipped with alternate work;
- aware of its role in the whole organization.

Then make the **organization** effectively continuous.
