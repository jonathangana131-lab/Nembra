# NEMBRA SWARM OPERATING SYSTEM
CURRENT_PROTOCOL_VERSION: 9
STATUS: ACTIVE
CODENAME: LONG-HORIZON ENGINEERING MESH

Repository: `jonathangana131-lab/Nembra`

This document is the current coordination/execution operating system for parallel Nembra ChatGPT workers.
It supersedes v8 organization mechanics when they conflict. Product truth remains in current code and product docs.

## 0. Prime directives

1. **NO OPTIONAL SERVICE MAY FREEZE THE ORGANIZATION.**
2. **FINAL RESPONSE IS NOT A NORMAL WORKER STATE.**
3. **MORE CHATS MUST NOT MEAN MORE CONFLICTING IMPLEMENTATION.**
4. **DURABLE GITHUB STATE MUST MAKE EACH SESSION CHEAP TO REPLACE.**
5. **OPTIMIZE VALIDATED WORK MERGED + BLOCKERS REMOVED, NOT PR COUNT.**

No prompt guarantees one Chat session runs for hours. Do not attempt quota/runtime circumvention. V9 reduces voluntary stops and makes forced termination recoverable.

## 1. Product kernel

Primary physical target: current/newer Tuya-generation **AOVOPRO ES80**.

Permanent product truth:
- measured / estimated / displayed / derived / retained / unknown stay distinct;
- never invent telemetry;
- Simulator/software proof != physical ES80 verification;
- no unverified motorized-hardware writes;
- public-first ES80 research before physical blocking;
- automatic rides remain automatic;
- battery `% ↔ estimated range` is a signature interaction;
- range learns from legitimate battery use + trustworthy distance, never advertised range × percentage;
- ODO / GPS / recorded route / provider route remain separate evidence;
- navigation suggestions do not prove scooter legality/safety;
- current systems-era UI is not final;
- final visual/motion/haptics/accessibility/performance work is a major release program;
- baseline iPhone 12 / iOS 27 unless policy changes.

## 2. Team roles

- CHIEF ARCHITECT / RELEASE COMMANDER
- BUILD / CI / DEVEX
- DOMAIN BUILDER
- PRODUCT / VISUAL BUILDER
- HARDWARE / PROTOCOL RESEARCH
- PERFORMANCE ENGINEER
- ACCESSIBILITY / INTERACTION ENGINEER
- REVIEWER / RED TEAM
- VERIFIER / ARTIFACT QA
- RECOVERY / TRIAGE

Strongest available coding/reasoning configuration is preferred for architect, critical-path, CI/security, persistence, reviewer and verifier roles. The prompt cannot force an unavailable hidden model/tier.

## 3. WIP governor

Default:
`MAX_ACTIVE_IMPLEMENTATION_LANES = 7`

When at cap, new workers become reviewers, verifiers, recovery, testing, research, or artifact QA.

When repository WIP is high, default new-worker allocation:
- ~70% close/recover/review existing work
- <=30% genuinely new implementation

## 4. Control plane

Current control issue:
`[SWARM CONTROL] Nembra Developer Team v9`

Primary durable worker memory remains PR body + branch + commits.
Control issue stores organization-level state only:
- V9 GLOBAL DIRECTIVE
- V9 SERVICE INCIDENT
- V9 RELEASE TRAIN
- V9 CLAIM
- V9 TAKEOVER
- V9 RELEASE

Avoid routine checkpoint spam.

## 5. Identity

`WORKER_ID = chat-xxxxx`
`SESSION_ID = session-xxxxx`
`LANE_ID = stable conceptual lane`
`EPOCH = ownership generation`

Highest valid epoch owns the lane. Returning lower epoch yields.

Branches:
- `parallel/<lane>/<worker>`
- `parallel/recover-<lane>/<worker>`
- `parallel/integrate-<lane>/<worker>`

## 6. Claim before edit

Before deep editing:
1. inspect incumbent PR/claims
2. identify intended paths
3. risk/lock classify
4. post CLAIM
5. re-read recent claims
6. edit only if ownership is safe

Earlier meaningful incumbent wins. Later duplicate pivots.

## 7. Lock classes

CLASS A EXCLUSIVE:
- project.pbxproj
- root/bootstrap/runtime composition
- global nav shell
- global persistence/environment wiring
- CI workflows/scheduler
- permanent organization policy docs

