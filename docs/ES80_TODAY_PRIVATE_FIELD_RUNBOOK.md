# ES80 TODAY Private Field Runbook — V14

Status: **NO-GO — DO NOT RUN PHYSICAL EXPERIMENT ONE YET.**

Purpose: field handoff for the first private, stationary, charger-disconnected, passive/read-only `ES80-FINGERPRINT-v1` artifact under `CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md` and `ES80_TODAY_RESEARCH_AUTHORIZATION_CONTRACT.md`.

This document is intentionally narrower than the release-grade/public physical authorization design. For the first private artifact only, the TODAY contract permits the exact dedicated Research Field Build to use package-owned build-time `ResearchAdmission` instead of waiting for the public P-256 envelope/trust-root ceremony. The public P-256 path remains POST-CAPTURE hardening and is not silently weakened or deleted.

This runbook never makes software evidence physical truth. It authorizes only the exact build/procedure named in the Final GO Record below after every TODAY gate is closed.

## Current NO-GO blockers

Before this document may flip to `GO`, all of the following must be true for one frozen software candidate:

1. Terminal trusted Xcode 27 acceptance succeeds on the exact frozen source SHA. Queued, running, skipped, cancelled, ancestor, child-only, package-only, or Simulator-only results are not final acceptance.
2. Retained primary-path Simulator artifacts/screenshots from that exact run are inspected for TODAY blockers: unusable Capture flow, missing/incorrect Share, unsafe operator flow, build/provenance failure, or another defect that makes the first artifact unsafe or unusable.
3. The TODAY-only `scripts/ci/xcode27_today_research_field_candidate.sh` wrapper compiles the dedicated `NEMBRA_ES80_TODAY_RESEARCH` capability and delegates signing, exact-source, intended-device, recipe, hashing, and retained-evidence production to the canonical `scripts/ci/xcode27_signed_field_candidate.sh` producer. Invoking the ordinary producer directly is intentionally NO-GO because it must not compile research admission.
4. The canonical signed-field inspector independently verifies the retained IPA's code signing, provisioning/team/application identity, intended-device authorization, `NembraCaptureFieldRecipe=ES80-FINGERPRINT-v1`, exact build/source tuple, executable SHA-256, raw Info.plist SHA-256, and exact IPA SHA-256.
5. The exact retained signed IPA is installed on the intended iPhone 12 / iOS 27 device.
6. The package-owned TODAY research admission is available only in the dedicated physical-iOS Release Research Field Build, remains recipe-bound to `ES80-FINGERPRINT-v1`, and ordinary/Debug/Simulator/general builds remain NO-GO.
7. The live Capture path still requires explicit operator action; authorization does not auto-start capture.
8. Stationary + charger-disconnected setup remains mechanically required by the accepted preflight/setup contract.
9. No application Bluetooth characteristic-value write/command path is introduced or enabled.
10. The Final GO Record below is filled from independently checked retained evidence and names the exact frozen source SHA, exact IPA SHA-256, exact build identity, recipe, procedure, intended baseline, expected output, and stop conditions.

Until every item above is closed, this document stays **NO-GO**.

## Final GO Record — intentionally blank while NO-GO

Do not fill values from memory, PR prose, signer stdout alone, stale artifacts, or self-reported metadata without checking the retained exact bytes/evidence.

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
- Installed on intended iPhone 12 / iOS 27: **NO / NOT YET AUTHORIZED**
- Package research admission: **NO-GO / NOT YET AUTHORIZED**
- Ordinary/general build authority: **MUST REMAIN NO-GO**
- Procedure version: **V14 / NOT YET AUTHORIZED**
- Experiment recipe: **ES80-FINGERPRINT-v1 / NOT YET AUTHORIZED**
- Required charger declaration: **DISCONNECTED**
- Required motion state: **STATIONARY for the entire Experiment One procedure**
- Expected Share artifact: **NOT YET AUTHORIZED**
- Physical result collected: **NO**

The final `GO` edit may name a frozen source SHA that is different from the documentation commit containing this record. That is intentional: changing this documentation after software acceptance must not mutate the already accepted/signed application source candidate and reset its identity.

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

## Preflight once Final GO exists

Before the first scan, confirm in the accepted app:

- Bluetooth permission is granted and Bluetooth is powered on;
- the app is foregrounded and required foreground integrity is healthy;
- exact runtime build identity is available and matches the accepted Research Field Build tuple;
- the running build is the dedicated physical-iOS Release research configuration for `ES80-FINGERPRINT-v1`;
- package-owned research admission succeeds; no UI Boolean, preference, launch argument, environment variable, remote flag, or imported JSON can mint it;
- the exact signed IPA named in the Final GO Record is the build installed on the intended iPhone;
- storage/export readiness is healthy;
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
- installed build cannot be tied to the exact retained IPA digest named in the Final GO Record;
- the procedure would require an unknown characteristic write/command.

Do not improvise around a failed gate. The correct output is an incomplete/failed attempt plus the exact blocker for the next iteration.

## Post-capture return to full hardening

After the first accepted raw ES80 artifact is preserved, return immediately to the full V14 evidence ladder and release-grade backlog. The deferred independently signed P-256 field-authorization envelope/trust-root work remains relevant for public/release authorization; TODAY's private Research Field Build is not precedent for weakening that boundary.

## Current conclusion

**NO-GO / DO NOT RUN.**

The next legal transition is not a physical experiment. It is terminal exact-head Apple acceptance of the frozen Capture candidate, followed by production + independent inspection + installation of the exact signed intended-device Research Field Build, then completion of the Final GO Record above.
