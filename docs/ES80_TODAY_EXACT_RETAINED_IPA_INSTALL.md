# ES80 TODAY Exact Retained IPA Installation Handoff — V14

Status: **SUPPORTING TODAY PROCEDURE ONLY — PHYSICAL EXPERIMENT ONE REMAINS NO-GO.**

Purpose: close the operational handoff between the independently inspected signed Research Field Build and installation on the intended iPhone 12 / iOS 27 without rebuilding, re-exporting, or silently substituting different app bytes.

This document is subordinate to `CAPTURE_TODAY_FIELD_READY_DIRECTIVE.md`, `docs/ES80_TODAY_RESEARCH_AUTHORIZATION_CONTRACT.md`, and `docs/ES80_TODAY_PRIVATE_FIELD_RUNBOOK.md`. It does not change the Final GO Record, authorize Bluetooth activity, or turn software/install evidence into physical ES80 truth.

## Canonical install subject

The only TODAY install subject is the exact retained IPA published by the accepted signed-field producer:

`<candidate>/inspection/build-evidence/NembraField.ipa`

That file must already have passed the canonical signed-field inspector and independent retained-evidence review for the exact frozen Capture source/build instance.

Do **not** substitute any of the following:

- an `.app` from DerivedData;
- a fresh Archive or Export performed after acceptance;
- Xcode `Run` / Build & Run output;
- a Simulator product;
- a differently exported IPA with the same marketing/build version;
- an IPA whose digest was copied from signer stdout without independently hashing the retained file;
- a sibling candidate from a different build-instance ID or source SHA.

A filename, bundle identifier, version string, or matching UI is not enough to establish exact-byte identity.

## Required retained inputs before installation

Have the accepted candidate directory and independently checked values available locally:

- exact frozen source SHA;
- exact IPA SHA-256;
- exact Capture build identifier;
- exact build-instance ID;
- exact executable SHA-256;
- exact raw Info.plist SHA-256;
- exact `ES80-FINGERPRINT-v1` recipe;
- `NembraCaptureExternalBuildRecord.json`;
- `NembraCaptureFieldBuildEvidenceRecord.json`;
- `NembraCaptureSignedFieldArtifactInspection.json`;
- intended-device authorization already proven by the inspector/provisioning profile;
- the intended iPhone 12 / iOS 27 physically available and paired to the Mac.

Do not place the private intended-device UDID in this document, GitHub comments, screenshots, artifact names, or durable operator notes.

## 1. Run the external retained-candidate cross-check

Before installation, mechanically cross-check the **published retained candidate** with the independent verifier that lives outside the frozen app-candidate lineage. The accepted verifier commit for this handoff is:

`699a1616b6ebd6e3443ca8fdd75daea9bbe6063a`

Its post-merge `Capture TODAY Independent Candidate Crosscheck QA` run `31292812633` completed successfully. Do not silently substitute a newer verifier merely because `main` moved.

Use a separate clean Nembra tooling checkout. Do **not** copy the verifier into the retained candidate directory, and do not write the receipt into that directory.

```bash
TOOL_REPO='/absolute/path/to/a/clean/Nembra/tooling-checkout'
CANDIDATE_DIR='/absolute/path/to/the/accepted/candidate'
EXPECTED_SOURCE_SHA='<exact frozen 40-hex Capture source SHA>'
TOOL_COMMIT='699a1616b6ebd6e3443ca8fdd75daea9bbe6063a'
RECEIPT_DIR="$(/usr/bin/mktemp -d /tmp/nembra-es80-crosscheck.XXXXXX)"
RECEIPT="$RECEIPT_DIR/retained-candidate-crosscheck.json"
TOOL="$RECEIPT_DIR/es80_today_independent_candidate_crosscheck.py"

cd "$TOOL_REPO"
test -z "$(/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1 \
  /usr/bin/git status --porcelain=v1 --untracked-files=all)" || {
  echo 'Tooling checkout is not clean.' >&2
  exit 1
}

/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1 \
  /usr/bin/git show "$TOOL_COMMIT:scripts/ci/es80_today_independent_candidate_crosscheck.py" \
  > "$TOOL"

/usr/bin/python3 -I "$TOOL" \
  --candidate-dir "$CANDIDATE_DIR" \
  --expected-source-sha "$EXPECTED_SOURCE_SHA" \
  > "$RECEIPT"
```

A successful command is still only a supporting evidence check. Inspect the receipt and require all of these exact semantics:

- `authority` = `independent-retained-candidate-evidence-crosscheck-not-final-go`;
- `status` = `PASS_NOT_FINAL_GO`;
- `sourceCommitSHA` = the exact frozen Capture source SHA;
- `experimentRecipeID` = `ES80-FINGERPRINT-v1`;
- `procedureVersion` = `V14`;
- `singleRetainedIPA` = `true`;
- `crossRecordDigestLinksVerified` = `true`;
- `producerPhysicalAuthorizationRemainsNotGranted` = `true`;
- `physicalExperimentAuthorization` = `not-granted`.