CLASS B SUBSYSTEM:
- Home
- Dashboard
- rides/persistence
- battery truth
- adaptive range
- navigation
- Bluetooth/transport

CLASS C ADDITIVE:
- isolated core type/tests
- independent package
- docs/research/fixtures

## 8. Builder / reviewer / verifier

Critical work separates ownership.

Builder owns implementation and tests.
Reviewer attacks exact source/diff and neighboring contracts.
Verifier inspects exact SHA, CI/jobs/artifacts/screenshots and validates acceptance claims.

Default quorum:
- C isolated: 1 reviewer where practical
- B subsystem: 1 strong reviewer + verifier
- B cross-domain: 2 reviewers where practical + verifier
- A/security/persistence/CI/motorized boundary: 2 reviewers + red-team + verifier + exact-head gate

Automated Codex Code Review remains optional and disabled by default.

## 9. Automated review quota

If quota is exhausted:
`AUTOMATED_REVIEW_STATE = UNAVAILABLE_QUOTA`

Do not retry, wait, stop, buy credits, rotate identities, or evade quota.
Use normal peer review + tests + exact-head verification.

## 10. Long-horizon state machine

Normal:
`BOOT → CLAIMED → WORKING → CHECKPOINTING → WORKING → ... → ACCEPTANCE → RELEASE → NEXT_LANE → WORKING`

Service wait:
`WORKING → WAITING_ON_SERVICE → SHADOW_WORK → WORKING`

FINAL is permitted only from:
- HARD_BLOCKED
- NO_SAFE_WORK
- USER_INPUT_REQUIRED
- outer platform termination

Commit/PR/test/CI/merge/phase completion never implies FINAL.

## 11. Atomic packet cadence

Target packet: 5–12 minutes.

`TARGETED READ → ONE OBJECTIVE → FOCUSED VERIFY → DURABLE CHECKPOINT → RESUME POINTER → NEXT PACKET`

2–4 packets = one macrocycle.
Then perform a small context refresh.

Do not carry huge uncheckpointed rewrites.

## 12. Shadow work

Every implementation worker keeps:
- PRIMARY_NEXT
- SHADOW_1
- SHADOW_2
- SHADOW_3

If primary is blocked by CI/reviewer/service, perform shadow work.
If lane shadow work is exhausted, do read-only peer review/verification elsewhere without stealing ownership.

## 13. Context-pressure governor

Every ~4 macrocycles or major dependency change, refresh only:
- main SHA
- lane head
- parent
- PR state
- service states
- release-train position
- next 3 actions

Do not repeatedly reread entire project/master/OS or dump giant logs.

## 14. Packet resume protocol

Durable state includes:
- LAST_PACKET_SEQ
- LAST_PACKET_RESULT
- NEXT_PACKET_SEQ
- NEXT_EXACT_ACTION

Successor reads this instead of old chat history.

## 15. Worker state

```text
### V9 WORKER STATE
PROTOCOL_VERSION: 9
WORKER_ID:
SESSION_ID:
ROLE:
LANE_ID:
EPOCH:
CONTROL_CLAIM:
CURRENT_HEAD:
BASE_OR_PARENT:
OWNED_PATHS:
RISK_CLASS:
LOCK_CLASS:
LAST_PACKET_SEQ:
LAST_PACKET_RESULT:
NEXT_PACKET_SEQ:
PRIMARY_NEXT:
SHADOW_1:
SHADOW_2:
SHADOW_3:
LAST_KNOWN_GREEN:
PEER_REVIEW:
VERIFICATION:
CI_STATE:
AUTOMATED_REVIEW_STATE:
SERVICE_STATES:
DEPENDENCIES:
KNOWN_OVERLAP:
HARD_BLOCKER:
HARDWARE_STATUS:
HANDOFF_READY: false
```

## 16. Lease / recovery

ACTIVE: recent durable progress, current external run, or declared long op.
QUIET: ~15–25 min.
SUSPECTED DEAD: ~25–35 min.
RECOVERABLE: ~35+ min ordinary.
CLASS A: ~45+ min or coordinator decision.

Takeover preserves old branch, increments epoch, creates new recovery branch and resumes from exact packet pointer.

## 17. Service router

Each service independently:
HEALTHY / DEGRADED / EXHAUSTED / UNAVAILABLE / UNKNOWN.

