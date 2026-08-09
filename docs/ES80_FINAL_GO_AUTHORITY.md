# ES80 Experiment One Final GO Authority — V14

Status: **NO-GO — THIS DOCUMENT DOES NOT AUTHORIZE PHYSICAL EXPERIMENT ONE.**

This document closes one field-release authority contradiction in the current V14 Capture procedure: a signed build cannot be required to include a post-build tracked runbook edit that names its own final Git commit. Nembra build provenance binds the exact Git `SOURCE_SHA`; changing a tracked runbook after signing changes that SHA and makes the already-signed artifact ancestor evidence.

The final physical GO authority must therefore be **post-build and external to the repository source tree**. It may bind exact repository source, but it must not mutate the source it is authorizing.

This document changes no BLE behavior, command authority, telemetry semantics, target identity claim, signed artifact, trust root, or physical status. Experiment One remains NO-GO until every gate below is deliberately closed.

## Non-self-referential authority model

The authoritative subjects are separated by phase.

### 1. Procedure source — fixed before the field build

The accepted source commit contains:

- the V14 physical procedure/runbook;
- `PassiveBluetoothCaptureExternalBuildRecord.requiredProcedureVersion == "V14"`;
- the accepted `ES80-FINGERPRINT-v1` recipe contract;
- the package-owned field-verification code;
- the reviewed P-256 **public** trust root used by `PassiveBluetoothCaptureFieldAuthorizationVerifier`.

The procedure is source material. It is not edited after the exact field build is produced merely to insert that build's digest or SHA.

### 2. Authority key — established before final exact-source acceptance

The production P-256 authority private key is created and controlled outside the repository. It never enters the app, repository, normal CI artifacts, logs, or caller-controlled configuration.

Before the final field-source SHA is frozen:

1. establish external private-key custody;
2. derive and independently review the corresponding uncompressed X9.63 public key;
3. pin only that reviewed public key in `PassiveBluetoothCaptureFieldAuthorizationTrustAnchor.publicKeyX963Representation` through a reviewed source change;
4. record/review the public-key X9.63 SHA-256;
5. run final exact-head package/app/Xcode acceptance on the resulting source SHA.

The current flagship still has a `nil` trust root, so this prerequisite is not yet satisfied.

### 3. Exact signed field artifact — produced from the frozen source

Only after the trust-root-bearing source SHA has terminal exact-head software acceptance may the private signing surface produce the Research Field Build.

The retained signed IPA and evidence must come from that exact source SHA and the accepted recipe. The canonical producer/inspector must retain and independently verify at least the exact facts already required by the V14 field lineage, including:

- build identifier;
- build-instance ID;
- source commit SHA;
- executable SHA-256;
- raw processed Info.plist SHA-256;
- `ES80-FINGERPRINT-v1` recipe;
- procedure version `V14`;
- signed-installable IPA SHA-256;
- signing/provisioning/intended-device acceptance evidence.

Installing or rebuilding a different artifact does not transfer authority.

### 4. External signed authorization envelope — post-build Final GO authority subject

After the exact retained signed IPA and its canonical evidence have been independently accepted, the external authority may issue the schema-v2 signed authorization envelope.

That envelope is non-self-referential because it is created **after** the build and remains outside the repository. It signs the exact authorization payload whose subject digests bind:

- the exact schema-v3 external build-record bytes; and
- the exact canonical field-build evidence-record bytes.

The external build record in turn binds the exact `sourceCommitSHA`, `procedureVersion == V14`, and `experimentRecipeID == ES80-FINGERPRINT-v1`. Because the source SHA commits the repository tree, this also identifies the exact procedure source that was frozen before build production.

A signature-valid envelope is still not enough by itself. The installed app must verify it through the package-pinned public trust root and exact runtime build rendezvous, and all physical safety/preflight gates must remain satisfied.

## Final GO Record

For V14 Experiment One, the **Final GO Record is a retained external acceptance record for the exact signed authorization envelope and its exact accepted subjects**. It must not be implemented as a post-build edit to the repository source it authorizes.

