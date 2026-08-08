# ES80 TODAY Research Authorization Contract

Status: TODAY field-ready execution contract for the first private stationary passive ES80 artifact. This narrows the first-data unlock only; it does not replace the full public-release P-256 authorization design.

## Goal

Permit exactly one deliberately produced, signed developer/research build to execute recipe `ES80-FINGERPRINT-v1` after the final composed software head earns terminal exact-head Xcode 27 acceptance.

This is build/procedure authority only. It does not establish ES80 identity, GATT/Tuya/DP/telemetry semantics, command acknowledgement, or any application characteristic write authority.

## Required properties

The TODAY research path MUST be all of the following:

1. **Build-time and mechanically identifiable.** Research authorization must be present because the exact source/build was deliberately produced as an ES80 research field build, not because a user flipped a Settings preference, launch argument, environment variable, remote flag, or imported JSON file.
2. **Recipe-bound.** It authorizes only `ES80-FINGERPRINT-v1` and must fail closed for every other recipe identifier.
3. **Exact-build-bound.** The runbook must name the exact accepted source SHA and exact signed installable SHA-256. The installed build must carry the existing signed recipe/build provenance and must be produced by the canonical signed-field producer.
4. **Research-only.** Standard/App Store/general Release builds remain NO-GO. The full production P-256 trust-root path remains unchanged and can be completed after the first artifact.
5. **Package-owned capability.** App UI must not be able to manufacture physical authority with a Boolean. The live coordinator construction seam must still require a package-owned admission capability.
6. **Stationary + charger-disconnected preflight remains mandatory.** Research authorization cannot bypass the app's explicit charger-state declaration or the package setup requirements.
7. **Explicit operator action remains mandatory.** Authorization must not auto-start scanning/capture on launch.
8. **No application characteristic writes.** The research path may instantiate only the existing passive/read-only Experiment One controller. Any write/command path remains unauthorized.
9. **Deterministic target correlation remains mandatory.** Research authorization does not weaken target-correlation/rediscovery rules.
10. **Failure is closed.** Missing/wrong build marker, wrong recipe, malformed build provenance, failed exact-head acceptance, or inability to prove the installed signed build means NO-GO.

## Preferred implementation shape

Use a distinct package-owned `ResearchAdmission` (or equivalent) with no public initializer. Mint it only from a build-time research authority that is compiled into the dedicated research build and is mechanically bound to `ES80-FINGERPRINT-v1`.

Do **not** overload `permitsPhysicalProcedure` into a globally true Boolean for all builds. Prefer an admission-bearing construction API so the ordinary zero-argument `makeAuthorizedES80()` remains permanently fail-closed.

The app's dedicated research launch route should obtain the research admission through one explicit package API and pass it into a research-only `makeAuthorizedES80(researchAdmission:)` overload. That overload may instantiate only the existing passive Experiment One coordinator.

If the implementation uses a signed-bundle build marker as one ingredient, it must not be the sole authority. The package must also require the dedicated research-build code path/capability, and the runbook must bind the exact signed installable digest. Arbitrary Info.plist edits, preferences, environment variables, launch arguments, or imported files must not mint admission.

## Acceptance ladder

Before first physical use:

1. Freeze the final composed software head.
2. Terminal trusted Xcode 27 package/app/UI/provenance run succeeds on that exact head.
3. Primary-path retained screenshots/artifacts are inspected for true blockers only.
4. Produce the exact signed developer/research build with the canonical producer.
5. Verify code signing, intended-device provisioning, recipe marker, executable + Info.plist/build provenance, and retain the exact installable SHA-256.
6. Verify the research admission is available only in the dedicated research build and wrong/missing recipe remains NO-GO.
7. Verify the ordinary/standard build remains mechanically NO-GO.
8. Record exact source SHA, installable SHA-256, recipe, procedure version, charger/stationary requirements, expected output artifact, and stop conditions in the runbook.
9. Perform only the stationary, charger-disconnected, passive/read-only Experiment One procedure.
10. Preserve the resulting raw artifact unchanged and immediately return to the full post-capture hardening backlog.

## TODAY blocker classification

A defect in this authorization lane blocks TODAY only if it can make the intended research build impossible to authorize/install/run safely, can accidentally authorize a non-research build/recipe, can bypass stationary/charger preflight, can create a write-capable path, or can make the runbook unable to bind the exact installed build.

Release-grade external-signing ceremony, hostile same-UID filesystem attacks, generalized public distribution, and unrelated analyzer hardening remain POST-CAPTURE unless they reproduce on the normal private research path.
