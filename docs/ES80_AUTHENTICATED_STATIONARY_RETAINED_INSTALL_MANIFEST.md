# ES80 authenticated-stationary retained-install manifest

Status: **SOFTWARE CONTRACT ONLY — NOT INSTALL AUTHORITY / NOT PHYSICAL GO**

Procedure: `ES80-AUTHENTICATED-STATIONARY-v1`

## Purpose

`AuthenticatedStationaryCaptureInstallManifestVerifier` in Swift and
`scripts/ci/es80_retained_install_manifest.py` now define **one byte-identical closed canonical
record** for the retained-IPA handoff. The installer and running Capture app must not maintain two
incompatible meanings of “canonical manifest.”

The shared record binds:

- schema/version and procedure identity;
- exact Capture bundle identity;
- full source commit;
- build identifier and build-instance ID;
- retained signed IPA SHA-256 (`retainedIPASHA256`);
- executable and raw `Info.plist` SHA-256;
- reviewed Tuya dependency lock SHA-256;
- external build record SHA-256;
- signed build-evidence SHA-256;
- Final-GO record SHA-256;
- intended-device pseudonymous binding SHA-256;
- current-procedure authorization-envelope SHA-256.

Canonical bytes use the same contract as Swift `JSONEncoder` with `.sortedKeys` and
`.withoutEscapingSlashes`: compact UTF-8 JSON with no trailing newline. The schema is
`nembra.es80-authenticated-stationary-install-manifest`, version `1`.

The manifest intentionally has no `decision`, `GO`, `authorized`, or caller-selected trust-root
field. Structural validation remains non-authorizing.

## Authority boundary

The manifest is deliberately **not** a trust root, signature verifier, Final-GO publisher, installer,
Bluetooth capability, or physical authorization. Structural validation cannot make independently
untrusted inputs trustworthy.

A future installer/app integration must obtain expected values from separately accepted subjects,
verify the exact manifest bytes and retained IPA, verify the current-procedure authorization through
the independently reviewed pinned public key, and only then allow the verifier-minted opaque
one-attempt capability to advance through the app lifecycle gate.

The production trust root remains absent and the app authorization adapter is not yet wired, so
physical Capture remains **NO-GO**. Do not weaken or self-repin an independently accepted
workflow/build-graph custody boundary merely because this manifest or another Capture source file
changes.

## Validation

Focused contract checks:

```sh
python3 -m unittest scripts/ci/tests/test_es80_retained_install_manifest.py
python3 scripts/ci/es80_retained_install_manifest.py --self-test
python3 -m py_compile scripts/ci/es80_retained_install_manifest.py scripts/ci/tests/test_es80_retained_install_manifest.py
swift test --package-path Packages/NembraBluetoothCapture --filter AuthenticatedStationaryCaptureInstallManifest
```

The Python regression suite also pins the shared schema/field/canonicalization contract against the
Swift verifier source so future format drift fails loudly.

Passing these checks proves only the software manifest grammar and exact-binding behavior. It does
not prove Xcode, signing, installation, an intended iPhone, Tuya authentication, BLE continuity,
ES80 identity, telemetry semantics, command safety, or physical readiness.
