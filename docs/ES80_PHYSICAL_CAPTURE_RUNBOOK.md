# AOVOPRO ES80 Passive Physical Capture Runbook — V14

Status: **NO-GO — PHYSICAL EXPERIMENT ONE MUST NOT RUN FROM THE CURRENT SOFTWARE LINEAGE.**

Primary physical target: the current/newer Tuya-generation AOVOPRO ES80.

This document is the physical-procedure gate for Nembra Capture under the V14 product contract. It supersedes older V11-era timing/authorization wording in this file. Supporting passive research primitives may already exist, but package code, Simulator evidence, a passing child PR, or a visually complete research shell does not authorize a physical experiment.

Only the **final composed exact build** may change this status from `NO-GO` to `GO` after every required software, app-visible, runtime, integrity, and safety gate below is satisfied.

## Current NO-GO blockers

The current passive-foundation recovery does not by itself close the full V14 Capture vertical. Before this runbook can become `GO`, the final composed product must have all of the following accepted on one exact head:

- passive CoreBluetooth capture foundation and continuity-safe offline analysis;
- deterministic OFF1 -> ON1 -> OFF2 -> ON2 target correlation;
- explicit operator confirmation of the correlated target before target-labeled capture;
- one canonical artifact-authority lifecycle across the real foreground controller;
- finite acquisition `Ready` admission tied to the exact accepted queue/recorder chronology;
- an authoritative observation horizon of **at least 60 seconds after accepted Ready**, measured by the canonical monotonic evidence contract rather than a visual timer;
- exact Horizon recorder proof, queue commit, immutable artifact read/freeze, and terminal seal;
- fail-closed handling for Ready/Horizon authority changes, stale callbacks, abandoned epochs, post-H queue retirement/resolution, and fresh-session reopen;
- app-visible Capture flow with Bluetooth privacy configuration, preflight, target correlation, capture health, completion, integrity, and direct share/export;
- exact build/procedure/recipe provenance embedded in the exported artifact;
- final exact-head Xcode 27 / iPhone 12 / iOS 27 acceptance for the composed app;
- required visual, accessibility, performance, and recovery-state review for the app-visible Capture surface;
- an explicit final runbook edit that names the accepted exact build/commit, procedure version, expected artifact, and stop conditions and changes this status to `GO`.

Until those conditions are closed, all procedures below are **supporting experiment recipes only**. They describe the intended safe physical sequence but are not authorization to perform it.

## Safety and truth rules

1. Keep the scooter stationary for setup, target correlation, arming, and completion/export interaction.
2. Do not touch or operate the phone while riding. Any riding experiment begins only after capture is armed and phone interaction resumes only after safely stopping.
3. Do not send unknown application characteristic writes or random scooter commands.
4. Do not copy writable Tuya DP IDs from another product and treat them as ES80 commands.
5. Discover/read/subscribe only according to observed GATT properties and accepted passive policy.
6. Treat `.write` / `.writeWithoutResponse` characteristic properties as metadata, never authorization.
7. Treat subscription success and CoreBluetooth write-capability metadata as transport facts, never scooter command acknowledgement.
8. Treat FD50, A201, 1910, ZYDTECH, Tuya, and other researched families as candidates until the physical target supplies matching evidence.
9. Preserve raw CoreBluetooth callback boundaries, queue chronology, monotonic receipt timing, GATT identity, origin, continuity, and capture provenance. Derived framing/decryption/field hypotheses belong in separate analysis artifacts.
10. Do not export Tuya local/auth/session keys, account tokens, or unrelated credentials.
11. Do not claim Nembra intercepted another app's private Bluetooth exchange. CoreBluetooth supplies Nembra's own central-session observations.
12. A scan name, RSSI, local-name similarity, service-name hint, or short identifier never establishes authoritative ES80 identity.
13. A CoreBluetooth peripheral UUID is useful observed identity evidence but is not automatically a permanent physical-scooter identifier.
14. If acquisition, foreground integrity, chronology, horizon duration, seal, integrity, or export readiness fails, treat the session as incomplete. Never interpret missing evidence as proof that a field/service/event does not exist.
15. Never promote Simulator, public research, display interpolation, or derived UI motion into physical telemetry evidence.

## Final GO record — intentionally blank while NO-GO

When the software is actually ready, replace this section in the same acceptance change that flips the status above to `GO`.

- Accepted exact build/commit: **NOT YET AUTHORIZED**
- Procedure version: **V14 / NOT YET AUTHORIZED**
- Baseline device: iPhone 12 / iOS 27
- Experiment recipe: **ES80-FINGERPRINT-v1 candidate; final recipe authority not yet issued**
- Expected artifact: **NOT YET AUTHORIZED**
- Physical result collected: **NO**

