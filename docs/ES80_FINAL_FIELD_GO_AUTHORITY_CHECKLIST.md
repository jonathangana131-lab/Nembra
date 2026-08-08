# ES80 Final Field GO Authority Checklist — V14

Status: **NO-GO — this checklist does not authorize Physical Experiment One.**

This checklist is the final authority bridge between the accepted Nembra Capture software instrument and the deliberate `GO` edit in `docs/ES80_PHYSICAL_CAPTURE_RUNBOOK.md`. It exists to keep the final field decision from collapsing several independent authority layers into one Boolean, one signed file, one passing workflow, or one operator action.

Nothing in this file changes package field policy, configures a production trust root, proves an IPA is installed, or permits CoreBluetooth field construction.

## Required authority chain

Physical Experiment One may move toward `GO` only when the final composed product proves this entire chain on one exact accepted lineage:

1. **Exact composed software accepted**
   - Name one exact 40-hex flagship commit.
   - The trusted Xcode 27 package/app/UI/provenance gate for that exact commit must be terminal success. Queued, skipped, cancelled, in-progress, ancestor, child-PR, resolver-only, or tree-similar evidence is not acceptance.
   - Inspect the retained QA artifacts and the required Capture screenshots/states. A green test result alone is not visual, accessibility, or runtime acceptance.

2. **Exact signed physical-device candidate produced**
   - Produce the Release field candidate from that exact accepted commit through the canonical signed-field producer.
   - Retain the exact IPA bytes plus canonical external-build, field-build-evidence, and signed-artifact inspection records.
   - Verify signing identity, provisioning profile, effective entitlements, intended-device authorization, exact recipe marker, exact build/runtime tuple, executable hash, Info.plist hash, and retained IPA hash through the canonical inspector.
   - Production output must be failure-atomic/no-replace. A partial producer directory or failed build is not a field candidate.

3. **Independent external authorization issued for those exact subjects**
   - Independently review the retained field evidence; do not trust the IPA's self-description or caller-constructed JSON as authority.
   - Establish the external signing keypair outside the app/repository. The private key never enters Nembra source, app resources, CI logs, capture artifacts, or Git history.
   - Pin only the deliberately reviewed public trust root in the product.
   - The signed authorization envelope must bind the exact accepted evidence subjects required by the canonical verifier. Any byte/identity mismatch fails closed.

4. **Package mints non-forgeable `VerifiedAdmission`**
   - Verification of the independently signed exact authorization must succeed through the canonical package verifier.
   - Only that verified path may mint `PassiveBluetoothExperimentOneFieldExecutionGate.VerifiedAdmission`.
   - A Boolean, launch argument, environment variable, preference, Info.plist marker, raw envelope, parsed JSON object, caller-supplied digest, or UI state cannot substitute for `VerifiedAdmission`.

5. **Installed app consumes the admission-bearing factory**
   - The final Nembra app must deliberately consume the verified admission through the admission-bearing ES80 construction path.
   - The legacy zero-argument `makeAuthorizedES80()` path remains permanently fail-closed and must never become a back door when field policy changes.
   - App wiring must preserve exact runtime/build-instance rendezvous with the accepted signed field evidence before live controller construction.

6. **Separate final package field-execution policy is deliberately GO**
   - `PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure` must be changed to GO only in the deliberate final field-authorization change.
   - The admission-bearing factory must require both the non-forgeable `VerifiedAdmission` **and** this separate final package GO before constructing the live `ForegroundCoreBluetoothCaptureController`.
   - Valid signed evidence alone is insufficient. Package GO alone is insufficient.

7. **Physical runbook records the same exact authority**
   - In the same accepted final field lineage, update `docs/ES80_PHYSICAL_CAPTURE_RUNBOOK.md` from `NO-GO` to `GO`.
   - The runbook must name the exact accepted build/commit, signed IPA identity/digest, independent authorization subject, package field-GO state, procedure version, recipe, expected capture artifact, and stop/failure conditions.
   - The runbook must not authorize an ancestor SHA or a different IPA/build instance from the one admitted by the installed app.

