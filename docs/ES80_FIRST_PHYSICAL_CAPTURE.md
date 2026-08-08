# AOVOPRO ES80 — First Physical Capture

Status: **prepared V13 procedure — BLOCKED, not yet verified on physical hardware**

Primary target: newer Tuya-generation AOVOPRO ES80

This procedure defines **one** minimal physical experiment. Its purpose is to move Nembra from software-only passive capture toward observed physical advertisement/GATT/value evidence without sending an unknown application characteristic write or pretending that candidate correlation is permanent scooter identity.

It is intentionally stationary and foreground-only. It is not a riding test, battery-decoding test, stock-app correlation test, command test, or proof of any Tuya DP semantic.

## V13 supersession boundary

This file is the current V13 procedure for Nembra's **first** physical ES80 action.

If `docs/ES80_PHYSICAL_CAPTURE_RUNBOOK.md` is also present, treat that file's V11 multi-session matrix as historical research planning. Its Session A / “smallest first physical action” is superseded by this procedure. Do not proceed automatically into its reconnect, charging, post-ride, or controlled-riding sessions after the first capture.

After this first artifact is analyzed, the next experiment must be selected from the actual physical evidence and revalidated against the then-accepted V13 capture/provenance/tooling contracts. Historical V11 session ordering is not authority for the next physical action.

## Run gate — DO NOT EXECUTE YET

Do not run this experiment until **all** of the following are true:

