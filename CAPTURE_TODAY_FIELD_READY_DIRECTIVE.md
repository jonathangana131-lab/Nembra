# CAPTURE TODAY FIELD-READY DIRECTIVE — V14

Status: **ACTIVE TODAY OVERRIDE / PHYSICAL EXPERIMENT ONE REMAINS NO-GO UNTIL THE FINAL RECORD BELOW IS COMPLETE.**

Feature: **Nembra Capture / first private stationary passive ES80 artifact**

This directive restores the TODAY authority referenced by the flagship Capture closure and resolves one documentation conflict without weakening any physical-safety, exact-build, provenance, runtime, or read-only requirement.

The repository contains both a release-grade signed-authorization design and a narrower private Research-build authority deliberately implemented to collect the first passive ES80 artifact. For the first TODAY artifact, this directive is authoritative when older field documents accidentally require the release-grade lane.

## 1. Narrow scope and precedence

For **only the first private stationary passive `ES80-FINGERPRINT-v1` artifact**, this directive supersedes older wording in:

- `docs/ES80_PHYSICAL_CAPTURE_RUNBOOK.md`;
- `docs/ES80_SIGNED_FIELD_CANDIDATE_PRODUCTION.md`;
- `docs/ES80_FIELD_AUTHORIZATION_OFFLINE_SIGNING.md`;

where that wording requires, before the first artifact:

- a configured release-grade P-256 package trust root;
- an externally signed schema-v2 `VerifiedAdmission` envelope;
- the release/global `PassiveBluetoothExperimentOneFieldExecutionGate.status` to change from its default NO-GO value; or
- a post-build tracked runbook edit that must somehow become the same Git source SHA already embedded in the signed artifact it names.

Those requirements remain valid release-grade/future authority work. They are **not TODAY prerequisites** unless a later accepted directive explicitly promotes them.

Everything else in the V14 physical runbook remains in force, especially stationary setup, charger-disconnected declaration, foreground integrity, deterministic OFF1 -> ON1 -> OFF2 -> ON2 correlation, explicit target confirmation, passive/read-only GATT behavior, accepted Ready/Horizon chronology, >=60 seconds post-Ready monotonic observation, immutable seal, integrity, exact Share artifact, and all stop/failure conditions.

This directive never authorizes application characteristic writes or physical command research.

## 2. TODAY package authority is the private ResearchAdmission lane

The accepted package/app architecture intentionally has two separate authority lanes.

### Release-grade lane — not required for the first TODAY artifact

`PassiveBluetoothCaptureVerifiedFieldAuthorization` -> `VerifiedAdmission` -> release-grade canonical construction remains independently signed/trust-root-gated and fail-closed while its production trust root is unconfigured.

Do not pull this lane into TODAY merely to make the first passive capture possible.

### TODAY private Research lane — required

The first artifact uses:

`makeResearchAuthorizedES80ForCurrentApplication()`
-> package-owned `researchAdmissionForCurrentApplication()`
-> module-private `ResearchAdmission`
-> canonical live Research coordinator.

That admission is mechanically available only when the running app is:

- physical iOS;
- non-Simulator;
- non-Debug;
- compiled with `NEMBRA_ES80_TODAY_RESEARCH` by the narrow TODAY field wrapper;
- carrying the exact canonical `ES80-FINGERPRINT-v1` recipe in the processed Info.plist;
- carrying producer-shaped build identifier, build-instance ID, and source SHA matching the runtime identity;
- using canonical build identifier `Capture Build V14-<first 12 source SHA>`;
- bound by the runtime identity reader to the running executable and raw processed Info.plist evidence.

`ResearchAdmission` is not a caller-created Boolean, imported JSON token, UserDefaults preference, launch argument, target UUID, or UI flag. It is module-private package capability.

The coordinator permits experiment mutation only when both are true:

1. it owns the package-created canonical live CoreBluetooth controller; and
2. its instance field status is the ResearchAdmission-produced `.goPrivateResearchBuild(build)` state.

Every OFF/ON, target-confirmation/rediscovery, connection, and Horizon-finalization mutation remains guarded by coordinator execution authority.

This is build/procedure authority only. It does not authenticate the scooter, prove RF completeness, assign GATT/Tuya/DP semantics, or make telemetry physical truth.

## 3. TODAY source freeze and software acceptance

Before producing the private field IPA, freeze one exact flagship source commit that contains the complete app-visible Capture composition and this directive.

That unchanged exact source must earn all applicable terminal acceptance, including:

- immutable exact-head resolution;
- NembraCore and NembraBluetoothCapture validation required by the flagship gate;
- app build/test on Xcode 27;
- iPhone 12 / iOS 27 Simulator runtime witness for the accepted Capture flow;
- retained screenshot/log/xcresult/build-evidence inspection required by open flagship review threads;
- exact build/provenance transport validation;
- all current portable Capture custody/authority gates;
- no application characteristic-value write authority.

Queued, pending, skipped, cancelled, sibling, or ancestor evidence is not acceptance.

Simulator remains software evidence only.

## 4. Exact private signed Research Field Build

Only after the frozen source earns terminal software acceptance may the private signing surface run:

`scripts/ci/xcode27_today_research_field_candidate.sh`

using the real private signing inputs required by the canonical producer, including the real Development Team, accepted ExportOptions plist, and private intended-device input.

The producer must build from the exact accepted source SHA and retain the exact exported signed IPA plus canonical evidence. At minimum the accepted field candidate must preserve/bind:

- source commit SHA;
- build identifier;
- build-instance ID;
- executable SHA-256;
- raw processed Info.plist SHA-256;
- `ES80-FINGERPRINT-v1` recipe;
- procedure version `V14`;
- exact signed-installable IPA SHA-256;
- signing/provisioning/intended-device inspection evidence.

