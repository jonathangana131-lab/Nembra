# ES80 TODAY Private Field Runbook — V14

Status: **NO-GO — DO NOT RUN PHYSICAL EXPERIMENT ONE YET.**

Purpose: field handoff for the first private, stationary, charger-disconnected, passive/read-only `ES80-FINGERPRINT-v1` artifact under `CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md` and `ES80_TODAY_RESEARCH_AUTHORIZATION_CONTRACT.md`.

This document is intentionally narrower than the release-grade/public physical authorization design. For the first private artifact only, the TODAY contract permits the exact dedicated Research Field Build to use package-owned build-time `ResearchAdmission` instead of waiting for the public P-256 envelope/trust-root ceremony. The public P-256 path remains POST-CAPTURE hardening and is not silently weakened or deleted.

This runbook never makes software evidence physical truth. It authorizes only the exact build/procedure named in the Final GO Record below after every TODAY gate is closed.

The exact retained-IPA installation handoff in `docs/ES80_TODAY_EXACT_RETAINED_IPA_INSTALL.md` is a mandatory part of this runbook. Its pinned external retained-candidate cross-check, pre-install digest, exact install route, post-install digest, and installed-runtime provenance rendezvous are Final GO evidence, not optional supporting notes. The external cross-check remains `PASS_NOT_FINAL_GO`; it does not authorize Bluetooth activity by itself.

## Current accepted software subject

The software/Simulator gate is already closed for one frozen Capture subject. Do not rerun unchanged-source Xcode merely to accumulate evidence and do not move the frozen product head unless a newly demonstrated TODAY blocker requires a bounded repair.

- Frozen Capture PR/head: `#833@a0f4a33451f61411d6e0541f2e70edea5438342d`
- Accepted build identity: `Capture Build V14-a0f4a33451f6`
- Recipe/procedure: `ES80-FINGERPRINT-v1` / `V14`
- Ordinary exact Xcode 27 app/runtime run: `31310396405` — **SUCCESS**
- Trusted owner-command run: `31312741465` — **SUCCESS**
- Trusted resolver job: `93242986211` — **SUCCESS**
- Trusted isolated prevalidation job: `93243000285` — **SUCCESS**
- Trusted Mac authority job: `93243212531` — **SUCCESS**
- Accepted retained owner artifact: `9038098282` / `nembra-capture-xcode27-833-641-1`
- Retained artifact GitHub digest: `sha256:f128a9bd05b2ceff7be47addce103028d7bc6982ede17ad0bc8894983e826e72`
- Independent retained-manifest verification: **PASS — 64/64 subjects exact**
- Retained visual acceptance: **ACCEPTED**, including critical Accessibility XXXL and landscape Capture states
- Signed intended-device Research Field Build: **NOT YET PRODUCED / VERIFIED HERE**
- First real ES80 artifact: **NOT YET COLLECTED**

These accepted software identifiers are supporting inputs to the private field handoff. They do not authorize copying guessed values into the Final GO Record, do not prove an intended-device signed IPA exists, and do not grant Bluetooth or physical Experiment One authority.

## Current NO-GO blockers

Before this document may flip to `GO`, all of the following must be true for one frozen software candidate:

