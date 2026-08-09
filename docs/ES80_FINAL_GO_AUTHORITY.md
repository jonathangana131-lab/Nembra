# ES80 Final GO Authority — Diagnostic Recovery Note

Status: **SUPERSEDED AS TODAY AUTHORITY DESIGN / NO-GO / DO NOT INTEGRATE AS WRITTEN INTO THE FLAGSHIP.**

This recovery note exists to preserve one useful process finding without misrepresenting Nembra's current first-capture authority model.

## Correction

The first revision of this note incorrectly treated the release-grade externally signed `VerifiedAdmission` / package-pinned P-256 trust-root lane as a prerequisite for TODAY's first private ES80 artifact.

Current exact package/app source proves that is false.

Nembra intentionally has two separate authority lanes:

1. **Release-grade authority** — `PassiveBluetoothCaptureVerifiedFieldAuthorization` -> `VerifiedAdmission` -> release-grade canonical factory. This lane uses the externally signed authorization envelope and package-pinned public trust root. It remains fail-closed while that trust root is unconfigured.
2. **TODAY private Research authority** — `makeResearchAuthorizedES80ForCurrentApplication()` -> package-owned `researchAdmissionForCurrentApplication()` -> module-private `ResearchAdmission` -> canonical live Research coordinator. This is the lane intentionally used only to collect the first stationary passive ES80 artifact.

The release-grade trust root is therefore **not a TODAY prerequisite** and must not be pulled into the first-artifact freeze merely because this diagnostic branch once proposed it.

## Current TODAY mechanical authority

The private Research admission is not a user setting or imported authorization document. It can be minted only by package code when the running application is all of the following:

- physical iOS;
- non-Simulator;
- non-Debug;
- compiled with `NEMBRA_ES80_TODAY_RESEARCH` by the narrow TODAY signed-field wrapper;
- carrying the exact canonical `ES80-FINGERPRINT-v1` recipe in the processed app Info.plist;
- carrying producer-shaped build identifier, build-instance ID, and source SHA that exactly match the runtime build identity;
- using the canonical build identifier `Capture Build V14-<first 12 source SHA>`;
- able to produce the runtime executable and raw processed Info.plist identity required by the accepted build rendezvous.

The resulting opaque `ResearchAdmission` is module-private. Its instance status is `.goPrivateResearchBuild(build)`. The coordinator permits experiment mutation only when both that instance-bound status and the package-created canonical live CoreBluetooth controller exist. Every OFF/ON, rediscovery/connect, and Horizon-finalization mutation checks execution authority again.

That is the deliberate TODAY build/procedure authority model. It does not authenticate an ES80, prove RF completeness, establish GATT/Tuya/telemetry semantics, or authorize application characteristic writes.

## Narrow unresolved process question retained by this branch

A separate question remains worth reviewing in the current physical procedure documentation:

`docs/ES80_PHYSICAL_CAPTURE_RUNBOOK.md` contains wording that appears to require a tracked post-build runbook edit naming the accepted exact build/commit while Nembra field-build provenance itself binds exact Git `SOURCE_SHA`.

If that tracked edit is literally required to become the exact source SHA already named by the signed Research artifact, the requirement is self-referential: producing a signed artifact for commit A and then changing the tracked runbook creates commit B, making A ancestor evidence for B.

This is a **procedure/documentation consistency question**, not proof that the TODAY ResearchAdmission implementation is blocked. Resolve it against the current accepted private Research-build procedure before physical GO. Do not solve it by importing release-grade trust-root/envelope work into TODAY unless the accepted field procedure explicitly requires that stronger lane.

A coherent non-self-referential procedure can freeze the source/runbook before the Research build, then retain a post-build external acceptance record that names the already-frozen exact source + exact retained IPA/evidence/runtime-rendezvous facts. Whether that is the intended current V14 Final GO mechanism must be decided by the flagship procedure owner rather than asserted by this recovery branch.

## Current physical status

This branch creates no GO authority.

Physical Experiment One remains **NO-GO / DO NOT RUN** until the actual TODAY ladder is closed, including at minimum:

- terminal exact-head package/app/UI/provenance acceptance on the unchanged flagship source;
- production of the exact private signed `ES80-FINGERPRINT-v1` Research Field Build from that accepted source on the private signing surface;
- independent retained-IPA signing/provisioning/intended-device and provenance inspection;
- installation of that exact retained IPA without rebuild/substitution on the intended iPhone 12 / iOS 27 device;
- successful pre-scan runtime rendezvous to the accepted build/source/build-instance/executable/raw-Info.plist evidence;
- explicit accepted Final GO procedure/record with no source-SHA contradiction;
- charger-disconnected, stationary, foreground-safe passive Experiment One execution only.

This document is a diagnostic recovery checkpoint only. It should be superseded or deleted when the canonical physical runbook is reconciled; it must not become a second competing field procedure.
