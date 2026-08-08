# ES80 trusted-build manifest bridge

Status: **software provenance composition only — physical Experiment One remains NO-GO.**

Schema-v2 stationary manifests record a human-readable Nembra build identifier, exact source-commit declaration, package-owned `ES80-FINGERPRINT-v1` recipe identity, exact capture-byte SHA-256/byte count, target/session identity, and declared setup context. Those manifest build fields are provenance declarations; the manifest schema does not itself contain or authenticate the running executable digest.

V14 field production must therefore not populate schema-v2 build fields from rider input or from an unchecked runtime declaration. `PassiveBluetoothStationaryCaptureManifestBuilder.makeUsingTrustedCurrentApplicationBuild(...)` is the stronger field producer:

1. off the caller actor, run `PassiveBluetoothCaptureBuildPreflight.currentApplication()`;
2. hash the exact running executable and load the fixed `NembraCaptureTrustedBuildRecord.json` resource;
3. require exact build identifier, normalized full source commit, executable SHA-256, `ES80-FINGERPRINT-v1`, and `V14` procedure agreement;
4. only after that sealed binding exists, project its build identifier/source commit and package-owned recipe into the existing schema-v2 manifest builder;
5. rebuild target/evidence summary and exact capture-byte binding from the supplied capture JSON as before.

The public field API accepts no build label, Git SHA, executable digest, recipe ID, or procedure version. The deterministic package seam accepts only `PassiveBluetoothCaptureRuntimeBuildBinding`, which has no public initializer.

## Performance boundary

Runtime executable hashing, trusted-record I/O, capture JSON decoding, and capture hashing may all be nontrivial on the iPhone 12 baseline. The public trusted field producer is therefore `async` and performs that work in a utility-priority detached task. App/UI code should await the immutable `Sendable` result and present an intentional checking state rather than block MainActor.

## What the manifest does and does not retain

Schema v2 retains the matched binding's build label/source commit and the package-owned recipe ID. It does **not** contain the executable SHA-256, trusted-record digest/signature, or workflow attestation. Do not claim the exported manifest alone proves source-to-binary provenance.

Final field acceptance/share still needs the accepted trusted build record (or stronger signed/archive provenance) to remain available alongside the capture evidence so the build binding can be independently checked later. If the product requires that executable digest to live inside the manifest itself, evolve the existing closed-world manifest schema deliberately; do not smuggle a new field into schema v2 or create a second ad-hoc sidecar format.

## Relationship to runtime-only bridge

A runtime-identity-only bridge can remove manual typing, but runtime declarations alone are weaker than the matched trusted-build binding. The physical field path should prefer this trusted bridge once accepted. Runtime-only comparison/bridge APIs may remain diagnostic only if a concrete non-authoritative consumer needs them.

## Physical boundary

A matched software build does not identify/authenticate the AOVOPRO ES80, prove RF completeness, establish GATT/Tuya/DP semantics, verify battery/voltage/current/power/speed meaning, acknowledge a command, or authorize physical execution. `PassiveBluetoothExperimentOneFieldExecutionGate` remains independent and NO-GO until the final composed accepted build deliberately changes that authority.