1. **SATISFIED for exact `a0f4a334…`:** terminal trusted Xcode 27 acceptance succeeded on the exact frozen source SHA. Queued, running, skipped, cancelled, ancestor, child-only, package-only, or unrelated Simulator results remain non-evidence.
2. **SATISFIED for exact `a0f4a334…`:** retained primary-path Simulator artifacts/screenshots from the accepted run were independently inspected with no TODAY blocker found in the accepted Capture flow, Share path, build/provenance presentation, Accessibility XXXL, or critical landscape states.
3. **PENDING PRIVATE SIGNING SURFACE:** follow `docs/ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md` end-to-end on exact frozen source. That canonical production handoff owns the pinned private intended-device helper, pinned non-authorizing preflight, `DEVELOPER_DIR` / `xcode-select` coherence gate, descriptor-bound ExportOptions custody/coherence, and the only accepted transition into `scripts/ci/xcode27_today_research_field_candidate.sh`. **Do not invoke the TODAY wrapper directly from this runbook.** The wrapper may run only after the canonical production handoff's exact checks admit producer invocation; it then compiles the dedicated `NEMBRA_ES80_TODAY_RESEARCH` capability and delegates signing, exact-source, intended-device, recipe, hashing, and retained-evidence production to the canonical `scripts/ci/xcode27_signed_field_candidate.sh` producer. Invoking the ordinary producer directly is also intentionally NO-GO because it must not compile research admission.
4. **PENDING RETAINED SIGNED CANDIDATE:** the canonical signed-field inspector must independently verify the retained IPA's code signing, provisioning/team/application identity, intended-device authorization, `NembraCaptureFieldRecipe=ES80-FINGERPRINT-v1`, exact build/source tuple, executable SHA-256, raw Info.plist SHA-256, and exact IPA SHA-256.
5. **PENDING CROSS-CHECK + EXACT INSTALL:** before installation, the published candidate must pass the pinned external retained-candidate cross-check in `docs/ES80_TODAY_EXACT_RETAINED_IPA_INSTALL.md`; its receipt remains outside the candidate, reports `PASS_NOT_FINAL_GO` / `physicalExperimentAuthorization=not-granted`, verifies the exact Research Field Build tuple `private-today-v1 / canonical-producer-explicit-mode / NEMBRA_ES80_TODAY_RESEARCH`, and its private-runner/canonical-inspector Git-blob claims reconcile against the exact frozen Capture source repository. The exact retained signed IPA is then installed on the intended iPhone 12 / iOS 27 without rebuild/re-export/substitution, SHA-256 checked before and after installation, and the Home-Screen-launched app's source/build/build-instance/recipe rendezvous exactly matches the retained evidence.
6. **PENDING PHYSICAL-RUNTIME RENDEZVOUS:** package-owned TODAY research admission must be observed on the dedicated physical-iOS Release Research Field Build, remain recipe-bound to `ES80-FINGERPRINT-v1`, and ordinary/Debug/Simulator/general builds must remain NO-GO.
7. **SOFTWARE CONTRACT ACCEPTED; RECHECK INSTALLED RUNTIME:** the live Capture path requires explicit operator action; authorization must not auto-start capture.
8. **SOFTWARE CONTRACT ACCEPTED; FRESH FIELD SETUP STILL REQUIRED:** Stationary + charger-disconnected setup remains mechanically required by the accepted preflight/setup contract.
9. **SOFTWARE SOURCE REVIEW ACCEPTED; RECHECK EXACT INSTALLED SUBJECT:** no application Bluetooth characteristic-value write/command path may be introduced or enabled.
10. **PENDING FINAL PROCEDURAL AUTHORITY:** the hardened Final GO record must be issued from independently checked retained evidence plus the fresh operator attestation described by `docs/ES80_TODAY_FINAL_GO_OPERATOR_ATTESTATION.md`. It must bind the exact frozen source SHA, signed IPA SHA-256, build identity, pinned external cross-check tool/receipt, Research Field Build compile tuple, recipe, procedure, intended baseline, exact retained-IPA installation evidence, expected output, and stop conditions.

Until every item above is closed, this document stays **NO-GO**.

## Final GO Record — intentionally blank while NO-GO

Do not fill values from memory, PR prose, signer stdout alone, stale artifacts, or self-reported metadata without checking the retained exact bytes/evidence. The accepted software-subject section above is coordination context, not permission to bypass the hardened Final GO publisher.

