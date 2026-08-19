# Nembra Capture official Tuya SDK provisioning

Status: **PRIVATE SOFTWARE HANDOFF ONLY — PHYSICAL CAPTURE REMAINS NO-GO**

Canonical procedure: `ES80-AUTHENTICATED-STATIONARY-v1`
Canonical field runbook: `docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md`
Canonical installer: `scripts/field/install_one_time_capture.command`

This handoff provisions the disposable Nembra Capture utility with Tuya's official SmartLife SDK. It does not authorize Bluetooth activity, physical scooter interaction, or a telemetry/DP interpretation.

## Exact public inputs

The public CocoaPods inputs are exact-pinned:

- `ThingSmartHomeKit` **7.8.0**
- `ThingSmartBusinessExtensionKit` **7.8.0**

The app-specific `ThingSmartCryption` package and generated `NembraTuyaPrivateConfig` remain beneath ignored `LocalSecrets/`. AppKey, AppSecret, account credentials, verification codes, tokens, local keys, private device identifiers, and SDK security bytes must not enter Git, shell arguments, environment variables, logs, screenshots, issues, or exported Capture artifacts.

## Resolve and review a lock candidate

Run this only when no dependency lock has yet been accepted:

```sh
./Scripts/bootstrap_capture_tuya_sdk.sh --resolve-lock-for-review
```

Review mode may run `pod install --repo-update` to resolve a candidate. Its output has no build, install, Bluetooth, or physical authority. Review the resulting `Podfile.lock`, preserve its SHA-256, and do not run an ad-hoc `pod update`.

## Accepted-lock field mode

The field installer requires an existing reviewed `Podfile.lock` and its exact accepted SHA-256. Before invoking CocoaPods, bootstrap verifies the existing lock digest. It then runs only:

```sh
pod install --deployment --no-repo-update
```

Bootstrap verifies the lock again afterward. Any missing, symlinked, changed, or mismatched lock stops before `xcodebuild`. The installer also fingerprints the ignored private SDK and identity inputs into the local mode-0600 `ResolvedTuyaDependencyProvenance.txt`, verifies those fingerprints immediately before and after the signed build, and reads the lock fingerprint back from the final app.

Use `NembraCapture.xcworkspace`; the bare project is not the authenticated field-build graph.

## Private-value and encoding boundary

The installer base64-encodes only the already-public, Git-authenticated Python helper source so isolated system Python can execute those exact accepted bytes. Base64 is transport encoding, **not encryption or secret protection**. No private value may be placed in that encoded helper argument.

The intended iPhone UDID is read from one canonical absolute, owner-only, mode-0600 file outside the repository. The reader rejects symlink ancestors, resolved in-repository targets, hard links, mutation during read, malformed Apple UDID shapes, and digest mismatch. The raw UDID stays out of `devicectl` and `xcodebuild` arguments. Before installation, the decoded embedded development profile must include that exact intended device; automatic arbitrary-device registration is disabled.

## Private SDK symlink compatibility gate

`capture_tuya_private_input_provenance.py` currently rejects every symlink inside the private `ThingSmartCryption` build tree and private identity source tree. The actual app-specific package downloaded for the exact Capture bundle ID must pass this rule on the private Mac before the candidate is accepted.

That compatibility is still a private-package validation gate because the public repository does not contain the package. If the official package legitimately requires framework symlinks, **STOP**. Do not flatten, dereference, copy, or exclude them ad hoc. Update the provenance model under review so it fingerprints link identity and target custody explicitly, then re-run software acceptance before any physical step.

## Current physical boundary

After private provisioning, the current target still comes only from a fresh package-owned `OFF1 → ON1 → OFF2 → ON2` series, exactly one repeatable full CoreBluetooth UUID, after which the operator must explicitly confirm that current-attempt target. The historical C7D09A22 UUID is descriptive only. The official SDK account, exact owned/shared scooter membership, and same-account UID lease must be fresh.

The supported accepted artifact must continue to state:

- `rawFD50BytesCaptured: false`
- `dpQueriesSent: false`
- `dpCommandsSent: false`

No outdoor ride is authorized by provisioning or installation.