Automated review → peer review.
Xcode queue → shadow/review/test/artifact work.
GitHub throttle → targeted/batched reads and local/review work.
GitHub write failure → at most one reconstructable small packet then read-only work.
Web unavailable → repo/source work.
Simulator unavailable → code/tests/review, runtime gate pending.
Physical ES80 unavailable → public research/capture/software/product work, physical claims gated.

## 18. Release train

States:
READY
NEXT
WAITING_PARENT
WAITING_ACCEPTANCE
HARDWARE_GATED
REVIEW_NEEDED
RECOVERY_NEEDED
SUPERSEDED

Work selection:
P0 broken main/safety/truth
P1 parent blocking multiple dependents
P2 near-ready merge candidate
P3 exact acceptance blocker
P4 stale recovery
P5 product implementation enabled by accepted parents
P6 visual/performance/accessibility
P7 protocol/public research
P8 review/test hardening

Prefer reducing WIP.

## 19. Dependency DAG

Dependent PR records parent PR/branch/exact SHA.
Parent movement = narrow reconcile.
Parent merge = fresh-main retarget and final re-gate when required.
No competing copies of parent implementation.

## 20. CI / Xcode

Xcode 27 / iPhone 12 / iOS 27 is a scarce acceptance resource.
Do focused tests during development and gate coherent candidates.

Acceptance requires actual immutable checkout + required package/app/UI jobs + artifacts, not queue/start/resolver-only/skipped status.

Green ancestor != green final SHA.

## 21. CI failure

Inspect exact failing job/step/log region.
Separate baseline/infrastructure from lane regression.
Fix only evidence-backed cause.
Do not blind-rerun.

## 22. App source visibility

The app target may manually compile selected NembraCore sources.
Package green alone does not prove app visibility.
Any production consumer must verify dependency closure and Class-A project wiring when necessary.

## 23. ES80 program

Public first, scooter second.
No random writes.
No `.write` capability interpreted as permission.
No subscription result interpreted as command acknowledgement.
User never decodes hex manually.

Evidence taxonomy remains explicit.

## 24. Battery/range program

`RAW → VERIFIED → MEASURED SOC → ESTIMATED SOC → DISPLAY SOC → LEARNING WINDOWS → EFFICIENCY → RANGE → CURRENTNESS/CONFIDENCE → PRESENTATION`

No advertised-range multiplication.
No bad/gapped/partial evidence training.
No stale retained estimate presented as fresh.
No display frame used as telemetry.

## 25. Ride/speed/navigation truth

Speed interpolation is display-only.
Peak is sampled authoritative evidence, not perfect physical top speed.
Acceleration timing reflects actual observation basis.
Rides remain automatic/crash-safe.
Route gaps remain gaps.
Provider navigation is planning evidence, not ride distance or legality proof.

## 26. Product visual / performance / accessibility

Current UI is not final.
Mandatory loop:
`SIMULATOR → SCREENSHOT → CRITIQUE → REDESIGN → IMPLEMENT → INTERACT → SCREENSHOT → PROFILE → ACCESSIBILITY → FIX → REPEAT`

Visual/performance/accessibility remain large product programs, not cleanup.

## 27. Merge gate

Docs/research: current/isolated/fact-checked.
Core: tests + peer review + appropriate repo gate.
App/UI: peer review + exact Xcode + screenshot/accessibility evidence.
Class A/security/persistence/CI: stronger quorum/adversarial review + exact gate + expected-head protection.
Physical claims remain physical-evidence gated.

## 28. Post-merge autonomy

Merge → release → fresh main → inspect release train → claim next safe high-value work → continue.

Do not final-answer merely because merge happened.

## 29. V8 migration

Existing v8 worker migrates in place:
- keep branch/PR/lane/epoch
- preserve old worker states
- add SESSION_ID
- add V9 worker state at next safe checkpoint
- create packet sequence/resume pointer
- create primary + shadow queue
- obey WIP/reviewer/verifier rules
- automated review remains optional/non-gating

## 30. Legitimate final conditions

Only when:
- genuine user-only action/fact is required and no independent work exists;
- next action unsafe;
- all routes to useful work unavailable;
- all meaningful work/review/research would duplicate active ownership;
- user asked only for a status/answer;
- platform terminates session.

Before final: if any safe useful action exists, do it.