- Accepted exact source SHA: **NOT YET AUTHORIZED**
- Trusted Xcode 27 run / job: **NOT YET AUTHORIZED**
- Accepted signed IPA SHA-256: **NOT YET AUTHORIZED**
- Accepted build identifier: **NOT YET AUTHORIZED**
- Accepted build-instance ID: **NOT YET AUTHORIZED**
- Accepted executable SHA-256: **NOT YET AUTHORIZED**
- Accepted raw Info.plist SHA-256: **NOT YET AUTHORIZED**
- Accepted external build record SHA-256: **NOT YET AUTHORIZED**
- Accepted field-build evidence record SHA-256: **NOT YET AUTHORIZED**
- Signing / intended-device inspection: **NOT YET AUTHORIZED**
- Independent cross-check tool commit: **d827a296048386bda62024ea3278775d5344c47c / REQUIRED**
- Independent cross-check verifier Git blob: **c3b2b620280484c05316fc5c2fa2ca451f1fdc83 / REQUIRED**
- Independent cross-check accepted QA lineage: **4125d16ad839d4b677b389cce590157c0574b8c4 / run 31294257471 / SUCCESS**
- Independent retained-candidate cross-check receipt SHA-256: **NOT YET AUTHORIZED**
- Independent cross-check authority/status: **PASS_NOT_FINAL_GO / NOT YET CHECKED**
- Research compile mode: **private-today-v1 / NOT YET CHECKED**
- Research compile authority: **canonical-producer-explicit-mode / NOT YET CHECKED**
- Research compile condition: **NEMBRA_ES80_TODAY_RESEARCH / NOT YET CHECKED**
- Research compile tuple verified: **NO / NOT YET AUTHORIZED**
- Producer / canonical-inspector Git-blob claim reconciliation: **NO / NOT YET AUTHORIZED**
- Exact retained-IPA install handoff procedure: **REQUIRED / NOT YET COMPLETED**
- Pre-install retained IPA SHA-256 match: **NO / NOT YET AUTHORIZED**
- Installation route: **EXACT RETAINED IPA VIA XCODE DEVICE MANAGEMENT / NOT YET COMPLETED**
- Installed on intended iPhone 12 / iOS 27: **NO / NOT YET AUTHORIZED**
- Post-install retained IPA SHA-256 match: **NO / NOT YET AUTHORIZED**
- Runtime source/build/build-instance/recipe rendezvous match: **NO / NOT YET AUTHORIZED**
- Package research admission: **NO-GO / NOT YET AUTHORIZED**
- Ordinary/general build authority: **MUST REMAIN NO-GO**
- Procedure version: **V14 / NOT YET AUTHORIZED**
- Experiment recipe: **ES80-FINGERPRINT-v1 / NOT YET AUTHORIZED**
- Required charger declaration: **DISCONNECTED**
- Required motion state: **STATIONARY for the entire Experiment One procedure**
- Expected Share artifact: **NOT YET AUTHORIZED**
- Physical result collected: **NO**

The final `GO` record may name a frozen source SHA that is different from the documentation commit containing this runbook. That is intentional: changing procedure/coordination documentation after software acceptance must not mutate the already accepted/signed application source candidate and reset its identity.

## Safety and truth rules

1. Experiment One is stationary. Do not ride the scooter during this first fingerprint procedure.
2. Keep the charger disconnected for the entire accepted Experiment One session. If that declaration stops being true, abort and start a fresh session later.
3. Do not touch unknown application characteristic writes or random scooter commands.
4. Read only where `.read` is advertised and the accepted passive policy permits it.
5. Subscribe only where `.notify` / `.indicate` is advertised and the accepted passive policy permits it.
6. Writable characteristic metadata is not command authorization and a CoreBluetooth callback is not physical acknowledgement.
7. Scan name, RSSI, local-name similarity, service-name hints, short IDs, Tuya-looking strings, or public research do not authenticate the scooter.
8. Preserve raw callback boundaries, FIFO chronology, monotonic receipt timing, GATT identity, origin, continuity, build/procedure provenance, and exact final Share bytes.
9. Missing evidence is not evidence of absence. Any invalid/incomplete session stays incomplete.
10. Simulator/public/display/derived evidence never becomes physical telemetry truth.
11. Experiment One does not establish battery, voltage, current, watts, speed, throttle, regen, command acknowledgement, rated maximum, or production telemetry semantics.

## Private signed-candidate handoff — next legal transition

This is the current critical path. It requires a private macOS/Xcode 27 signing surface plus the intended iPhone 12 / iOS 27. It is not another public GitHub/Simulator gate.