The verifier intentionally treats the producer/inspector Git-blob OIDs in the candidate environment as claims rather than silently promoting them. Cross-check those claims against the exact frozen Capture source repository before installation:

```bash
PRIVATE_RUNNER_BLOB="$(/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1 \
  /usr/bin/git rev-parse "$EXPECTED_SOURCE_SHA:scripts/ci/es80_signed_field_artifact_private_runner.py")"
INSPECTOR_BLOB="$(/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1 \
  /usr/bin/git rev-parse "$EXPECTED_SOURCE_SHA:scripts/ci/es80_signed_field_artifact_evidence.py")"

/usr/bin/python3 -I - "$RECEIPT" "$EXPECTED_SOURCE_SHA" "$PRIVATE_RUNNER_BLOB" "$INSPECTOR_BLOB" <<'PY'
import json
import re
import sys
from pathlib import Path

receipt_path, expected_source, private_runner_blob, inspector_blob = sys.argv[1:]
receipt = json.loads(Path(receipt_path).read_text(encoding="utf-8"))
required = {
    "authority": "independent-retained-candidate-evidence-crosscheck-not-final-go",
    "status": "PASS_NOT_FINAL_GO",
    "sourceCommitSHA": expected_source,
    "experimentRecipeID": "ES80-FINGERPRINT-v1",
    "procedureVersion": "V14",
    "singleRetainedIPA": True,
    "crossRecordDigestLinksVerified": True,
    "producerPhysicalAuthorizationRemainsNotGranted": True,
    "physicalExperimentAuthorization": "not-granted",
    "privateRunnerSourceGitBlobClaim": private_runner_blob,
    "canonicalInspectorSourceGitBlobClaim": inspector_blob,
}
for key, expected in required.items():
    if receipt.get(key) != expected:
        raise SystemExit(f"Independent retained-candidate receipt mismatch: {key}")
if re.fullmatch(r"[0-9a-f]{64}", receipt.get("signedInstallableSHA256", "")) is None:
    raise SystemExit("Independent retained-candidate receipt has no canonical IPA SHA-256")
print("Independent retained-candidate cross-check: PASS_NOT_FINAL_GO")
PY
```

Retain the receipt **outside** the candidate directory and hash that receipt for the private Final GO evidence. Do not edit, normalize, or add files to the published candidate merely to attach this receipt.

This cross-check does **not** replace the canonical Apple code-signing/provisioning/intended-device inspection. It does not prove installation, runtime rendezvous, stationary setup, charger state, or physical ES80 truth. `PASS_NOT_FINAL_GO` means exactly that: continue the handoff only if every remaining gate also passes; it never grants permission to start Experiment One.

## 2. Independently re-hash the exact retained IPA

From Terminal, hash the retained installable itself:

```bash
IPA="$CANDIDATE_DIR/inspection/build-evidence/NembraField.ipa"
/usr/bin/shasum -a 256 "$IPA"
```

The resulting lowercase SHA-256 must exactly match both:

- `signedInstallableSHA256` from the accepted external cross-check receipt; and
- the independently accepted IPA digest from the retained field-build/signing evidence intended for the TODAY Final GO Record.

If the path is missing, resolves to a different candidate, contains more than the accepted retained subject, or the digest differs by even one character, stop. Do not install.

This pre-install hash is evidence about the local retained file. It is not a claim about bytes already present on the iPhone.

## 3. Prepare the intended iPhone without rebuilding Nembra

Use the intended iPhone 12 / iOS 27 that was authorized by the retained provisioning evidence.

Before installation:

1. Connect or pair that exact device to the field Mac.
2. Ensure Developer Mode is enabled on the iPhone when required for development-signed IPA execution.
3. Use the accepted Xcode 27 installation environment; do not switch to an arbitrary toolchain that would prompt a rebuild or re-export.
4. Keep the retained candidate directory unchanged.
5. Do not open the project and press Run as an installation shortcut.

Apple's current developer documentation supports direct installation of an exported `.ipa` on a registered device through Xcode's device-management UI and states that Developer Mode is required for running IPA-based development installs:

- `https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices`
- `https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device`

Those Apple procedures are transport/install mechanisms only. Nembra's retained digest/build/provenance gates remain stricter and still apply.

## 4. Install the retained IPA directly

Canonical TODAY route:

1. Open the accepted Xcode 27 installation environment.
2. Open **Window → Devices and Simulators** (or the equivalent current Xcode device-management surface).
3. Select the intended iPhone 12 / iOS 27.
4. In the device's Installed Apps area, choose **Add (+)**.
5. Select the exact retained file at `<candidate>/inspection/build-evidence/NembraField.ipa`.
6. Allow that installation to complete.

Do not use Product → Run, a newly generated archive, or a DerivedData `.app`. Those routes can install bytes that are not the exact independently inspected retained IPA.

If Xcode asks to rebuild, resign, repair the project, create a new archive, or select another product instead of installing the retained IPA, stop and preserve the blocker. Do not improvise around the exact-subject requirement.

