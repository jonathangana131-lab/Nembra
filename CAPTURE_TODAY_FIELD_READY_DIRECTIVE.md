# Nembra V14 — TODAY FIELD-READY CAPTURE DIRECTIVE

Status: ACTIVE until the first successful stationary passive ES80 capture artifact is collected.

## 0. Objective

The immediate milestone is no longer “make Capture maximally hardened against every theoretical hostile-host/filesystem edge case.”

The immediate milestone is:

**TODAY: produce one safe, installable, stationary, READ-ONLY Nembra Capture build that can collect the first real AOVOPRO ES80 evidence artifact, verify/export that artifact, and unlock the next Nembra development phase.**

After the first real artifact exists, analyze it and resume the full release-grade hardening backlog in parallel with actual Nembra feature development.

This directive changes closure priority, not truth. Never fabricate hardware evidence, never add characteristic writes, and never bypass the stationary/charger/read-only safety boundary.

---

## 1. Scope freeze now

Freeze new Capture feature work.

Until the first real artifact is collected, a newly found issue may block TODAY only if it can plausibly cause one of these on the intended trusted developer phone/build:

1. app does not build/install/launch;
2. Capture can crash/hang/corrupt its own run on the normal path;
3. target correlation can select the wrong scooter or become ambiguous without failing closed;
4. any application characteristic write/command can occur;
5. charger/stationary/preflight safety can be bypassed accidentally;
6. the generated capture bytes can be wrong, incomplete, silently mutable inside the normal app flow, or impossible to export/analyze;
7. the exact final build cannot receive a real terminal trusted Xcode 27 acceptance run;
8. the exact signed developer/research build cannot be installed on the intended iPhone;
9. the field gate/runbook cannot deliberately authorize that exact safe developer research build.

Everything else is POST-CAPTURE BACKLOG unless it is demonstrated to affect one of those nine conditions on the intended environment.

---

## 2. Explicitly defer noncritical last-mile work

Do not keep moving the flagship head before first capture for purely release-grade or adversarial-host hardening such as:

- same-UID/symlink/path-retargeting attacks that require a hostile local process outside the normal Nembra flow;
- deep directory/inode publication custody beyond what is required for normal trusted-device artifact correctness;
- duplicate-key/parser-precedence attacks against JSON that Nembra itself deterministically generates, unless a normal app path can emit ambiguous bytes;
- offline-analyzer filesystem authority hardening that does not affect producing the first raw capture artifact;
- optional haptics;
- VoiceOver rotor/heading refinements beyond a usable primary flow;
- Reduce Transparency / Increase Contrast / Differentiate Without Color polish beyond clear/readable operation;
- cosmetic screenshot perfection that does not hide, clip, mislabel, or block the primary capture flow;
- generic refactors, API cleanup, schema elegance, branch hygiene, duplicate-test cleanup, and theoretical future release-security work.

Record those findings durably in GitHub with label/wording equivalent to **POST-CAPTURE HARDENING**. Do not silently discard them.

A reviewer may still report a noncritical finding, but it must not reset the final acceptance clock or move the flagship head before first capture unless the integration closer promotes it under the nine blocking conditions above.

---

## 3. Today’s minimum field-ready acceptance ladder

The first real ES80 Capture may earn GO when ALL of the following are true on one frozen exact head:

1. package/app compile succeeds on Xcode 27;
2. exact-head app/Simulator smoke path succeeds;
3. primary Capture path is visibly usable on iPhone 12/iOS 27 target sizing;
4. OFF1 -> ON1 -> OFF2 -> ON2 correlation remains deterministic and fails closed on zero/multiple candidates;
5. no application characteristic-value writes/commands exist in the Experiment One path;
6. charger-disconnected + stationary operator preflight is explicit and required fresh for the run;
7. >=60 s same-authority passive observation and final seal/export integrity remain intact;
8. the exact final Share/capture bytes can be retained/exported and independently hashed/analyzed;
9. a real signed installable developer/research iPhone build is produced from that frozen exact source;
10. that exact build is deliberately field-authorized for **this stationary passive recipe only** and named in the runbook;
11. the runbook states stop conditions and still says no riding / no writes / charger disconnected.

Do not require full App-Store/release-distribution hardening to collect the first private research artifact.

---

## 4. Developer research authorization vs release authorization

The first private ES80 capture is a developer/research procedure, not a public release.

Therefore workers may separate two authority levels:

### A. TODAY — Research Field Build
A deliberately produced, exact-source, signed developer build for the intended iPhone may earn Experiment One authorization if the package can mechanically prove it is the special research configuration and the safe passive recipe is compiled in.

Requirements:
- exact source/build identity;
- intended recipe `ES80-FINGERPRINT-v1`;
- no application characteristic writes/commands reachable;
- fresh stationary + charger-disconnected preflight;
- fail-closed target correlation;
- explicit operator action to begin;
- exact runbook names the accepted build;
- authorization cannot be toggled by a normal Settings preference or arbitrary imported unsigned JSON.

A compile/build-time research entitlement/configuration tied to the exact signed developer build is acceptable for this private first capture if implemented fail-closed and testable.

### B. LATER — Release-grade authorization
External P-256 authority, hostile-host filesystem custody, public distribution signing policy, deeply closed-world evidence manifests, and other release-grade anti-tamper hardening remain valuable, but they are POST-CAPTURE unless independently required by the normal private research path.

Do not make the first raw ES80 dataset wait for a public-release threat model.

---

## 5. Final-head discipline

Once the current integration closer declares **TODAY FREEZE CANDIDATE**:

- stop merging noncritical changes into that head;
- run one terminal trusted exact-head Xcode 27 package/app/UI/provenance acceptance;
- inspect only defects that meet the nine blocker conditions;
- if a noncritical issue is found, record it to post-capture backlog without changing the frozen head;
- if a true blocker is found, fix only that blocker, freeze again, and rerun exact-head acceptance.

This prevents endless “one more polish fix -> new SHA -> old green no longer counts” loops.

---

## 6. Swarm behavior until first artifact

Prioritize workers roughly as follows:

1. Integration closer / freeze captain
2. exact-head Xcode + signed developer build
3. field-research authorization/runbook
4. primary-path crash/hang/correlation/export QA
5. primary-path visual usability
6. only then adjacent noncritical hardening

If a worker discovers a noncritical forensic issue, post it durably and self-reassign to a TODAY blocker instead of opening another flagship-moving repair.

PR count and red-team depth are not the goal. **Time to first trustworthy real ES80 artifact is the goal.**

---

## 7. After first real capture

Immediately:

1. preserve the raw artifact unchanged;
2. run the offline analyzer;
3. identify real services/characteristics/notifications/cadence/correlation evidence;
4. use that truth to continue Nembra Battery / Power / Speed / Range / Controls / Dashboard integration;
5. reopen the deferred release-grade hardening backlog in parallel, not as the only project activity.

The first physical capture is the data unlock for Nembra 2.0 development. It is not the end of the app.