No ancestor SHA, package-only green, child PR, Simulator run, or stale acceptance may be filled into this section as the final physical build.

## Intended preflight once GO is authorized

Before the first scan, the accepted app must mechanically verify or clearly block on:

- Bluetooth permission and powered-on state;
- foreground evidence integrity;
- exact build identity and capture schema compatibility;
- storage/export readiness;
- the exact versioned experiment recipe;
- any required stock-app/reference-marker setup;
- no unknown Nembra command path enabled;
- scooter stationary and safe to test;
- one intended physical ES80 available for the correlation sequence.

The primary UI should show `READY` only when those requirements are satisfied. Otherwise it must show the exact blocker.

## Experiment One — target correlation and passive fingerprint

This is the smallest useful first physical experiment after the final runbook status becomes `GO`.

### A. Correlate the physical target

Use the deterministic physical power sequence:

1. **OFF1** — scooter physically off; collect the accepted scan interval.
2. **ON1** — power the scooter on; collect the accepted scan interval.
3. **OFF2** — power the scooter off again; collect the accepted scan interval.
4. **ON2** — power the scooter on again; collect the accepted scan interval.
5. Let the accepted correlation logic compare full CoreBluetooth peripheral identity across the four intervals.
6. If exactly one candidate satisfies the accepted repeatability rules, present it only as a **correlated Bluetooth target / scooter signal found**.
7. The operator explicitly confirms that exact correlated candidate before a target-labeled durable capture session begins.

Do not break ties using display name, RSSI, vague Tuya hints, service-name vibes, or short IDs. If the accepted correlation contract cannot produce one unambiguous candidate, stop. Do not guess.

This step does **not** by itself prove permanent AOVOPRO ES80 identity or protocol semantics.

### B. Acquire passive GATT evidence

After explicit target confirmation:

1. Connect to the selected target through the accepted foreground-only capture controller.
2. Discover services, included services, characteristics, properties, and descriptors.
3. Read only where `.read` is advertised and the accepted passive policy permits it.
4. Subscribe only where `.notify` / `.indicate` is advertised and the accepted passive policy permits it.
5. Preserve structured connection, discovery, subscription, raw value, interruption, and provenance evidence.
6. If finite acquisition fails, times out, is invalidated, loses foreground integrity, or otherwise fails the accepted readiness contract, stop and preserve only the legitimate incomplete evidence. Do not proceed to Horizon as if Ready was earned.

### C. Observation Ready and authoritative horizon

Once the final composed controller mints the accepted finite-acquisition `Ready` proof:

1. Begin the observation horizon from that exact committed Ready epoch.
2. Observe for **at least 60 seconds after Ready** under the accepted monotonic evidence contract.
3. A UI countdown may guide the user, but the visual timer is presentation only. It cannot authorize the artifact or substitute for the monotonic Ready/Horizon duration evidence.
4. Continue to preserve accepted raw callbacks and continuity/interruption evidence during the horizon.
5. If authority changes, chronology becomes invalid, the app loses required foreground integrity, or another accepted failure condition occurs, fail closed. Do not relabel an incomplete/abandoned session as complete.

### D. Horizon, immutable seal, integrity, and share

After the accepted minimum horizon is satisfied:

1. Admit Finish exactly once through the final composed lifecycle.
2. Respect pending callback/FIFO chronology through the exact Horizon cutoff.
3. Durably record the exact Horizon boundary.
4. Commit the exact queue transaction.
5. Perform the immutable exact-H artifact read/freeze before terminal authority is granted.
6. Retire/resolve any post-H callback suffix only through the accepted producer-issued retirement/resolution path; retired positions are not recorder-written evidence.
7. Verify artifact integrity, analyzer readiness, build/procedure provenance, and export readiness.
8. Present `CAPTURE COMPLETE — Ready for analysis` only after those gates succeed.
9. Primary action: `SHARE CAPTURE`. Secondary action: `VIEW DETAILS`.

If the seal or integrity check fails, the UI must say why and preserve already-legitimate evidence without fabricating completion.

## Expected Experiment One artifact once GO exists

The final exported artifact should automatically preserve or bind:

- capture schema/version;
- exact Nembra build/commit identity;
- experiment recipe/version;
- selected/correlated CoreBluetooth peripheral identity and correlation evidence;
- target-session and artifact provenance required by the accepted schema;
- raw advertisement/GATT/value evidence;
- receipt order and accepted monotonic timing evidence;
- continuity/interruption evidence;
- finite-acquisition Ready boundary;
- Horizon boundary and immutable seal/integrity evidence;
- legitimate reference markers when the recipe requires them;
- enough information for offline transport fingerprinting, cadence/statistics, and controlled comparison without rewriting the raw evidence.

