# CAPTURE TODAY FIELD-READY DIRECTIVE — V14

Status: **ACTIVE TODAY OVERRIDE / PHYSICAL EXPERIMENT ONE REMAINS NO-GO UNTIL THE FINAL RECORD BELOW IS COMPLETE.**

Feature: **Nembra Capture / first private stationary passive ES80 artifact**

This directive restores the TODAY authority referenced by the Capture flagship and reconciles the repository's release-grade field-authorization design with the narrower private Research-build lane already implemented specifically for the first passive ES80 artifact.

It changes procedure authority only. It does not create Bluetooth write authority, verify an AOVOPRO ES80, assign protocol or telemetry semantics, or authorize a physical experiment by itself.

## 1. Narrow scope and precedence

For **only the first private stationary passive `ES80-FINGERPRINT-v1` artifact**, this directive supersedes older wording in field documents where that wording requires, before the first artifact:

- a configured release-grade P-256 package trust root;
- an externally signed schema-v2 `VerifiedAdmission` envelope;
- the release/global `PassiveBluetoothExperimentOneFieldExecutionGate.status` to change from its default NO-GO value; or
- a tracked post-build runbook edit that would create a new Git source SHA after the signed artifact has already bound the old source SHA.

Those release-grade requirements remain valid future hardening. They are not prerequisites for this one private Research capture unless a later accepted directive explicitly promotes them.

Everything else in the V14 physical runbook remains in force, especially stationary setup, a fresh charger-disconnected declaration, foreground integrity, deterministic OFF1 -> ON1 -> OFF2 -> ON2 correlation, explicit target confirmation, passive/read-only GATT behavior, accepted Ready/Horizon chronology, at least 60 seconds of accepted monotonic observation after Ready, immutable seal, integrity, exact Share artifact preservation, and all stop/failure conditions.

## 2. TODAY package authority

The package intentionally has two separate authority lanes.

### Release-grade lane — deferred for this first artifact

`PassiveBluetoothCaptureVerifiedFieldAuthorization` -> `VerifiedAdmission` remains independently signed and package-trust-root-gated. Its production trust root may remain unconfigured while this private Research procedure is in force.

### Private Research lane — required for TODAY

The first artifact uses the package-owned path:

`makeResearchAuthorizedES80ForCurrentApplication()`
-> `researchAdmissionForCurrentApplication()`
-> module-private `ResearchAdmission`
-> canonical live Research coordinator.

The admission is mechanically available only when the running app is:

- physical iOS;
- non-Simulator;
- non-Debug;
- compiled with `NEMBRA_ES80_TODAY_RESEARCH`;
- carrying exact canonical recipe `ES80-FINGERPRINT-v1` in its processed Info.plist;
- carrying producer-shaped build identifier, build-instance ID, and source SHA matching the runtime identity;
- using canonical build identifier `Capture Build V14-<first 12 source SHA>`; and
- accepted by the package runtime identity reader, which computes the running executable and raw processed Info.plist hashes internally before the Research admission is minted.

`ResearchAdmission` is not a caller-created Boolean, imported document, UserDefaults value, launch argument, target UUID, or UI flag. Ordinary Debug, Simulator, and non-Research Release builds fail closed.

The coordinator may mutate Experiment One only when it owns the canonical live controller and its instance field status is the ResearchAdmission-produced `.goPrivateResearchBuild(build)` state.

This is build/procedure authority only. It does not authenticate the scooter, prove RF completeness, assign GATT/Tuya/DP semantics, or make any telemetry value physical truth.

## 3. Freeze and software acceptance

Before producing the private field IPA, freeze one exact flagship source commit containing the complete app-visible Capture composition and this directive.

That exact source must earn all applicable terminal acceptance, including:

- immutable exact-head resolution;
- required NembraCore and NembraBluetoothCapture validation;
- Xcode 27 app build/test;
- iPhone 12 / iOS 27 Simulator Capture runtime witnesses;
- retained screenshot/log/xcresult/build-evidence inspection required by the flagship;
- exact build/provenance transport validation;
- all current portable Capture custody/authority gates; and
- confirmation that no application characteristic-value write/command authority was introduced.