Apple Configurator can also install exported IPA files, but TODAY intentionally uses one canonical Xcode device-install route to reduce operator ambiguity. A fallback route must be deliberately reviewed before it is substituted into the Final GO handoff.

## 5. Launch from the installed app, not Xcode Run

After installation succeeds:

1. Disconnect the installation action from any Xcode Run/debug flow.
2. Launch **Nembra** from the iPhone Home Screen.
3. Enter the accepted Capture/preflight path normally.
4. Confirm the app reports the dedicated physical-iOS Release Research Field Build for `ES80-FINGERPRINT-v1`.
5. Compare the runtime-visible build/provenance tuple against the retained evidence:
   - exact source SHA;
   - exact Capture build identifier;
   - exact build-instance ID;
   - exact recipe.
6. Confirm package-owned TODAY research admission is available only for this dedicated Research Field Build.
7. Confirm ordinary/general build authority remains NO-GO.

Installation success alone does not prove the runtime tuple. Runtime tuple agreement alone does not prove the signed IPA was authorized for the intended device. TODAY requires both the retained signed-field evidence and the post-install runtime rendezvous.

Do not begin Bluetooth scanning merely to test that the app launches. The private physical run remains NO-GO until the complete Final GO Record is deliberately issued.

## 6. Re-hash the same retained IPA after installation

After installation and runtime tuple inspection, hash the original retained IPA again:

```bash
/usr/bin/shasum -a 256 "$IPA"
```

The post-install digest must equal all three:

- the pre-install independently checked digest;
- `signedInstallableSHA256` from the accepted external cross-check receipt; and
- the accepted retained IPA SHA-256 intended for the Final GO Record.

This detects accidental local replacement/mutation of the retained install subject during the handoff. It does **not** claim that iOS exposes a retrievable on-device byte-for-byte IPA image after installation.

## 7. What may be recorded as TODAY install evidence

Only after every step above succeeds, the private runbook may record:

- exact accepted source SHA;
- exact accepted IPA SHA-256;
- exact build identifier;
- exact build-instance ID;
- independent retained-candidate cross-check receipt SHA-256 plus its `PASS_NOT_FINAL_GO` authority boundary;
- intended baseline: iPhone 12 / iOS 27;
- installation route: exact retained IPA through Xcode device-management installation;
- pre-install retained IPA SHA-256 match: yes;
- post-install retained IPA SHA-256 match: yes;
- runtime build/source/build-instance/recipe rendezvous match: yes;
- package TODAY research admission available for that exact build: yes;
- ordinary/general build authority remains NO-GO: yes.

A wall-clock installation time may be retained as operator metadata, but it is not authority.

Do not retain the raw intended-device UDID in public/durable evidence merely to prove that an install occurred. Intended-device authorization remains bound through the private inspector input and signed provisioning evidence.

## Failure / stop conditions

Stop the TODAY handoff and leave `Installed on intended iPhone 12 / iOS 27` as **NO / NOT YET AUTHORIZED** if any of the following occurs:

- external retained-candidate cross-check does not emit the exact `PASS_NOT_FINAL_GO`/`not-granted` authority boundary;
- external cross-check source/build/build-instance/recipe/digest records disagree with the retained candidate;
- producer/inspector Git-blob claims do not match the exact frozen Capture source repository;
- retained IPA SHA-256 mismatch before or after installation;
- wrong candidate directory, source SHA, build identifier, build-instance ID, or recipe;
- more than one plausible installable and the exact retained subject cannot be unambiguously selected;
- intended-device provisioning/inspection is not independently accepted;
- the intended iPhone is not the selected install destination;
- Developer Mode / trust / pairing prevents the accepted IPA from running;
- Xcode requires a rebuild, re-export, or different product to install;
- installation fails or its outcome is ambiguous;
- the installed app cannot launch from the Home Screen;
- runtime source/build/build-instance/recipe values disagree with retained evidence;
- the dedicated TODAY research admission is unavailable in the installed build;
- ordinary/general build authority becomes enabled;
- any step would require weakening stationary, charger-disconnected, passive/read-only, exact-byte, or no-command constraints.

The correct output of a failed install handoff is the exact blocker, not a substitute artifact.

## Truth boundary

This procedure establishes a controlled private handoff from one independently inspected retained signed IPA to an intended-device installation attempt plus runtime build/provenance rendezvous.

It does **not** establish:

- physical AOVOPRO ES80 identity;
- RF completeness;
- GATT/Tuya/DP semantics;
- battery, voltage, current, power, speed, throttle, regen, or range truth;
- Bluetooth command authorization or acknowledgement;
- that an iOS-installed application can be reconstructed as the original IPA byte-for-byte;
- public/release-grade field authorization;
- permission to start Experiment One before the private runbook Final GO Record is complete.

**FIRST REAL ES80 CAPTURE / PHYSICAL EXPERIMENT ONE REMAINS NO-GO / DO NOT RUN.**