Derived analysis must remain separate from the immutable raw capture.

## Questions Experiment One may answer

Only after a valid physical artifact exists may analysis begin to answer:

- which advertisement/GATT identifiers were actually observed on the correlated physical target;
- whether the observed topology resembles FD50, A201, 1910, ZYDTECH/Tuya, or another family;
- which characteristics actually advertised read/notify/indicate/write capabilities;
- which passive raw value streams were observed;
- whether topology changed or invalidated during the accepted session;
- what raw callback cadence/length/duplicate behavior occurred inside each continuity segment.

Use wording such as `OBSERVED ON THE CORRELATED PHYSICAL TARGET` until stronger evidence earns a stronger identity or protocol claim.

Experiment One does **not** by itself establish battery, voltage, current, watts, speed, throttle, regen, command acknowledgement, rated maximum, or other field semantics.

## Follow-up passive recipes — only after Experiment One is accepted

The next physical experiment should be generated from the exact unknowns remaining after offline analysis of Experiment One. Do not run a broad battery/electrical/motion campaign just because the software can record bytes.

Potential later recipes, each requiring its own accepted prerequisites and versioned procedure, include:

### Stationary baseline cadence

- scooter on and stationary, charger disconnected;
- preserve a long enough accepted passive window for cadence analysis;
- compare callback count, continuity segments, provenance, payload-length range, unique/duplicate behavior, and callback interval statistics;
- never call those statistics decoded telemetry cadence until field identity is verified.

### Charger disconnected versus connected

Prefer separate immutable sessions with legitimate visible reference markers when available. Compare topology and raw stream changes only after target/session identity is sufficiently resolved. Do not present an unresolved/different-identifier comparison as proven same-scooter state evidence.

### Post-ride recovery

A later recipe may compare stationary pre-ride and post-ride/rest states. Nembra sends no unknown command. Preserve every interruption boundary and do not convert raw voltage-like changes into SoC semantics without independent verification.

### Controlled riding electrical correlation

Only after stable passive streams and the relevant safety prerequisites are established. Arm while stationary, ride normally without touching the phone, safely stop, then interact/export. Raw correlation may generate hypotheses about speed/current/power behavior but does not establish semantics by itself.

## Cross-app correlation limitation

Nembra cannot claim to passively sniff a stock app's private CoreBluetooth exchange from the same iPhone. Legitimate approaches include Nembra's own read/subscribe session plus before/after reference values, a second-device observation only when the physical setup truly supports it, external BLE test equipment where appropriate, or repeated controlled physical states.

Every capture must document the actual setup used.

## Promotion gates for visible telemetry

### Battery percentage

Verify exact raw/decoded path, scale/range, direct-versus-derived behavior, quantization, cadence/latency, reconnect/charging/load-rest behavior, and low-state behavior before calling it authoritative measured SoC.

### Voltage

Verify exact raw field, units/scale, cadence, load sag/recovery, pack-state behavior, and whether the stock app transforms the value. Never map instantaneous voltage linearly to precise SoC.

### Current

Verify exact raw field, units/scale, signedness, physical meaning, zero/rest behavior, acceleration/braking/charging behavior, and timing quality before energy integration.

### Power

Verify whether an independent raw field exists, units/scale/sign, timing relative to voltage/current, possible `V × A` derivation, and update cadence. A live watt value alone is insufficient for trustworthy energy-per-distance estimates.

### Speed

Verify exact source/field, units/scale, cadence, freshness/currentness behavior, reconnect/gap behavior, resolution, and feature-specific quality requirements before using it as physical stopped authority or historical maximum evidence.

## Stop / failure conditions once GO exists

Stop the experiment and preserve only legitimate evidence if any required condition fails, including:

- Bluetooth becomes unavailable or the accepted target cannot be correlated unambiguously;
- the selected target/session changes unexpectedly;
- acquisition never earns accepted Ready;
- foreground integrity required by the recipe is lost;
- a discontinuity/authority transition invalidates the current recipe stage;
- the accepted >=60-second post-Ready horizon cannot be proven;
- Horizon/queue commit/immutable freeze cannot complete exactly;
- artifact integrity or export readiness fails;
- the physical setup becomes unsafe or would require touching the phone while moving.

Do not improvise around a failed gate in the field. The correct result is an incomplete/failed capture plus an exact blocker for the next software or experiment iteration.

## Current physical conclusion

**NO-GO.** The passive foundation is valuable software evidence, but it is not the final composed app-visible Capture instrument and it cannot authorize physical Experiment One. The first physical session should occur only after this same runbook is deliberately flipped to `GO` with one exact accepted final build and procedure.