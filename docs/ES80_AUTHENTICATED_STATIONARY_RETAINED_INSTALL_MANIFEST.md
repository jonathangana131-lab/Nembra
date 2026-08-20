# ES80 authenticated-stationary retained-install manifest

Status: **SOFTWARE CONTRACT ONLY — NOT INSTALL AUTHORITY / NOT PHYSICAL GO**

Procedure: `ES80-AUTHENTICATED-STATIONARY-v1`

## One canonical contract

The package-owned authority is
`AuthenticatedStationaryCaptureInstallManifestVerifier` in `NembraBluetoothCapture`.

`scripts/ci/es80_retained_install_manifest.py` is an offline mirror of that exact wire contract for
installer/workflow tooling. It must not invent a second manifest shape. Both sides use:

- schema `nembra.es80-authenticated-stationary-install-manifest`, version `1`;
- compact sorted-key JSON with no trailing newline;
- the same 16 KiB input bound;
- procedure, source, bundle, build identifier, and build-instance identity;
- retained IPA, executable, raw `Info.plist`, reviewed Tuya lock, external build record, signed
  build evidence, Final-GO record, intended-device pseudonym, and authorization-envelope digests.

The retained IPA field is named `retainedIPASHA256` on both sides.

## Authority boundary

The manifest is evidence and cross-binding input only. It is deliberately **not** a trust root,
signature verifier, Final-GO publisher, installer, Bluetooth capability, or physical authorization.
Structural validation cannot make independently untrusted inputs trustworthy.

The offline mirror additionally provides `verify_manifest_against_expected`: installer code can use
that only with values independently derived from already accepted subjects. Matching caller-supplied
files to each other is not sufficient authority.

A future installer integration remains blocked until the repository's pinned trust root, app
authorization adapter, runtime/build identity handoff, accepted signed-install provenance, and
applicable exact-source execution evidence are independently closed. Do not self-repin an accepted
workflow/build-graph custody boundary merely because package/runtime source moved.

## Validation

Focused contract checks:

```sh
python3 -m unittest scripts/ci/tests/test_es80_retained_install_manifest.py
python3 scripts/ci/es80_retained_install_manifest.py --self-test
python3 -m py_compile scripts/ci/es80_retained_install_manifest.py scripts/ci/tests/test_es80_retained_install_manifest.py
```

Passing these checks proves only wire-format parity, manifest grammar, and exact-binding comparison
behavior. It does not prove Xcode, signing, installation, an intended iPhone, Tuya authentication,
BLE continuity, ES80 identity, telemetry semantics, command safety, or physical readiness.
