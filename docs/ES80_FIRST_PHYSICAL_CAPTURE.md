# AOVOPRO ES80 — First Physical Capture

Status: **prepared procedure only — not yet verified on physical hardware**

Primary target: newer Tuya-generation AOVOPRO ES80

This procedure defines **one** minimal physical experiment. Its purpose is to move Nembra from software-only passive capture toward observed physical advertisement/GATT/value evidence without sending an unknown application characteristic write or pretending that a broad-scan candidate is already a verified ES80 identity.

It is intentionally stationary and foreground-only. It is not a riding test, battery-decoding test, stock-app correlation test, command test, or proof of any Tuya DP semantic.

## V13 supersession boundary

This file is the current V13 procedure for Nembra's **first** physical ES80 action.

If `docs/ES80_PHYSICAL_CAPTURE_RUNBOOK.md` is also present, treat that file's V11 multi-session matrix as historical research planning. Its Session A / “smallest first physical action” is superseded by this procedure. Do not proceed automatically into its reconnect, charging, post-ride, or controlled-riding sessions after the first capture.

After this first artifact is analyzed, the next experiment must be selected from the actual physical evidence and revalidated against the then-accepted V13 capture/provenance/tooling contracts. Historical V11 session ordering is not authority for the next physical action.

## Run gate

Do not run this experiment until all of the following are true:

