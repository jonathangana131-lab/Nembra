# ES80 Physical GO — Two-Key Field Authority Contract

Status: **NO-GO — PHYSICAL EXPERIMENT ONE MUST NOT RUN.**

Feature: Nembra Capture / ES80 physical truth  
Procedure family: V14 / `ES80-FINGERPRINT-v1`

This document is a narrow V14 authority addendum to `ES80_PHYSICAL_CAPTURE_RUNBOOK.md`. It records the live package architecture after the current closure spine separated signed field admission from the deliberate final repository/package GO policy.

It does **not** authorize a physical experiment. If this document conflicts with a later accepted package implementation, exact final build evidence, or the deliberately edited physical runbook GO record, the live accepted implementation and final runbook record win.

## Why two independent keys are required

Live-controller construction now has two independent prerequisites:

1. **Verified signed-field admission** — the package must cryptographically verify the externally signed field authorization and convert that verifier-owned result into `PassiveBluetoothExperimentOneFieldExecutionGate.VerifiedAdmission`.
2. **Deliberate final field policy GO** — `PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure` must separately be true in the exact accepted final composition.

Either key alone is insufficient.

A valid signed authorization must not make the repository field policy GO automatically. Likewise, a future deliberate field-policy GO must not allow a caller that lacks a package-minted verified admission to construct live CoreBluetooth authority.

## Canonical construction boundary

The current package contract is intentionally asymmetric:

- `PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80()` is the legacy/current app construction seam and is **permanently fail-closed**. A future GO edit must not turn this zero-argument method into a live path.
- `PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80(verifiedAdmission:)` is the only intended future live ES80 construction seam.
- The admission-bearing overload must check final package field policy before creating the live CoreBluetooth controller.
- `VerifiedAdmission` must remain non-forgeable by ordinary app/UI callers. No public/memberwise initializer, Boolean, preference, launch argument, Info.plist marker, local setting, or caller-selected digest may substitute for the package verifier.

Therefore the physical authority chain is:

`exact retained signed-device bytes`
→ `canonical field-build evidence`
→ `independently signed authorization`
→ `package signature/evidence verification`
→ `VerifiedAdmission`
→ **AND** `final package field policy GO`
→ admission-bearing `makeAuthorizedES80(verifiedAdmission:)`
→ live passive CoreBluetooth coordinator.

No earlier node in that chain is physical permission by itself.

## Exact-subject binding that admission must preserve

The verified admission is only meaningful when its verified authorization remains bound to the accepted exact subjects, including the applicable current contract for:

- build identifier;
- build-instance identity;
- exact source commit SHA;
- retained signed-installable IPA SHA-256;
- canonical field-build evidence record SHA-256;
- authorization payload SHA-256;
- exact external build record and its executable / Info.plist digests;
- exact recipe `ES80-FINGERPRINT-v1`;
- exact accepted procedure version;
- required installable kind and signing/provisioning evidence.

These are build/procedure facts. They do not authenticate the scooter or establish any GATT/Tuya/telemetry semantics.

## Runtime and app wiring requirement before GO

The final field build must not merely contain the two-key package APIs. Before physical GO, the exact accepted app composition must mechanically consume the verified authorization and pass the resulting `VerifiedAdmission` to the admission-bearing construction seam.

A Release launch recipe marker may route the user to Capture, but routing is not authority. The launch marker must never unlock Bluetooth transport or mint admission.

The final app-visible preflight must fail closed unless all of the following are true for the same accepted composition:

- exact runtime/build identity matches the independently accepted signed-device subject;
- the signed field authorization verifies under the reviewed, pinned public trust root;
- the verified authorization is admitted by package policy into a non-forgeable `VerifiedAdmission`;
- final package field policy is deliberately GO;
- the live coordinator is created only through `makeAuthorizedES80(verifiedAdmission:)`;
- the physical runbook GO record names the same exact build, artifact authority, recipe, procedure, and field-policy state.

## What must remain impossible

The following must remain mechanically unable to authorize the first physical ES80 experiment:

- calling zero-argument `makeAuthorizedES80()`;
- changing a UI Boolean;
- changing a local preference or UserDefaults value;
- supplying a launch argument or environment variable;
- adding or editing the Capture routing Info.plist marker;
- parsing unsigned or self-carried JSON;
- supplying an arbitrary digest that happens to equal a retained digest;
- possessing only `VerifiedAdmission` while final package policy is NO-GO;
- flipping only final package policy while no verified admission is supplied;
- using an ancestor/child/package-only/Simulator green instead of exact final acceptance;
- treating code-signing success, provisioning success, installation success, or app launch alone as authorization;
- treating a CoreBluetooth connection/write-capability/callback as physical scooter acknowledgement.

## Required final GO record

When the physical runbook is eventually changed to `GO`, that same acceptance change must record enough information to prove both keys and their exact subjects. At minimum:

- accepted exact final commit;
- retained signed-installable artifact identity and SHA-256;
- canonical field-build evidence identity/digest;
- independently signed authorization identity/payload digest;
- reviewed public trust-root identity/fingerprint or other accepted immutable key identifier;
- proof/result that exact authorization verification produced the admission used by the app;
- package final field-policy state = GO;
- proof that live app wiring uses the admission-bearing construction seam, not the legacy zero-argument seam;
- exact recipe and procedure version;
- baseline device/runtime;
- expected exported Capture artifact;
- stop/failure conditions;
- terminal exact-head software/app/UI/provenance acceptance and completed visual/accessibility/performance review.

The private signing key must never enter the app or repository.

## Current closure state

At the time this contract was added, the current flagship package already preserves the two-key construction shape, while the physical procedure remains intentionally locked. The repository trust root/final GO state and final accepted field wiring are not treated here as completed physical authority.

**PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN.**