Queued, pending, skipped, cancelled, sibling, or ancestor evidence is not acceptance. Simulator remains software evidence only.

## 4. Exact private signed Research Field Build

Only after the frozen source earns terminal software acceptance may the private signing surface run:

`scripts/ci/xcode27_today_research_field_candidate.sh`

using the real private signing inputs required by the canonical producer, including the Development Team, accepted ExportOptions plist, and private intended-device input.

The producer must build from the exact accepted source SHA and retain the exact exported signed IPA plus canonical evidence. Independent candidate evidence must preserve or bind at least:

- source commit SHA;
- build identifier;
- build-instance ID;
- executable SHA-256;
- raw processed Info.plist SHA-256;
- recipe `ES80-FINGERPRINT-v1`;
- procedure version `V14`;
- exact signed-installable IPA SHA-256; and
- signing/provisioning/intended-device inspection evidence.

Producer success is evidence, not physical GO.

## 5. Independent candidate acceptance

Before installation or any scan:

1. independently inspect the exact retained IPA and canonical evidence;
2. verify signing/provisioning and intended-device membership under the accepted private field policy;
3. independently recompute the retained IPA and evidence digests required by the candidate contract;
4. verify the retained build/source/build-instance/recipe/executable/raw-Info.plist evidence is internally consistent with the exact retained candidate;
5. reject substitution, re-export, rebuild, stale artifacts, or ancestor artifacts.

The executable SHA-256 and raw processed Info.plist SHA-256 are **independent retained-candidate acceptance evidence**. The current app does not import that external evidence record and does not display those hashes for operator comparison before scan. Do not invent such an app capability.

The accepted install subject is the exact retained IPA that passed this independent inspection.

## 6. Install exact retained IPA and perform the executable pre-scan rendezvous

Install the exact accepted retained IPA on the intended iPhone 12 / iOS 27 without rebuilding or substituting another archive/export.

Before any Bluetooth scan, launch that exact install and require the package-owned stationary-preflight Research witness.

The **operator-visible/external rendezvous** must match the tuple the current app actually exposes:

- recipe: `ES80-FINGERPRINT-v1`;
- canonical build identifier;
- exact source commit SHA; and
- exact build-instance ID.

The app must present the package-owned private Research state (`PRIVATE RESEARCH BUILD` / `Runtime provenance ready`, or the exact accepted equivalent) and the coordinator must report physical procedure permitted for that instance.

This visible rendezvous is not a caller assertion. Reaching it depends on `researchAdmissionForCurrentApplication()` succeeding inside the package. The package internally computes the running executable and raw Info.plist hashes as part of runtime identity construction before it can mint the Research admission, but the current UI does **not** externally compare those hashes to the retained candidate record.

Therefore:

- independently inspected executable/raw-Info.plist hashes remain in the retained-candidate acceptance rung above;
- the on-device pre-scan rendezvous uses only the exact visible recipe/build/source/build-instance tuple plus successful package Research admission;
- absence of the Research witness, any visible tuple mismatch, any field NO-GO surface, or inability to reach the canonical Research coordinator is **NO-GO / STOP BEFORE SCAN**.

## 7. Final GO Record is external to the frozen source

The TODAY Final GO Record is created only after the signed candidate and intended-device rendezvous are known. It must not require a tracked source edit that would change the already-accepted source SHA.

Retain the record durably in the flagship GitHub acceptance record and/or alongside the accepted private candidate evidence.

It must contain at least:

- decision: `GO`;
- exact accepted source commit SHA;
- exact accepted build identifier;
- exact accepted build-instance ID;
- exact retained IPA SHA-256;
- exact external build-record SHA-256;
- exact field-build evidence-record SHA-256;
- retained executable SHA-256 and raw processed Info.plist SHA-256 from independent candidate inspection;
- procedure version `V14`;
- experiment recipe `ES80-FINGERPRINT-v1`;
- baseline device: iPhone 12 / iOS 27;
- confirmation that the exact retained IPA was installed without rebuild/substitution;
- confirmation that the visible pre-scan recipe/build/source/build-instance tuple matched retained accepted evidence;
- confirmation that package private ResearchAdmission was live and the canonical coordinator permitted the procedure for that exact running build;
- expected output: the exact raw Nembra Capture Share artifact for Experiment One;
- applicable V14 stop/failure conditions; and
- physical result collected: initially `NO`, changing only after the accepted raw capture is preserved.

A Final GO Record cannot use an ancestor SHA, Simulator build, package-only green, stale candidate, self-carried metadata alone, or arbitrary operator assertion.

Release-grade authorization-envelope/trust-root digests are not required fields for this first private Research capture. If later included, they are additional evidence and must not be misrepresented as the authority that enabled the ResearchAdmission lane.

## 8. GO / NO-GO decision

Experiment One is **GO** only when all of these are simultaneously true:

1. one exact flagship source commit containing this directive is frozen and terminal software-accepted;
2. retained app-visible Capture evidence has been inspected, including the required stationary-preflight -> charger-disconnected -> synthetic OFF1 Simulator witness;
3. the exact private physical iOS Release Research candidate was produced from that accepted source through the TODAY wrapper;
4. the exact retained signed IPA/evidence were independently accepted for signing/provisioning/intended-device membership and build provenance, including executable/raw-Info.plist evidence;
5. that exact retained IPA was installed without rebuild/substitution on the intended iPhone 12 / iOS 27;
6. before scan, the app-visible recipe/build/source/build-instance tuple matched the retained accepted candidate;
7. package private ResearchAdmission was live for that exact running build and the canonical coordinator reported the physical procedure permitted;
8. Bluetooth/storage/foreground/integrity preflight was healthy;
9. charger state was freshly declared **Disconnected** and the scooter was stationary for setup; and
10. the durable external TODAY Final GO Record above was complete for those exact subjects.

If any item is missing, stale, queued, failed, substituted, ambiguous, or not executable by the accepted product: **NO-GO / DO NOT RUN**.

## 9. Experiment One after GO

After GO only:

1. Keep setup stationary; charger disconnected; Nembra foreground/unlocked; stock scooter app closed as required by the accepted recipe.
2. Run OFF1 for the package-required >=10-second accepted window.
3. Run ON1 for the package-required >=10-second accepted window.
4. Run OFF2 for the package-required >=10-second accepted window.
5. Run ON2 for the package-required >=10-second accepted window.
6. Accept only one deterministic repeated correlated CoreBluetooth target; otherwise stop.
7. Explicitly confirm that exact correlated target.
8. Perform accepted passive discover/read/subscribe acquisition only. Never issue unknown characteristic writes or scooter commands.
9. Require accepted finite-acquisition Ready.
10. Preserve at least 60 seconds of accepted monotonic observation after Ready.
11. Finish only through exact Horizon/queue chronology and immutable seal/integrity acceptance.
12. Complete interaction while stationary and share the exact raw Capture artifact unchanged.
13. Preserve that first accepted raw artifact before any derived analysis or next experiment.

Any foreground loss, chronology failure, continuity/integrity failure, authority change, build-rendezvous mismatch, export failure, correlation ambiguity, or other accepted stop condition invalidates completion. Preserve only legitimate evidence; never manufacture a successful artifact.

## 10. After the first accepted artifact

Once the first accepted raw physical ES80 artifact is preserved, retire this special TODAY override as appropriate and return release-grade authorization/trust-root hardening to the normal closure graph.

No physical identity, protocol field, telemetry semantic, command acknowledgement, battery/current/power/speed meaning, or scooter capability becomes verified merely because this directive authorized the measuring instrument to collect passive evidence.