- the accepted passive-capture runtime closes the current source-truth blockers, not merely its compile/test gate;
- delayed `didDiscover` callbacks are admitted only while this controller is actively scanning with CoreBluetooth powered on, so a callback delivered after scan stop / target selection / central invalidation cannot repopulate the candidate catalog or become target-session advertisement evidence;
- local/operator connection cancellation records an explicit interruption in the same evidence queue **before** artifact-authority advance/retirement, so later evidence cannot correlate backward across an unrecorded cancellation gap;
- the current-main passive-capture integration composes the reviewed controlled-comparison descendant (currently #334 or an accepted equivalent) rather than the pre-#334 comparison blob; this keeps misleading comparison APIs out of the product even though experiment one itself does not perform a controlled comparison;
- the V13 product-facing Nembra Capture shell (current recovery line: #350 or its accepted descendant) has been reconciled onto that repaired current-main passive runtime and has passed its exact-head iPhone 12 / iOS 27 app gate;
- any known shell blockers that could misstate evidence continuity, target correlation, or artifact finalization have been closed;
- the exact Nembra build/commit used on the phone is known;
- the capture can be exported unchanged for offline analysis.

A terminal green workflow on an older passive-runtime blob is not enough if source review has demonstrated a truth defect on that exact blob. Source-integrity blockers must be repaired and then re-gated on the exact accepted descendant.

If the stationary-capture manifest/sidecar capability lands first, use it and preserve it with the exact capture JSON. Do not weaken provenance by manually editing the raw capture artifact.

A green Simulator/package run is software evidence only. It does not satisfy this physical run gate by itself.

## Exact research app/build

Use the accepted product-facing capture integration, not the normal Nembra runtime:

1. Check out the exact accepted Git commit that will be recorded in experiment provenance.
2. Open the existing Nembra Xcode project in Xcode 27.
3. Select the shared **Nembra ES80 Research** scheme.
4. Run the existing `Nembra.app` Debug build on the iPhone 12 used for the experiment.
5. Confirm the app opens the dedicated **Nembra Capture** surface and visibly shows its passive-evidence-only / foreground-only boundary before scanning.

That shared research scheme selects the dedicated Debug launch mode (`--es80-passive-capture`). The same mode may be selected by the Debug-only `NEMBRA_ES80_PASSIVE_CAPTURE=1` environment selector for automation. Release builds ignore those selectors and launch the normal product runtime, so a Release launch is not this experiment's capture tool.

Do not start the normal `AppRuntime`/vehicle-control surface alongside this research capture.

## Safety boundary

For this experiment:

- scooter remains physically stationary for the entire experiment;
- charger remains **disconnected**;
- rear wheel remains on the ground and no throttle/brake/control experiment is performed;
- the only deliberate physical state change before target selection is normal scooter power-on used to correlate one newly appearing Bluetooth candidate;
- Nembra performs only discovery, permitted reads, and permitted notification/indication subscriptions;
- do not send any unknown characteristic-value write;
- do not use a `.write` / `.writeWithoutResponse` property as authorization;
- do not enable lock, light, cruise, speed-limit, start-mode, or motor commands from Nembra;
- do not open or use the stock Tuya/AOVOPRO app on any device as part of this first fingerprint experiment;
- do not insert stock-app state/reference markers into this first capture;
- keep Nembra in the active foreground for the entire live selected-target session;
- if the accepted shell reports that foreground evidence integrity was lost, treat the session as permanently failed, allow its connection cancellation to stand, and do not resume/reconstruct/export it as a valid capture;
- if Bluetooth, the app, or the selected connection becomes unavailable before finite acquisition is ready, treat the attempt as incomplete rather than filling the gap with assumptions.

The V13 shell deliberately uses a foreground-only evidence lifecycle. While a live selected-target capture is active it keeps the screen awake and fails closed if the scene leaves active foreground; this is a capture-integrity guard, not proof of background capability.

## Physical setup

1. Place the ES80 on stable level ground in a safe area away from traffic.
2. Leave the scooter **powered off** initially and keep the charger disconnected.
3. Use the exact accepted Debug research build identified above on the iPhone 12.
4. Keep only one physical ES80 intentionally under test. Nearby BLE devices may remain present; they are unrelated candidates until evidence says otherwise.
5. Keep the stock app closed for this first fingerprint. Battery %, voltage, current, watts, and other stock-app displays are intentionally deferred to a later evidence-driven correlation experiment.

## Exact target-correlation + capture procedure

1. Open **Nembra Capture** through the accepted **Nembra ES80 Research** Debug launch and keep it foregrounded.
2. With the ES80 still powered **off**, start one broad foreground scan with advertisement-cadence duplication at its normal/off setting.
3. Observe the candidate list for about **10 seconds**. This is only a nearby-device baseline; do not select anything yet.
4. Without moving the scooter, power the ES80 on normally while the broad scan remains active.
5. Watch for a newly appearing connectable candidate after scooter power-on. Treat power-on timing as physical-correlation evidence only—not authentication or permanent scooter identity.
6. Continue scanning for about **10 seconds** after power-on. Proceed only if one candidate is uniquely attributable from that before/after observation. If no new candidate appears, or multiple plausible candidates appear together, stop the scan and classify target selection as ambiguous. Do not guess from local name or strongest RSSI.
7. Leave the scooter powered on and untouched for about **30 seconds** before connecting so transient power-on behavior can settle. The scooter remains stationary throughout.
8. Treat any short UUID prefix shown in the product shell as display-only disambiguation. Provenance/manifest tooling must use the controller's **full canonical CoreBluetooth UUID** for the selected target. Never reconstruct or guess the full identifier from an 8-character prefix. If the integrated tooling cannot bind the full selected identifier automatically, keep the raw artifact and defer manifest creation until offline tooling can read the exact target identity from evidence.
9. Select the uniquely correlated candidate and start the target-scoped capture. The accepted runtime must stop broad scanning here and reject any delayed discovery callback delivered after that stop from mutating the catalog or selected-target evidence.
10. Keep the scooter stationary while Nembra performs finite service / included-service / characteristic / descriptor discovery plus only GATT-permitted reads/subscriptions.
11. Wait until Nembra reports that the finite passive acquisition is complete/ready. If it fails closed, times out, disconnects before readiness, becomes ambiguous, or reports foreground evidence-integrity loss, stop. Preserve failed diagnostics only as failure evidence; do not use the attempt to claim a service/field is absent.
12. After readiness, leave the healthy foreground session running for **60 seconds** without touching scooter controls.
13. Finish Capture **once** while still stationary. Keep Nembra foregrounded until artifact finalization/share UI is complete; do not switch apps or lock the phone during finalization.
14. Export the prepared versioned JSON unchanged. If the provenance sidecar/manifest capability is available, export/preserve it with the exact JSON bytes.
15. End the experiment. Do not immediately add a decoder or send a write from the phone.

## First-run provenance values

For the accepted stationary-capture manifest/sidecar contract, the first experiment's intended operator setup is:

- experiment kind: `stationaryBaseline`;
- charger state: `disconnected`;
- execution context: `foregroundUnlockedScreenOn`;
- stock-app reference setup: `none`;
- stock-app marker count expected from the raw artifact: `0`.

Those values describe intended procedure/provenance. They are not proof that the scooter was physically stationary, not OS attestation of uninterrupted foreground execution, not scooter authentication, and not telemetry semantics. If the exact raw artifact contradicts the setup metadata, fail closed rather than forcing the sidecar to verify.

## Automated offline handoff

Do not manually copy or decode packet hex after the capture.

When the accepted descendant of Nembra's offline capture-report lane is available, feed the **unchanged raw JSON file** directly to its CLI. For example, if the exported file is named `capture.json`, write the derived report to a separate new path:

```text
nembra-es80-capture-report capture.json --output capture-report.json
```

The current CLI protects existing outputs by default and refuses to replace its raw capture input even when force replacement is requested. Do not use `--force-output` for the first physical artifact; a pre-existing report filename should be treated as a naming conflict, not something to overwrite casually.

Preserve `capture-report.json` beside the unchanged source artifact/sidecar. The report remains a separate derived artifact bound to the exact input byte count and SHA-256. Use its target attribution, GATT/value-stream provenance, continuity, and bounded framing-candidate outcomes to decide the next experiment.

A structurally completed framing candidate is still only a public-family hypothesis. Do not rename candidate streams Battery, Voltage, Current, Power, Speed, Throttle, or Regen because the CLI found a frame shape. If the accepted CLI contract changes before physical execution, use the exact accepted command/contract rather than this historical spelling.

If no accepted automated report tool is available yet, preserve the raw capture unchanged and stop. Do not substitute manual hex interpretation just to keep the experiment moving.

## What to preserve

Keep together:

- exact versioned capture JSON bytes;
- exact Nembra Git commit/build identity;
- full selected observed CoreBluetooth peripheral identifier from authoritative capture evidence/tooling, never a guessed expansion of a UI prefix;
- the fact that target selection used the off-baseline -> normal power-on appearance correlation above, including any ambiguity/failure note;
- explicit operator-declared state: `stationary`, `charger disconnected`, `foregroundUnlockedScreenOn`, `stock app unused`;
- any generated stationary-capture manifest/sidecar;
- any generated offline capture report as a separate derived artifact;
- any failure diagnostic shown by Nembra;
- no manually reconstructed packet data.

## Offline acceptance questions

The first artifact is useful if offline tooling can answer these questions from captured evidence without inventing semantics:

1. Which advertisement identifiers/data were actually observed for the selected target?
2. Which GATT services, included services, characteristics, descriptors, and characteristic properties were observed?
3. Does the physical target expose a researched transport candidate such as modern Tuya `FD50`, legacy `1910`, or something else?
4. Which characteristics produced read responses and which produced subscription updates?
5. Which raw value streams changed or repeated during the stationary 60-second window?
6. Were there any continuity breaks, topology invalidations, acquisition failures, or target-attribution ambiguities?
7. Does the artifact contain enough explicit target evidence to distinguish `target absent/unknown` from `target observed but no candidate match`?
8. Does the raw artifact contain zero stock-app markers, as required by this first-run no-reference procedure?

These answers may promote facts only to **OBSERVED ON PHYSICAL TARGET** / **PHYSICAL EVIDENCE PRESENT** where the raw artifact supports them. They do not yet establish battery, voltage, current, watts, speed, odometer, charging, command, or acknowledgement semantics.

## Pass / fail result

### PASS — usable first physical fingerprint

Only if:

- target selection was uniquely correlated by the off-baseline -> normal power-on observation rather than guessed from name/RSSI;
- the accepted runtime rejects delayed discovery callbacks once broad scanning has stopped for target capture;
- finite acquisition reached the controller's accepted ready state;
- export completed from one immutable target-scoped artifact;
- target attribution is non-ambiguous under the capture/analyzer policy;
- no capture-integrity failure occurred;
- the accepted shell did not report foreground evidence-integrity loss;
- the stock app was unused and the raw artifact contains no stock-app reference markers;
- the raw artifact can be opened by Nembra's offline tooling.

A pass means: **Nembra has a usable passive physical fingerprint artifact for the selected observed target.**

It does **not** mean: **Nembra has decoded the ES80 protocol or permanently authenticated scooter identity.**

### FAIL / RETRY REQUIRED

Retry later with a fresh session if:

- power-on correlation did not produce one uniquely attributable candidate;
- finite acquisition never became ready;
- capture failed closed;
- the shell reports foreground evidence-integrity loss or the phone left the required active foreground condition;
- Bluetooth became unavailable during the required acquisition window;
- stock-app markers appear despite this run's declared no-reference setup;
- export failed or the raw file changed after export;
- provenance cannot be tied to the exact build and selected observed target.

Do not patch a failed artifact into a pass.

## Next step is evidence-driven

Do **not** preselect a battery/current/power DP before reviewing this artifact.

After offline analysis, choose exactly one next correlation experiment based on the strongest observed raw stream and transport evidence. Only then introduce a legitimate stock-app reference, preferably on a separate observer device when simultaneous observation is truly required by the experiment. The second experiment must preserve the actual reference setup and timing rather than implying that Nembra sniffed another app's private Bluetooth session.

Until raw source, scaling, units, signedness, cadence, and provenance are verified, stock-app battery %, voltage, amps, and watts remain correlation anchors rather than production telemetry authority.