Only after all seven layers are true on the final composed candidate may the first stationary/passive ES80 procedure be performed.

## Final GO record — intentionally blank while NO-GO

Do not populate these fields with placeholders that look authoritative. Fill them only in the final accepted field-authorization change.

- Exact flagship commit: **NOT YET AUTHORIZED**
- Terminal trusted exact-head Xcode 27 run/job: **NOT YET AUTHORIZED**
- Retained QA artifact/screenshot review: **NOT YET ACCEPTED**
- Signed IPA SHA-256: **NOT YET AUTHORIZED**
- External-build record SHA-256: **NOT YET AUTHORIZED**
- Canonical field-build-evidence record SHA-256: **NOT YET AUTHORIZED**
- Signed-artifact inspection subject: **NOT YET AUTHORIZED**
- Independent authorization envelope/payload subject: **NOT YET AUTHORIZED**
- Reviewed production public trust root: **NOT YET CONFIGURED / ACCEPTED**
- Package `VerifiedAdmission` subject: **NOT YET AUTHORIZED**
- Installed app admission-bearing construction path: **NOT YET ACCEPTED**
- Package field-execution policy: **NO-GO**
- Physical runbook state: **NO-GO**
- Procedure version: **V14 / NOT YET AUTHORIZED**
- Experiment recipe: **ES80-FINGERPRINT-v1 candidate; final field authority not yet issued**
- Baseline device: iPhone 12 / iOS 27
- Physical result collected: **NO**

## Fail-closed review questions

Before any final `GO` review, answer every question from durable evidence rather than intent:

- Is the accepted Xcode result for the exact final flagship SHA, not an ancestor or child PR?
- Were the real retained QA artifacts and required Capture screenshots inspected after the final composition settled?
- Are the retained IPA bytes exactly the bytes named by the canonical field evidence and independent authorization?
- Was the intended physical iPhone verified without persisting its UDID into public evidence?
- Does the installed runtime/build-instance identity rendezvous with the independently authorized signed candidate?
- Is the production public key deliberately reviewed and pinned while the corresponding private key remains external?
- Can any caller construct or synthesize the authority object consumed by the live factory without successful canonical signature/evidence verification? If yes, remain NO-GO.
- Can the legacy zero-argument factory construct live CoreBluetooth after the final package gate changes? If yes, remain NO-GO.
- Can a valid `VerifiedAdmission` construct live CoreBluetooth while the separate package field policy is NO-GO? If yes, remain NO-GO.
- Can package GO construct live CoreBluetooth without a verified admission? If yes, remain NO-GO.
- Does the runbook name the same exact build, IPA/evidence subjects, recipe, and package policy that the installed app actually consumes? If no, remain NO-GO.
- Is any application characteristic-value command/write path being introduced or relied upon for Experiment One? If yes, remain NO-GO and re-review scope.

## Experiment boundary after GO

The first accepted ES80 experiment remains the smallest passive fingerprint experiment defined by the physical runbook:

- stationary setup and target correlation;
- deterministic `OFF1 -> ON1 -> OFF2 -> ON2` repeated full-peripheral-identity correlation;
- explicit operator confirmation of the correlated target;
- discovery/read/subscribe only under accepted passive policy; no random characteristic writes;
- accepted finite-acquisition `Ready`;
- at least 60 seconds of authoritative monotonic post-Ready observation;
- exact Horizon/queue/freeze/seal/integrity completion;
- direct Share of the immutable capture artifact;
- stop immediately on any authority, foreground, chronology, horizon, integrity, identity, or safety failure.

A successful software authorization chain does not prove physical ES80 identity, GATT/Tuya/DP semantics, battery, voltage, current, power, speed, throttle, regen, command acknowledgement, or any other telemetry meaning. Those claims require the resulting physical evidence ladder.

## Current conclusion

**NO-GO.** The software closure spine may continue to harden and converge, but this checklist intentionally contains no accepted physical field record. Final physical authorization requires the exact accepted signed candidate, independent external authorization, non-forgeable verified admission, admission-bearing app wiring, separate package GO, and the matching deliberate physical-runbook GO record.