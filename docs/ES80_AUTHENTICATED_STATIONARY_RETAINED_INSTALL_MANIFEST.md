# ES80 authenticated-stationary retained-install manifest

Status: **SOFTWARE CONTRACT ONLY — NOT INSTALL AUTHORITY / NOT PHYSICAL GO**

Procedure: `ES80-AUTHENTICATED-STATIONARY-v1`

## Purpose

`scripts/ci/es80_retained_install_manifest.py` defines one small, closed, canonical record that
cross-binds the exact subjects required by the retained-IPA handoff:

- procedure and bundle identity;
- full source commit;
- build identifier and build-instance ID;
- retained signed IPA SHA-256;
- executable and raw `Info.plist` SHA-256;
- reviewed Tuya dependency lock SHA-256;
- external build record SHA-256;
- signed build-evidence SHA-256;
- Final-GO record SHA-256;
- intended-device pseudonymous binding SHA-256;
- current-procedure authorization-envelope SHA-256.

The manifest has no `decision` or `GO` field. Its kind is
`retained-install-exact-subject-bindings-not-authorization`.

## Authority boundary

The manifest is deliberately **not** a trust root, signature verifier, Final-GO publisher, installer,
Bluetooth capability, or physical authorization. Structural validation cannot make independently
untrusted inputs trustworthy.

A future installer integration must obtain expected values from separately accepted subjects and use
`verify_manifest_against_expected` semantics before any existing retained-input admission can advance.
That future integration remains blocked until the repository's pinned trust root, app authorization
adapter, runtime/build identity handoff, accepted signed-install provenance, and applicable exact-source
execution evidence are independently closed.

Do not weaken or self-repin an independently accepted workflow/build-graph custody boundary merely
because this manifest or another Capture source file changes.

## Validation

Focused contract checks:

```sh
python3 -m unittest scripts/ci/tests/test_es80_retained_install_manifest.py
python3 scripts/ci/es80_retained_install_manifest.py --self-test
python3 -m py_compile scripts/ci/es80_retained_install_manifest.py scripts/ci/tests/test_es80_retained_install_manifest.py
```

Passing these checks proves only the software manifest grammar and exact-binding comparison behavior.
It does not prove Xcode, signing, installation, an intended iPhone, Tuya authentication, BLE continuity,
ES80 identity, telemetry semantics, command safety, or physical readiness.
