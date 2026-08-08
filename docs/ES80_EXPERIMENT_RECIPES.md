# ES80 Experiment Recipes

Nembra physical research procedures are versioned product contracts. A recipe gives the app one stable identifier and one fixed stage order so later UI/controller integration cannot silently shorten or reorder a physical experiment while retaining the same procedure name.

## ES80-FINGERPRINT-v1

The first stationary ES80 fingerprint recipe is:

1. Preflight
2. Find scooter
3. OFF₁ observation window
4. ON₁ observation window
5. OFF₂ observation window
6. ON₂ observation window
7. Explicit target confirmation
8. Passive discovery
9. Observation ready
10. Capture
11. Observation horizon + immutable seal
12. Integrity check
13. Analyze
14. Share

`PassiveBluetoothExperimentRecipe.es80FingerprintV1` owns that exact sequence. Construction is sealed, so a caller cannot publish the same official recipe ID with omitted/reordered steps. `PassiveBluetoothExperimentRecipeProgress` accepts only the exact next stage and remains unchanged after an out-of-order attempt.

`PassiveBluetoothExperimentRecipeID.es80FingerprintV1` encodes as the stable string `ES80-FINGERPRINT-v1`. That spelling is intended for eventual capture-artifact provenance once the accepted final artifact/schema owner integrates it; this slice does not modify the capture schema or claim that current exported artifacts already contain the recipe ID.

## Truth boundary

Recipe progress is workflow policy, not evidence. Completing a software step does not prove that the scooter was physically OFF/ON, that RF traffic was complete, that the correlated UUID authenticates an AOVOPRO ES80, that GATT/Tuya bytes have telemetry semantics, or that the artifact passed its independent integrity/authority checks.

The existing evidence producers remain authoritative for power-cycle correlation, finite acquisition readiness, Ready→Horizon duration, queue chronology, immutable artifact sealing, provenance, and offline analysis. UI/controller integration should advance recipe presentation only when the corresponding accepted producer has earned the transition; it must not use recipe progress to manufacture those facts.

## Integration handoff

This additive slice deliberately avoids the actively owned foreground-controller, boundary queue, recovery, artifact schema, app-shell, and offline-report files. The next safe integration after those owners converge is to:

- bind each UI recipe transition to the accepted evidence producer rather than a caller-declared success;
- embed the stable recipe ID in the final immutable exported artifact/provenance contract;
- expose the recipe/version in the field build UI without replacing exact build SHA provenance;
- keep the first physical Experiment One status at **DO NOT RUN** until the final composed exact build passes its software, visual/accessibility, and physical GO gates.

## Hardware status

**SOFTWARE PROCEDURE ORDERING ONLY — NOT PHYSICAL AOVOPRO ES80 VERIFICATION. PHYSICAL EXPERIMENT ONE REMAINS DO NOT RUN.** No advertisement/GATT/Tuya/DP identity, battery/voltage/current/power/speed meaning, scaling/cadence, command authorization/acknowledgement, or physical scooter behavior is established. No characteristic-value write path is added.
