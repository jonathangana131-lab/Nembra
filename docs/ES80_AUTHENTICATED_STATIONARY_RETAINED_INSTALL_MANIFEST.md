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
- procedure, source, exact Capture bundle, build identifier, and build-instance identity;
- retained IPA, executable, raw `Info.plist`, reviewed Tuya lock, external build record, signed
  build evidence, Final-GO record, and intended-device pseudonym digests.

The retained IPA field is named `retainedIPASHA256` on both sides.

## Attempt chronology

The retained-install manifest contains **stable pre-attempt subjects only**. It deliberately does not
contain `authorizationEnvelopeSHA256`.

That omission is required by the accepted authorization model, not a weakening of it:

1. the exact retained app is installed and runs;
2. `makeCurrentApplicationAttempt` generates a fresh random process-local challenge;
3. the independent signer creates an authorization envelope that binds that exact challenge plus the
   stable build/evidence/device facts;
4. the running app verifies the returned envelope against the same in-memory attempt and the pinned
   production public key;
5. only the verifier-minted opaque capability may advance toward OFF1.

A pre-install manifest cannot truthfully bind the final envelope bytes because those bytes do not
exist until the running app creates the fresh attempt challenge. Reinstalling or relaunching cannot
bridge that cycle because the attempt is intentionally non-Codable and process-local.

## Authority boundary

The manifest is evidence and cross-binding input only. It is deliberately **not** a trust root,
signature verifier, Final-GO publisher, installer, Bluetooth capability, or physical authorization.
Structural validation cannot make independently untrusted inputs trustworthy.

The offline mirror additionally provides `verify_manifest_against_expected`: installer code can use
that only with values independently derived from already accepted subjects. Matching caller-supplied
files to each other is not sufficient authority.

The production trust root remains unset and the app entrypoint still does not consume the new
attempt/capability path, so physical Capture remains **NO-GO**. Do not self-repin an accepted
workflow/build-graph custody boundary merely because package/runtime source moved.

## Validation

Focused contract checks:

```sh
python3 -m unittest scripts/ci/tests/test_es80_retained_install_manifest.py
python3 scripts/ci/es80_retained_install_manifest.py --self-test
python3 -m py_compile scripts/ci/es80_retained_install_manifest.py scripts/ci/tests/test_es80_retained_install_manifest.py
swift test --package-path Packages/NembraBluetoothCapture --filter AuthenticatedStationaryCaptureInstallManifest
```

Passing these checks proves only wire-format parity, manifest grammar, exact stable-binding behavior,
and chronology separation. It does not prove Xcode, signing, installation, an intended iPhone, Tuya
authentication, BLE continuity, ES80 identity, telemetry semantics, command safety, or physical
readiness.
