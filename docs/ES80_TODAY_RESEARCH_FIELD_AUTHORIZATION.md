# ES80 TODAY Research Field Authorization

Status: candidate implementation for `CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md`. This document does **not** itself authorize physical Experiment One.

## Purpose

The first private AOVOPRO ES80 data-unlock run must not wait for the later public-release P-256 threat model, but ordinary Nembra builds must remain mechanically unable to start the physical procedure.

The TODAY research path therefore authorizes only the exact runtime shape already produced by `scripts/ci/xcode27_signed_field_candidate.sh`:

- `NembraCaptureFieldRecipe == ES80-FINGERPRINT-v1` in the running bundle;
- a validated runtime build identity from `Bundle.main`;
- exact running executable SHA-256;
- exact raw running Info.plist SHA-256;
- canonical per-build UUID;
- exact embedded 40-hex source commit;
- build identifier exactly `Capture Build V14-<first 12 hex of embedded source commit>`.

The recipe marker alone is insufficient. Missing/malformed runtime identity, wrong recipe, or a build-label/source mismatch stays NO-GO.

## What cannot authorize the run

The research gate does not read or accept:

- Settings/preferences;
- launch arguments;
- process environment flags;
- caller-provided booleans;
- arbitrary imported unsigned JSON;
- a user-entered build ID or commit SHA.

The ordinary package test host therefore remains NO-GO.

## Canonical construction

`PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80()` becomes live only when the package-owned runtime gate resolves `.researchBuildAuthorized` for the currently executing exact build. Otherwise it throws `fieldExecutionNotAuthorized` before a live CoreBluetooth controller is constructed.

The status-only public coordinator initializer remains inert and cannot create CoreBluetooth authority.

## Safety boundaries unchanged

Research authorization is only build/procedure authority. The following remain mandatory and unchanged:

1. stationary procedure only;
2. charger must be explicitly declared disconnected fresh for each run;
3. explicit operator action is required;
4. OFF1 -> ON1 -> OFF2 -> ON2 target correlation must be deterministic and fail closed on zero/multiple candidates;
5. the correlated full UUID must be rediscovered before connection;
6. Experiment One remains passive/read-only with no application characteristic-value writes/commands;
7. foreground-integrity loss invalidates the active run;
8. final raw capture bytes must cross immutable Horizon before export/analysis;
9. first field GO still requires the final frozen head to earn terminal trusted Xcode 27 acceptance and the exact signed/installable developer build to be produced/inspected.

This authorization does **not** prove physical scooter identity, RF completeness, GATT/Tuya/DP semantics, battery/voltage/current/power/speed meaning, command acknowledgement, or hardware behavior.

## Relationship to release authorization

The existing independently signed P-256 authorization/`VerifiedAdmission` path remains in source and is not weakened. After the first real ES80 artifact is preserved, the temporary research path should be retired or subordinated to that release-grade authority before public distribution.

## Acceptance required before first physical run

This branch may be composed into the TODAY freeze only after:

- focused package tests for research-gate fail-closed behavior pass;
- the final app/package exact head earns terminal trusted Xcode 27 acceptance;
- the exact signed field-candidate IPA is produced from that accepted source;
- signing/provisioning/intended-device/recipe/executable/Info.plist evidence for that exact IPA is inspected;
- the physical runbook names the exact accepted build and preserves no-riding/no-writes/charger-disconnected stop conditions.

Until those steps are complete: **DO NOT RUN PHYSICAL EXPERIMENT ONE.**
