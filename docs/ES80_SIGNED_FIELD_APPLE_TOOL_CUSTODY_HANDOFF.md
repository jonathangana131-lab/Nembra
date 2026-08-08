# ES80 signed-field Apple tool custody handoff

**Status:** P0 software provenance blocker on the exact Capture closure lineage at `73622ed18f61b2e5b57dd7fb2119da644aaa5f64`.  
**Physical status:** **NO-GO / DO NOT RUN Experiment One**.

## Finding

The canonical signed-field IPA inspector still resolves the Apple verification binaries using ambient caller-controlled `PATH`:

- `shutil.which("codesign")`
- `shutil.which("security")`

These are authority-adjacent inputs to the field-build evidence chain. `codesign` supplies signature validity/metadata, effective signed entitlements, and the leaf signing certificate. `security cms` supplies the decoded embedded provisioning profile. If an untrusted executable earlier in `PATH` can impersonate either tool, the inspector can be fed fabricated signing/provisioning facts before it emits the canonical field-build evidence and signing inspection records.

This trust class has already been removed from the offline field-authorization signer for OpenSSL; the signed-IPA inspector should not retain a weaker executable-discovery boundary.

## Durable regression

`qa/es80-v14-apple-tool-custody-night-provenance` adds:

`scripts/ci/tests/test_es80_signed_field_artifact_apple_tool_custody_source.py`

The test is intentionally expected-red on the vulnerable parent. It requires:

- no ambient `shutil.which("codesign")`;
- no ambient `shutil.which("security")`;
- fixed protected Apple system paths `/usr/bin/codesign` and `/usr/bin/security` in the canonical inspector.

Do not weaken the regression merely to make it green.

## Repair shape

Keep one canonical inspector. Prefer fixed Apple system executable paths for `codesign` and `security`. If a future release environment genuinely needs an override, require an explicit absolute controlled path and apply custody checks rather than ambient search.

Preserve all current stronger contracts:

- two-pass exact-IPA snapshot through one no-follow descriptor;
- snapshot stability/re-hash checks;
- duplicate/casefold/Unicode ZIP collision rejection;
- strict code-signature verification;
- exact leaf signing certificate membership in the provisioning profile;
- effective-entitlement subset validation;
- intended-device provisioning check without persisting the raw UDID;
- external build-record / field-build-record exact-byte binding;
- launch recipe + executable + raw Info.plist identity;
- nil production P-256 trust root and separate final field-policy GO.

## Exact-head acceptance correction

Trusted Xcode 27 run `31256441740` for `9b14d91f8acb65b226199e92b86394a3b2856c04` completed **cancelled** and is non-evidence.

The flagship then advanced to `73622ed18f61b2e5b57dd7fb2119da644aaa5f64`; run `31256566771` also completed **cancelled**. Neither run earns software, visual, provenance, or physical acceptance.

A repaired descendant must receive its own terminal exact-head trusted Xcode 27 acceptance, followed by retained artifact/screenshot review, before any signed-device handoff can be considered.

## Truth boundary

This finding does not authenticate an AOVOPRO ES80, prove RF completeness, establish GATT/Tuya/DP/telemetry semantics, authorize any application characteristic-value write, install a trust root, mint a signed field authorization, or authorize the physical procedure.

**FIRST REAL ES80 CAPTURE REMAINS NO-GO / DO NOT RUN.**
