# CAPTURE HARD FREEZE — FASTEST PATH TO FIRST ES80 ARTIFACT

This file is the active coordination lock for the one-time Nembra Capture utility.

It records live closure state only. It does **not** authorize hardware, and documentation movement after acceptance must not mutate or redefine the frozen application source candidate.

## Current frozen Capture subject

- Flagship PR: **#833**
- exact frozen product head: `a0f4a33451f61411d6e0541f2e70edea5438342d`
- product gate: **EXACT APP/RUNTIME + RETAINED VISUAL ACCEPTED — KEEP FROZEN**
- trusted owner-command gate: **ACCEPTED**
- accepted trusted owner-command run: `31312741465`
- trusted workflow source commit: `66eda3a736ea56523f6c3c1c0470c2011eca2f51`
- trusted workflow Git blob: `34a1b6af852f0d31a8fb7488f816bc34c985678e`
- physical status: **NO-GO / DO NOT SCAN / DO NOT RUN EXPERIMENT ONE**

Current default branch at this coordination refresh was `main@ef8811a5d2df782f5830c1ff299c4272468dba0b`. Main may continue moving for disjoint product work; that does not change the frozen Capture product subject above.

## Accepted trusted software gate

GitHub Actions run `31312741465` (`Capture Trusted Xcode 27 Exact-Head QA`) is terminal **SUCCESS**, attempt 1.

The exact jobs are terminal success:

- resolver `93242986211` — **SUCCESS**;
- isolated prevalidation `93243000285` — **SUCCESS**;
- trusted Mac authority `93243212531` — **SUCCESS**.

The trusted Mac job completed immutable exact-head checkout/verification, trusted Simulator evidence-producer custody, trusted build-graph custody, real Xcode build/test/Simulator capture, retained Capture evidence verification, trusted artifact upload, and final head-movement rejection.

The retained trusted artifact is:

- artifact ID `9038098282`;
- name `nembra-capture-xcode27-833-641-1`;
- size `36,021,665` bytes;
- GitHub digest `sha256:f128a9bd05b2ceff7be47addce103028d7bc6982ede17ad0bc8894983e826e72`.

This is accepted **software/Simulator evidence only**. It is not a signed intended-device field candidate and is not physical ES80 authorization.

## What is no longer a blocker

Do not keep treating the following as pending:

- another ordinary exact-head Xcode run for unchanged `a0f4a334…`;
- another trusted `/capture-xcode27` run for unchanged `a0f4a334…` merely to accumulate evidence;
- more Simulator screenshots solely to re-prove the already accepted retained Capture matrix;
- speculative post-capture hardening that would move the frozen product subject without a demonstrated TODAY blocker.

Queued, skipped, cancelled, stale-SHA, package-only, and unrelated descendant evidence still do not count. The accepted trusted run above is the current software gate.

## Prime rule

**KEEP `#833@a0f4a33451f61411d6e0541f2e70edea5438342d` FROZEN.**

Move the frozen Capture product only if a newly demonstrated normal-path TODAY blocker proves that exact subject cannot safely produce the first intended artifact. Examples include build/install/launch failure on the retained field candidate, Capture crash/hang/corruption/mis-target/export failure, an application characteristic-write authority regression, Stationary/Charger Disconnected bypass, a false software acceptance, signed intended-device installation failure, missing package-owned private-research runtime provenance, or inability to deliberately authorize the exact Research Field Build.

Do not move it for cosmetics, duplicate validation, branch hygiene, speculative security work, documentation-only cleanup, or unrelated product improvements.

## Current P0 blocker — private signed intended-device field candidate

The next legal rung is **not another GitHub/Simulator run**. It requires a private macOS/Xcode 27 signing surface plus the intended iPhone.

Required sequence:

1. Keep exact source `a0f4a33451f61411d6e0541f2e70edea5438342d` unchanged.
2. On the private signing surface, run `scripts/ci/xcode27_today_research_field_candidate.sh` with the accepted private Apple Team, export-options, and intended-device inputs.
3. Produce one immutable retained `inspection/build-evidence/NembraField.ipa`.
4. Independently inspect exact signing/provisioning/team/application identity, intended-device authorization, source/build/build-instance/recipe, executable SHA-256, raw Info.plist SHA-256, and IPA SHA-256.
5. Run the pinned independent retained-candidate cross-check required by `docs/ES80_TODAY_EXACT_RETAINED_IPA_INSTALL.md`. `PASS_NOT_FINAL_GO` remains non-authorizing.
6. SHA-256 the exact retained IPA before installation.
7. Install **that same retained IPA** on the intended iPhone 12 / iOS 27 through Xcode device management without rebuild/re-export/substitution.
8. Launch Nembra from the Home Screen and require package-owned `PRIVATE RESEARCH BUILD / Runtime provenance ready` plus an exact source/build/build-instance/recipe rendezvous with retained evidence.
9. SHA-256 the original retained IPA again and require exact equality.
10. Complete the external TODAY Final GO Record from independently checked retained/install/runtime evidence.
11. Only then may one stationary, charger-disconnected, passive/read-only `ES80-FINGERPRINT-v1` Experiment One become eligible.

Never place the raw intended-device UDID in GitHub comments, public command arguments, artifact names, screenshots, or public durable notes.

## Physical Experiment One remains NO-GO

Until the signed intended-device ladder above is complete, do **not** scan or run the experiment.

When Final GO is eventually earned, Experiment One remains deliberately narrow:

- scooter stationary for the entire procedure;
- charger disconnected;
- deterministic OFF1 → ON1 → OFF2 → ON2 target correlation;
- explicit correlated-target confirmation;
- passive GATT only;
- no random characteristic writes or speculative commands;
- minimum accepted 60-second observation horizon after Ready;
- exact Horizon/seal/integrity path;
- preserve the raw Share artifact unchanged.

The first artifact does not establish battery, voltage, current, watts, speed, throttle, regen, command acknowledgement, rated maximum, or production telemetry semantics.

## Durable handoff

Authoritative field procedure details remain in:

- `CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md`;
- `docs/ES80_TODAY_PRIVATE_FIELD_RUNBOOK.md`;
- `docs/ES80_TODAY_EXACT_RETAINED_IPA_INSTALL.md`;
- `docs/ES80_TODAY_FINAL_GO_OPERATOR_ATTESTATION.md`.

If those documents still describe terminal software acceptance as pending, treat that wording as stale relative to the accepted gate recorded here and live #833 state. Do not silently promote any still-missing signed-field/install/runtime evidence.

## Current disposition

**SOFTWARE OWNER-COMMAND GATE: ACCEPTED.**

**FROZEN PRODUCT: `#833@a0f4a33451f61411d6e0541f2e70edea5438342d`.**

**SIGNED INTENDED-DEVICE FIELD CANDIDATE: NOT YET PRODUCED/VERIFIED HERE.**

**FIRST REAL ES80 ARTIFACT: NOT YET COLLECTED.**

**PHYSICAL ES80 EXPERIMENT ONE: NO-GO / DO NOT SCAN / DO NOT RUN.**