- the accepted passive-capture runtime closes the current source-truth blockers, not merely its compile/test gate;
- stopped/non-powered discovery callbacks cannot mutate the candidate catalog or selected-target evidence;
- local/operator cancellation records its explicit continuity fence before artifact-authority retirement, while timeout/finalized teardown paths do not manufacture duplicate or false interruptions;
- the current-main passive-capture integration composes the reviewed controlled-comparison descendant (currently #334 or an accepted equivalent), including canonical GATT stream identity, rather than the older comparison blob;
- the accepted target-correlation descendant (currently #358 or an equivalent) provides a **live package-owned producer** that can issue honestly bounded `OFF₁ -> ON₁ -> OFF₂ -> ON₂` observation windows under one software observation authority;
- that live producer does not represent a local counter as CoreBluetooth scan-request provenance. If it uses multiple scan requests, it must solve delayed-callback isolation legitimately; if it uses one uninterrupted scan, it must bind windows to admitted callback-receipt evidence and fail the series on lifecycle/authority loss;
- the V13 product-facing Nembra Capture shell (currently #350 or an accepted descendant) is reconciled onto that repaired current-main passive runtime **and** the accepted repeated-correlation producer, then passes exact-head iPhone 12 / iOS 27 app acceptance;
- the shell keeps its screen-awake policy through artifact finalization and its first-run copy matches the accepted repeated power-cycle flow rather than a weaker one-cycle/name/RSSI heuristic;
- if the stationary sidecar (#347 or accepted descendant) is part of the accepted experiment path, Nembra exposes a mechanical shell/CLI path to build and verify it from exact raw bytes, full selected UUID, build SHA, and setup. The operator must not hand-edit a sidecar or write Swift code to create one;
- the exact Nembra build/commit used on the phone is known;
- immutable raw export and the accepted offline report executable are available.

A terminal green workflow on an older source blob is not enough if source review has demonstrated a truth defect on that exact blob. Repair, compose, then re-gate the **exact final product head**.

A green Simulator/package run is software evidence only. It never satisfies the physical experiment by itself.

## Exact research app/build

Once the run gate is actually green:

1. Check out the exact accepted Git commit that will be recorded in experiment provenance.
2. Open the existing Nembra Xcode project in Xcode 27.
3. Select the shared **Nembra ES80 Research** scheme.
4. Run the existing `Nembra.app` Debug build on the iPhone 12 used for the experiment.
5. Confirm the app opens the dedicated **Nembra Capture** surface and visibly shows its passive-evidence-only / foreground-only boundary before correlation or scanning.

That shared research scheme selects the dedicated Debug launch mode (`--es80-passive-capture`). The Debug-only `NEMBRA_ES80_PASSIVE_CAPTURE=1` selector may remain an automation equivalent. Release builds ignore those selectors and launch normal product runtime, so Release is not this experiment's capture tool.

Do not run the normal `AppRuntime`/vehicle-control surface alongside this research capture.

## Safety boundary

For experiment one:

- scooter remains physically stationary for the entire experiment;
- charger remains **disconnected**;
- rear wheel remains on the ground;
- the only deliberate scooter state changes before target selection are normal power OFF/ON transitions required by the accepted repeated-correlation flow;
- no throttle, brake, riding, lock, light, cruise, speed-limit, start-mode, or motor-control experiment is performed;
- Nembra performs only discovery, permitted reads, and permitted notification/indication subscriptions;
- do not send any unknown characteristic-value write;
- do not treat `.write` / `.writeWithoutResponse` as authorization;
- keep the stock Tuya/AOVOPRO app closed on every device for experiment one;
- insert **zero** stock-app reference markers;
- keep Nembra in the active foreground for the entire correlation, selected-target session, and artifact finalization;
- any foreground-integrity loss, Bluetooth-authority loss, correlation-authority reset, ambiguous target result, finite-acquisition failure, or artifact-finalization failure makes the attempt unusable. Do not reconstruct a pass from partial evidence.

## Physical setup

1. Put the ES80 on stable level ground in a safe area away from traffic.
2. Leave the charger disconnected.
3. Begin with the scooter powered **off**.
4. Use the exact accepted Debug research build identified above on the iPhone 12.
5. Keep only one physical ES80 intentionally under test. Nearby BLE devices may remain present; they are uncontrolled candidates, not automatically “noise” to discard.
6. Keep the stock app closed. Battery %, voltage, current, watts, speed, and other stock-app values are deliberately deferred to a later evidence-driven correlation experiment.

## Target correlation — accepted repeated flow only

The former one-cycle `OFF -> ON` procedure is no longer sufficient.

Experiment one may proceed only through the accepted live descendant of the repeated target-correlation policy currently owned by #358:

`OFF₁ -> ON₁ -> OFF₂ -> ON₂`

Required product behavior:

- all four bounded observation windows belong to one package-issued software observation authority;
- window chronology is strictly increasing inside that authority;
- snapshots use **full CoreBluetooth UUIDs**, never shortened prefixes;
- a UUID seen in either complete OFF window is ineligible as the positive “new when powered on” candidate for that cycle;
- explicitly non-connectable ON candidates are excluded; unknown connectability may remain only as the accepted policy permits;
- the same full UUID must satisfy the ON-vs-OFF pattern in both cycles;
- zero repeatable candidates fails closed;
- more than one repeatable candidate remains ambiguous;
- only `.singleRepeatableCandidate(fullUUID)` may be offered for explicit operator selection;
- local name, RSSI, advertised service/product guesses, short UUID prefixes, ordering, or Tuya signatures never break a tie or manufacture authority;
- the report is **physical-correlation evidence only**, not scooter authentication or permanent identity.

Do not manually improvise four stop/restart scans while #358 still says live window isolation is unresolved. Follow the exact accepted shell/producer workflow once that software exists. If the producer cannot honestly form four bounded windows, stop here and do not perform the physical capture.

## Selected-target passive capture

After the accepted correlation flow returns exactly one repeatable full UUID and the operator explicitly selects it:

1. Leave the scooter powered on, stationary, and untouched for the settling interval required by the accepted shell/producer.
2. Start the target-scoped connection/capture for that exact full UUID.
3. Keep Nembra foregrounded while it performs finite service / included-service / characteristic / descriptor discovery plus only GATT-permitted reads/subscriptions.
4. Wait until Nembra reports finite passive acquisition complete/ready.
5. If it fails closed, times out, disconnects before readiness, changes authority, reports lifecycle-integrity loss, or becomes ambiguous, stop. Preserve diagnostics only as failure evidence; do not claim an unobserved service/field is absent.
6. After readiness, leave the healthy foreground target session running for **60 seconds** without touching scooter controls.
7. Tap **Finish Capture once** while still stationary.
8. Keep Nembra active/foreground and the screen awake until immutable artifact preparation/share UI is complete.
9. Export the prepared versioned JSON unchanged.
10. If the accepted provenance tooling is wired, generate and verify the stationary sidecar **mechanically** from those exact raw bytes. Do not type a short UUID into it or manually reconstruct the full UUID.
11. End the experiment. Do not add a decoder, rename streams, or send a write from the phone.

## First-run provenance values

For the accepted stationary-capture manifest/sidecar contract, the intended setup is:

- experiment kind: `stationaryBaseline`;
- charger state: `disconnected`;
- execution context: `foregroundUnlockedScreenOn`;
- stock-app reference setup: `none`;
- raw stock-app marker count: `0`;
- target-correlation provenance: the accepted repeated correlation report/method result, if/when the accepted sidecar schema has a truthful representation for it.

These are experiment/procedure facts or operator declarations, not scooter telemetry, permanent identity, or OS attestation. If the immutable raw artifact contradicts metadata that can be checked mechanically, fail closed.

## Automated offline handoff

Do not manually copy or decode packet hex.

When the accepted descendant of Nembra's offline report lane is available, feed the **unchanged raw JSON** directly to it. With the current CLI shape:

```text
nembra-es80-capture-report capture.json --output capture-report.json
```

Do not use `--force-output` for experiment one. A pre-existing report path is a naming conflict, not an excuse to overwrite evidence casually.

Preserve the derived report beside the unchanged source artifact/sidecar. The report remains a separate derived artifact bound to the exact input bytes. A structurally completed framing candidate is still only a public-family hypothesis; never rename a stream Battery, Voltage, Current, Power, Speed, Throttle, Regen, or Odometer because a frame shape matched.

If the accepted report tool is unavailable, preserve the raw capture unchanged and stop. Do not substitute manual hex interpretation.

## What to preserve

Keep together:

- exact versioned raw capture JSON bytes;
- exact Nembra build/commit identity;
- accepted repeated-correlation report/provenance, including the full selected CoreBluetooth UUID;
- explicit operator-declared state: stationary, charger disconnected, foreground/unlocked/screen-on, stock app unused;
- generated stationary sidecar if accepted tooling supports it;
- generated offline report as a separate derived artifact;
- failure diagnostics;
- no manually reconstructed packet data.

## PASS — usable first physical fingerprint

Only if:

- the accepted repeated correlation flow returned exactly one repeatable full UUID under one valid observation authority;
- the operator explicitly selected that UUID;
- the accepted runtime preserved candidate/connection/evidence lifecycle truth;
- finite acquisition reached accepted ready state;
- one immutable target-scoped artifact exported successfully;
- target attribution is non-ambiguous;
- no capture-integrity / foreground / Bluetooth-authority failure occurred;
- the stock app was unused and the raw artifact contains zero stock-app markers;
- accepted offline tooling can open the raw artifact;
- accepted provenance tooling, when part of the run gate, verifies its sidecar against those exact bytes.

A pass means only: **Nembra has a usable passive physical fingerprint artifact for one repeatedly correlated observed CoreBluetooth target.**

It does **not** mean: Nembra decoded the ES80 protocol, permanently authenticated scooter identity, verified a telemetry field, or authorized any command.

## FAIL / RETRY REQUIRED

Retry later with a completely fresh accepted correlation/capture series if:

- repeated correlation yields zero or multiple candidates;
- observation authority/window integrity is invalid;
- correlation product wiring is not yet accepted;
- finite acquisition never becomes ready;
- capture fails closed;
- the app leaves the required active foreground condition;
- Bluetooth authority changes;
- stock-app markers appear despite first-run reference setup `none`;
- export fails or raw bytes change;
- provenance cannot be tied mechanically to the exact build/artifact/selected full UUID as required by the accepted tooling.

Do not patch a failed artifact into a pass.

## Next step is evidence-driven

Do **not** preselect a battery/current/power DP before reviewing experiment one.

After automated offline analysis, choose exactly one next correlation experiment based on the strongest observed target-scoped stream and transport evidence. Only then introduce a legitimate stock-app reference, preferably on a separate observer device when simultaneous visual reference is truly required. Preserve the actual reference setup and timing; never imply Nembra sniffed another app's private Bluetooth session.

Until raw source, scaling, units, signedness, cadence, and provenance are verified, stock-app battery %, voltage, amps, watts, speed, and other displays remain correlation anchors rather than production telemetry authority.