The retained Final GO Record must identify, directly or by exact bound subject bytes/digests:

- decision: `GO`;
- exact accepted source commit SHA;
- exact accepted build identifier and build-instance ID;
- exact retained IPA SHA-256;
- exact external build-record SHA-256;
- exact field-build evidence-record SHA-256;
- exact authorization payload SHA-256;
- exact authorization envelope SHA-256;
- reviewed authority public-key X9.63 SHA-256;
- procedure version `V14`;
- experiment recipe `ES80-FINGERPRINT-v1`;
- baseline device: iPhone 12 / iOS 27;
- expected Capture Share artifact contract;
- exact stop/failure conditions from the accepted V14 physical procedure;
- evidence that the exact retained IPA was installed on the intended device without rebuilding/substitution;
- evidence that the running app's build/source/build-instance/executable/raw-Info.plist tuple matches the accepted external build record before any Bluetooth scan.

The existing signed authorization envelope already cryptographically binds the two exact evidence subjects used by the package verifier. A release/field handoff may retain an additional human-readable acceptance summary, but that summary is descriptive unless it is independently bound to the exact envelope/subject digests above. It cannot replace package verification or mint authority from caller-supplied text.

## Physical GO decision

Physical Experiment One is `GO` only when **all** of these are true at the same time:

1. the final source commit contains the reviewed production public trust root and accepted V14 procedure/recipe code;
2. terminal exact-head Xcode/package/app/Simulator acceptance exists for that unchanged source SHA;
3. a private Research Field Build is produced from that exact source and recipe;
4. independent signed-IPA inspection accepts signing/provisioning/intended-device membership and exact retained bytes;
5. the exact retained IPA is installed without rebuild/substitution on the intended iPhone 12 / iOS 27 device;
6. pre-scan runtime rendezvous matches build identifier, build-instance, source SHA, executable digest, and raw Info.plist digest to the accepted external record;
7. the external authority signs the exact accepted build/evidence subjects with the private key corresponding to the package-pinned public trust root;
8. the package verifier accepts that exact envelope for the running application and the package-owned Experiment One field-execution gate reaches its deliberate GO state;
9. Bluetooth/preflight/storage/foreground/stationary/charger-disconnected/recipe requirements pass;
10. the external Final GO Record is retained with the exact envelope/subject identities and accepted V14 stop conditions.

Until all ten are closed: **NO-GO / DO NOT RUN PHYSICAL EXPERIMENT ONE.**

## Experiment One remains passive

Final GO does not authorize protocol exploration by writes. Experiment One remains the accepted passive/read-only sequence:

- setup while stationary;
- charger declared disconnected;
- OFF1 -> ON1 -> OFF2 -> ON2 deterministic correlation under the accepted receipt-time contract;
- explicit confirmation of the uniquely correlated target;
- accepted passive GATT discover/read/subscribe behavior only;
- finite-acquisition Ready;
- at least 60 seconds of accepted monotonic observation after Ready;
- exact Horizon/queue chronology;
- immutable seal/integrity check;
- Share the exact raw Capture artifact unchanged;
- stop/fail closed on any accepted authority, continuity, foreground, chronology, build-rendezvous, storage/export, or safety blocker.

No application characteristic write, writable-property inference, protocol semantic claim, or physical telemetry claim is created by this authority model.

## Required reconciliation before integration

`docs/ES80_PHYSICAL_CAPTURE_RUNBOOK.md` and `docs/ES80_FIELD_AUTHORIZATION_OFFLINE_SIGNING.md` currently contain wording that still expects the definitive tracked runbook itself to be edited to GO after the signed build is known. That wording must be reconciled with this non-self-referential model before physical authorization is considered closed.

In particular, final integrated wording must not require a tracked post-build edit to become the exact source commit already named by the signed artifact it is accepting.

This document is a recovery checkpoint for that reconciliation. It is not a physical GO record and does not change current physical status.