Producer success is evidence, not automatic physical GO.

## 5. Independent field-candidate acceptance

Before installation or scan:

1. independently inspect the exact retained IPA and canonical evidence;
2. verify signing/provisioning and intended-device membership under the accepted private field policy;
3. independently recompute the exact retained IPA and evidence digests required by the accepted candidate contract;
4. verify the retained build/source/build-instance/recipe/executable/raw-Info.plist tuple is internally consistent;
5. reject substitution, re-export, rebuild, or stale/ancestor artifacts.

The accepted install subject is the exact retained IPA from that accepted candidate. Installing a rebuild does not transfer acceptance.

## 6. Install exact retained IPA and rendezvous before Bluetooth scan

Install the exact accepted retained IPA on the intended iPhone 12 / iOS 27 device without rebuilding or substituting another archive/export.

Before any Bluetooth scan, the app must mechanically rendezvous the running Research build against the retained accepted build evidence. The compared tuple must include the accepted build identifier, build-instance ID, source SHA, executable SHA-256, and raw processed Info.plist SHA-256.

Any mismatch is **NO-GO**.

The app must also prove that the package private ResearchAdmission is actually available for that exact running build. A generic launch-mode request or visible Capture screen is not enough.

## 7. Final GO Record is post-build and external to source

The TODAY Final GO Record must be durable, exact, and retained **after** the signed candidate is known. It must not require editing the tracked source tree and then pretending the previously signed artifact came from the new Git SHA.

The record may be retained in the flagship GitHub acceptance thread and/or alongside the accepted private candidate evidence, provided it is immutable enough for later audit and names the exact subjects below.

It must contain at least:

- decision: `GO`;
- exact accepted source commit SHA;
- exact accepted build identifier;
- exact accepted build-instance ID;
- exact retained IPA SHA-256;
- exact external build-record SHA-256;
- exact field-build evidence-record SHA-256;
- procedure version `V14`;
- experiment recipe `ES80-FINGERPRINT-v1`;
- baseline device: iPhone 12 / iOS 27;
- confirmation that the exact retained IPA was installed without rebuild/substitution;
- confirmation that pre-scan runtime rendezvous matched the accepted tuple;
- confirmation that the package ResearchAdmission is live for that exact running build;
- expected output: the exact raw Nembra Capture Share artifact for Experiment One;
- exact applicable stop/failure conditions from the V14 runbook and this directive;
- physical result collected: initially `NO`, changing only after the accepted capture is actually preserved.

A Final GO Record cannot be filled with an ancestor SHA, Simulator build, package-only green, stale candidate, self-carried metadata alone, or arbitrary operator assertion.

The release-grade authorization-envelope/trust-root digests are not required fields for this first TODAY private Research capture. If they are later included, they are additional evidence and must not be misrepresented as having authorized a build that actually used the separate ResearchAdmission lane.

## 8. GO / NO-GO decision

The first physical ES80 Experiment One is **GO** only when all of these are simultaneously true:

1. one exact flagship source commit is frozen and terminal software-accepted;
2. its app-visible Capture runtime evidence has been inspected, including the required stationary-preflight -> charger-disconnected -> synthetic OFF1 Simulator witness;
3. the exact private physical iOS Release Research candidate was produced from that source through the TODAY wrapper;
4. the exact retained signed IPA/evidence were independently accepted for signing/provisioning/intended-device/build provenance;
5. that exact retained IPA was installed without rebuild/substitution on the intended iPhone 12 / iOS 27;
6. pre-scan runtime rendezvous exactly matched the retained build/source/build-instance/executable/raw-Info.plist evidence;
7. package private ResearchAdmission is live for that exact running build and the canonical coordinator reports physical procedure permitted;
8. Bluetooth/storage/foreground/integrity preflight is healthy;
9. charger state is freshly declared **Disconnected** for this experiment and the scooter is stationary for setup;
10. the durable TODAY Final GO Record above is complete for those exact subjects.

If any item is missing, stale, queued, failed, substituted, or ambiguous: **NO-GO / DO NOT RUN**.

## 9. Experiment One procedure after GO

After GO only:

1. Keep setup stationary; keep the charger disconnected; keep Nembra foreground/unlocked; keep the stock scooter app closed as required by the accepted recipe.
2. Run OFF1 for the package-required >=10-second accepted window.
3. Run ON1 for the package-required >=10-second accepted window.
4. Run OFF2 for the package-required >=10-second accepted window.
5. Run ON2 for the package-required >=10-second accepted window.
6. Accept only one deterministic repeated correlated CoreBluetooth target under the package contract; otherwise stop.
7. Explicitly confirm that exact correlated target.
8. Perform accepted passive discover/read/subscribe acquisition only. Never issue unknown characteristic writes.
9. Require accepted finite-acquisition Ready.
10. Preserve at least 60 seconds of accepted monotonic observation after Ready.
11. Finish only through exact Horizon/queue chronology and immutable seal/integrity acceptance.
12. Safely complete interaction while stationary and share the exact raw Capture artifact unchanged.
13. Preserve that first accepted raw artifact before any derived analysis or next experiment.

Any foreground loss, chronology failure, continuity/integrity failure, authority change, build-rendezvous mismatch, export failure, correlation ambiguity, or other accepted stop condition invalidates completion. Preserve only legitimate evidence; never manufacture a successful artifact.

## 10. After the first artifact

Once the first accepted raw physical ES80 artifact is preserved, retire this special TODAY override as appropriate and return release-grade authorization/trust-root hardening to the normal closure graph.

No physical identity, protocol field, telemetry semantic, command acknowledgement, battery/current/power/speed meaning, or scooter capability becomes verified merely because this directive authorized the measurement instrument to collect passive evidence.
