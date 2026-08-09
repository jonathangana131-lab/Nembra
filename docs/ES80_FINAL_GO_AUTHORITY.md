# ES80 Experiment One Final GO Authority — V14

Status: **NO-GO — THIS DOCUMENT DOES NOT AUTHORIZE PHYSICAL EXPERIMENT ONE.**

This document closes a source-provenance contradiction without broadening TODAY scope.

Nembra build provenance binds the exact Git `SOURCE_SHA`. Therefore a signed developer/research build cannot be accepted by a required **post-build tracked runbook edit** that names that same build: editing tracked source changes `SOURCE_SHA` and turns the already-signed artifact into ancestor evidence.

The physical GO decision must therefore be **post-build and external to the repository source tree**. It may bind exact repository source and exact signed bytes, but it must not mutate the source it is authorizing.

This model must also preserve the active `CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md`: the first private stationary passive ES80 artifact may use the deliberately compiled, exact-build-bound **Research Field Build** authority. Full external P-256 release authorization remains POST-CAPTURE unless it is independently promoted by a demonstrated TODAY blocker.

Experiment One remains NO-GO until the applicable TODAY gates below are deliberately closed.

## Authority levels

V14 has two separate authority levels. Do not accidentally make the later release threat model a prerequisite for the first private research artifact.

### A. TODAY — Research Field Build authority

This is the authority path for the first private stationary passive `ES80-FINGERPRINT-v1` capture.

The accepted tracked source commit must already contain:

- the V14 physical procedure source;
- exact recipe/build provenance support;
- package-owned Research Field Build admission that is mechanically unavailable to normal builds;
- fail-closed recipe binding to `ES80-FINGERPRINT-v1`;
- deterministic target correlation;
- fresh stationary + charger-disconnected preflight;
- passive/read-only Experiment One behavior with no application characteristic writes;
- exact Share/seal/export integrity requirements.

That source commit is frozen **before** the signed Research Field Build is produced. It is not edited later merely to insert the resulting IPA digest or build-instance identity.

The exact signed Research Field Build and retained evidence must then establish at least:

- build identifier;
- build-instance ID;
- source commit SHA;
- executable SHA-256;
- raw processed Info.plist SHA-256;
- recipe `ES80-FINGERPRINT-v1`;
- procedure version `V14`;
- signed-installable IPA SHA-256;
- signing/provisioning/intended-device acceptance evidence;
- proof that ordinary/non-research builds remain mechanically NO-GO.

Installing or rebuilding a different artifact does not transfer authority.

### B. LATER — release-grade P-256 authority

The repository also contains the stronger external P-256 authorization design:

- externally controlled P-256 private-key custody;
- reviewed public-key pinning in `PassiveBluetoothCaptureFieldAuthorizationTrustAnchor`;
- schema-v2 signed authorization envelope over exact retained evidence subjects;
- package verification against the pinned trust root;
- release-grade anti-tamper/custody hardening.

Under the active TODAY directive, this is **POST-CAPTURE** unless a concrete normal private-research-path defect proves it is required to satisfy one of TODAY's blocking conditions.

If/when the P-256 path is promoted, it follows the same non-self-referential rule: the trust-root-bearing source is frozen before build production; the signed envelope and any release Final GO acceptance record are created externally afterward and never require a tracked post-build source mutation.

## TODAY external Final GO Record

For the first private ES80 artifact, the **Final GO Record is a retained external acceptance record for the exact Research Field Build and the exact procedure source it came from**. It must not be implemented as a post-build edit to the repository source it authorizes.

The retained TODAY Final GO Record must identify, directly or through independently recomputed retained evidence:

- decision: `GO`;
- exact accepted source commit SHA;
- exact accepted build identifier and build-instance ID;
- exact retained IPA SHA-256;
- exact executable SHA-256;
- exact raw processed Info.plist SHA-256;
- exact recipe `ES80-FINGERPRINT-v1`;
- procedure version `V14`;
- baseline device: iPhone 12 / iOS 27;
- evidence that the exact retained IPA was installed on the intended device without rebuilding/substitution;
- evidence that the running app's **visible recipe/build/source/build-instance tuple** matches the retained accepted build evidence before any Bluetooth scan;
- evidence that package-owned Research Field Build admission is present for this exact running build/recipe and ordinary builds remain NO-GO;
- expected Capture Share artifact contract;
- exact stop/failure conditions from the accepted V14 physical procedure.

The executable and raw processed Info.plist hashes remain independently inspected retained-candidate evidence. The current app does not display or externally compare those hashes before scan, and this procedure must not pretend that it does. Package Research admission independently computes those runtime hashes while constructing the running-build identity; the operator-visible rendezvous is the exact recipe/build/source/build-instance tuple defined by `CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md`.

The record is an acceptance/handoff artifact, not a caller-constructible capability. The app still obtains authority only through its package-owned Research Field Build admission and exact runtime provenance checks. Human-readable text cannot mint physical authority.

## TODAY physical GO decision

Physical Experiment One may be `GO` only when **all** of these are true at the same time:

1. terminal trusted exact-head Xcode/package/app/Simulator acceptance exists for one unchanged final source SHA;
2. the primary Capture path is visibly usable at the iPhone 12 / iOS 27 baseline and the required Simulator evidence has been inspected;
3. deterministic OFF1 -> ON1 -> OFF2 -> ON2 correlation remains fail-closed;
4. the Experiment One application path contains no characteristic-value writes/commands;
5. fresh stationary + charger-disconnected preflight is mandatory and cannot be bypassed by the research authority;
6. >=60-second same-authority passive observation, exact Horizon/seal, final Share integrity, and export/analyzer readiness remain accepted;
7. one exact signed developer/research IPA is produced from that frozen source using the canonical producer and independently inspected for signing/provisioning/intended-device membership and exact retained bytes, including executable and raw processed Info.plist digests;
8. that exact retained IPA is installed without rebuild/substitution on the intended iPhone 12 / iOS 27 device;
9. before scan, the app-visible recipe/build identifier/build-instance/source SHA tuple matches the retained accepted build evidence and package-owned Research Field Build admission succeeds for that exact running build; executable/raw-Info.plist digests remain independently inspected candidate evidence rather than a nonexistent visible hash comparison;
10. the package-owned Research Field Build authority admits exactly `ES80-FINGERPRINT-v1`, ordinary builds remain NO-GO, and explicit operator action is still required;
11. Bluetooth/preflight/storage/foreground/stationary/charger-disconnected/recipe requirements pass;
12. the external TODAY Final GO Record is retained for those exact subjects and accepted stop conditions.

Until all twelve are closed: **NO-GO / DO NOT RUN PHYSICAL EXPERIMENT ONE.**

No P-256 production key or pinned public trust root is required merely to satisfy TODAY's first private-research-artifact authority unless a later concrete blocker explicitly promotes that release-grade path.

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

## Source-immutability rule

`docs/ES80_PHYSICAL_CAPTURE_RUNBOOK.md` is tracked procedure source. It must describe the exact accepted procedure and GO prerequisites **before** build production, but it must not require a post-build edit that becomes a different source SHA.

`docs/ES80_FIELD_AUTHORIZATION_OFFLINE_SIGNING.md` documents the later P-256 release boundary. It must not be treated as a TODAY prerequisite while the active field-ready directive classifies that ceremony as POST-CAPTURE.

A future release-authorized flow may retain a stronger external Final GO Record bound to the exact signed P-256 authorization envelope and evidence subjects. That later record obeys the same rule: external post-build acceptance may bind source, but may not mutate the source it authorizes.

This document is procedure/authority source only. It is not a physical GO record and does not change current physical status.