1. Use `docs/ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md` as the **mandatory production entrypoint** for exact frozen source `a0f4a33451f61411d6e0541f2e70edea5438342d`. Complete its exact detached-source, private intended-device helper, ExportOptions, Xcode-selection, and non-authorizing preflight gates before producer invocation.
2. **Do not manually construct or substitute the intended-device input and do not invoke `scripts/ci/xcode27_today_research_field_candidate.sh` directly from this runbook.** The canonical production handoff materializes and verifies the accepted helper bytes, keeps the raw UDID off public surfaces, fails closed on its custody rules, and invokes the TODAY wrapper only after `READY_TO_INVOKE_SIGNED_FIELD_PRODUCER` for the exact frozen source.
3. Preserve the one immutable retained candidate and its `inspection/build-evidence/NembraField.ipa` subject produced by that canonical handoff.
4. Require canonical signing/provisioning/intended-device inspection to pass on those exact retained bytes.
5. Complete the pinned external retained-candidate cross-check from a separate clean tooling checkout as required by `docs/ES80_TODAY_EXACT_RETAINED_IPA_INSTALL.md`; require exact `PASS_NOT_FINAL_GO` semantics and exact frozen-source producer/inspector blob reconciliation.
6. Hash the retained IPA immediately before installation.
7. Install that exact retained IPA through Xcode device management without rebuild, re-export, substitution, Product → Run, or DerivedData app installation.
8. Launch Nembra from the iPhone Home Screen and verify exact source/build/build-instance/recipe rendezvous plus `PRIVATE RESEARCH BUILD / Runtime provenance ready`.
9. Hash the original retained IPA again and require exact equality with the accepted pre-install/cross-check digest.
10. Perform the fresh operator observations required by `docs/ES80_TODAY_FINAL_GO_OPERATOR_ATTESTATION.md` and issue the hardened Final GO record through `scripts/ci/es80_today_final_go_hardened.py`.
11. Only an accepted hardened Final GO record may transition this runbook to Experiment One.

If any step fails or is ambiguous, preserve that exact blocker and remain NO-GO. Do not substitute a new build merely to get past an evidence mismatch.

## Preflight once Final GO exists

Before the first scan, confirm in the accepted app:

- Bluetooth permission is granted and Bluetooth is powered on;
- the app is foregrounded and required foreground integrity is healthy;
- exact runtime build identity is available and matches the accepted Research Field Build tuple;
- the running build is the dedicated physical-iOS Release research configuration for `ES80-FINGERPRINT-v1`;
- package-owned research admission succeeds; no UI Boolean, preference, launch argument, environment variable, remote flag, or imported JSON can mint it;
- `docs/ES80_TODAY_EXACT_RETAINED_IPA_INSTALL.md` was completed for this exact candidate, including the pinned external `PASS_NOT_FINAL_GO` receipt, verified exact Research Field Build compile tuple, and frozen-source Git-blob reconciliation, matching pre-install and post-install retained IPA SHA-256 values, plus the exact Home-Screen runtime source/build/build-instance/recipe rendezvous;
- the exact signed IPA named in the Final GO Record is the build installed on the intended iPhone;
- the hardened Final GO record was issued from fresh, independently checked evidence and has not been replaced by stale operator notes;
- no accepted app/runtime state is already known to make the normal exact-byte Share path impossible; there is no separate pre-scan filesystem/export certificate, and authoritative export readiness is earned only after seal + final Share integrity;
- charger state is freshly declared **Disconnected**;
- the scooter is stationary and safe to power OFF/ON for correlation;
- one intended physical ES80 is available;
- no unknown Nembra command/write path is enabled;
- capture begins only after explicit operator action.

If any item fails, remain NO-GO for that attempt.

## Experiment One procedure

### A. Correlate the physical target

Use the accepted deterministic sequence. Each window must satisfy the package-owned minimum observation duration; current V14 recipe intent is at least 10 seconds per window under accepted monotonic receipt-time evidence.

1. **OFF1** — scooter physically off; collect the full accepted window.
2. **ON1** — power scooter on; collect the full accepted window.
3. **OFF2** — power scooter off; collect the full accepted window.
4. **ON2** — power scooter on; collect the full accepted window.
5. Let package correlation compare full CoreBluetooth peripheral identity across all four windows.
6. Continue only if exactly one candidate satisfies accepted repeatability rules.
7. Present it only as a **correlated Bluetooth target / scooter signal found**.
8. Explicitly confirm that exact candidate before starting target-labeled durable capture.

Never break a tie using name, RSSI, Tuya hints, service vibes, or shortened identifiers. Ambiguous correlation means stop, not guess.

### B. Acquire passive GATT evidence

After target confirmation:

1. Connect through the accepted foreground-only passive controller.
2. Discover services, included services, characteristics, properties, and descriptors.
3. Perform only accepted reads/subscriptions allowed by observed properties and passive policy.
4. Preserve structured connection/discovery/subscription/raw-value/interruption/provenance evidence.
5. If finite acquisition cannot earn accepted Ready, stop. Do not continue as though Ready occurred.

### C. Observation horizon

After accepted finite-acquisition Ready:

1. Keep the app foregrounded and scooter stationary.
2. Observe for at least **60 seconds after accepted Ready** under the canonical monotonic evidence contract.
3. UI countdown is guidance only; it does not mint evidence.
4. Any authority, foreground, chronology, continuity, or setup invalidation fails closed.

### D. Finish, seal, integrity, share

After the accepted horizon:

1. Admit Finish exactly once.
2. Preserve FIFO chronology through the exact Horizon cutoff.
3. Record Horizon and commit the accepted queue transaction.
4. Freeze the immutable exact-H artifact before terminal completion authority.
5. Resolve/retire any post-H callback suffix only through accepted lifecycle logic; retired callbacks are not recorder-written evidence.
6. Require final artifact integrity + analyzer readiness + build/procedure provenance + export readiness.
7. Continue only when the UI reports `CAPTURE COMPLETE — Ready for analysis`.
8. Use the primary `SHARE CAPTURE` action.
9. Preserve the resulting raw Share artifact unchanged before any derived analysis.

## Expected first artifact

The accepted Share artifact must preserve or bind enough evidence for the next research rung, including:

- capture schema/version;
- exact accepted Nembra source/build identity and build instance;
- `ES80-FINGERPRINT-v1` recipe/procedure provenance;
- deterministic target-correlation evidence and selected full CoreBluetooth peripheral identity;
- raw advertisement/GATT/value evidence;
- receipt order + accepted monotonic timing;
- continuity/interruption evidence;
- finite-acquisition Ready boundary;
- Horizon boundary + immutable seal/integrity evidence;
- final Share exact-byte integrity/provenance.

Derived transport/DP/telemetry analysis must remain separate from the immutable raw capture.

## Stop / failure conditions

Abort the current attempt and preserve only legitimate incomplete evidence if any of these occurs:

- Bluetooth becomes unavailable;
- target correlation is zero/multiple/ambiguous or a required OFF/ON window is invalid/too short;
- selected target/session changes unexpectedly;
- acquisition never earns accepted Ready;
- foreground integrity is lost;
- charger is connected or the fresh disconnected declaration is no longer true;
- scooter cannot remain stationary/safe;
- accepted post-Ready 60-second horizon cannot be proven;
- chronology/authority/continuity invalidates the recipe stage;
- Horizon, queue commit, immutable freeze, final integrity, or Share readiness fails;
- runtime build identity no longer matches the accepted Research Field Build;
- package research admission is unavailable or wrong-recipe;
- the external retained-candidate receipt is missing, altered, not `PASS_NOT_FINAL_GO`, claims physical authorization, does not verify `private-today-v1 / canonical-producer-explicit-mode / NEMBRA_ES80_TODAY_RESEARCH`, or its producer/inspector blob claims do not reconcile against the exact frozen source;
- the exact retained-IPA installation handoff was not completed, or either retained IPA digest check / runtime rendezvous does not match the Final GO Record;
- installed build cannot be tied to the exact retained IPA digest named in the Final GO Record;
- the hardened Final GO record is absent, stale, mismatched, or not an accepted `GO` for the exact installed subject;
- the procedure would require an unknown characteristic write/command.

Do not improvise around a failed gate. The correct output is an incomplete/failed attempt plus the exact blocker for the next iteration.

## Post-capture return to full hardening

After the first accepted raw ES80 artifact is preserved, return immediately to the full V14 evidence ladder and release-grade backlog. The deferred independently signed P-256 field-authorization envelope/trust-root work remains relevant for public/release authorization; TODAY's private Research Field Build is not precedent for weakening that boundary.

## Current conclusion

**NO-GO / DO NOT RUN / DO NOT SCAN.**

The software/Simulator owner-command gate for frozen `#833@a0f4a33451f61411d6e0541f2e70edea5438342d` is accepted. The next legal transition is **private production through `docs/ES80_TODAY_SIGNED_FIELD_CANDIDATE_PRODUCTION.md` of the signed intended-device Research Field Build**, followed by canonical signing/provisioning/intended-device inspection, the pinned external retained-candidate `PASS_NOT_FINAL_GO` cross-check, exact retained-IPA installation/rendezvous under `docs/ES80_TODAY_EXACT_RETAINED_IPA_INSTALL.md`, fresh operator attestation, and successful hardened Final GO record issuance. Only after those exact gates close may the stationary, charger-disconnected, passive/read-only Experiment One begin.