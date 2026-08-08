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

- the accepted passive-capture runtime closes source-truth blockers, not merely its compile/test gate;
- stopped/non-powered discovery callbacks cannot mutate the selected-target evidence path;
- connection cancellation uses cause-correct continuity fencing, while timeout/finalized teardown paths do not manufacture duplicate or false interruptions;
- the current-main passive-capture integration composes the reviewed controlled-comparison descendant (currently #334 or an accepted equivalent), including canonical GATT value-stream identity and sealed evidence-derived result authority;
- the repeated target-correlation policy (currently #358 or accepted equivalent) and the **live window producer** (currently #361 or accepted equivalent) are both accepted;
- the live correlation producer can form all four `OFF₁ -> ON₁ -> OFF₂ -> ON₂` receipt-bounded windows without fabricating CoreBluetooth scan-request provenance. The current #361 design uses one fresh `CBCentralManager` transport epoch per window and exact callback-manager identity; if that design changes, the accepted replacement must preserve equivalent delayed-callback isolation;
- explicit correlation abandonment invalidates the whole non-complete series even **between** completed windows, so foreground/operator/lifecycle failure can never patch pre-gap windows into later phases;
- immutable observation-session evidence (currently #363 or accepted equivalent) is integrated so finite-ready and terminal observation-horizon boundaries are ordered against the same controller evidence queue/cutoff as raw callbacks;
- the accepted producer proves the post-ready observation interval from monotonic boundary evidence, not a UI timer or first/last BLE callback span;
- the V13 product-facing Nembra Capture shell (currently #350 or accepted descendant) is reconciled onto the repaired current-main runtime, accepted live correlation producer, and accepted observation-horizon producer, then passes exact-head iPhone 12 / iOS 27 app acceptance;
- the shell keeps its screen-awake / foreground-integrity policy through correlation, selected-target capture, terminal horizon, immutable artifact preparation, and share/export;
- if the stationary sidecar (#347 or accepted descendant) is part of the accepted experiment path, Nembra exposes a mechanical shell/CLI path to build and verify it from exact raw bytes, full selected UUID, build SHA, setup, and accepted correlation provenance. The operator must not hand-edit a sidecar or write Swift code to create one;
- immutable raw export and the accepted offline report executable (#301 or accepted descendant) are available;
- the exact Nembra product head used on the phone has terminal exact-head Apple-toolchain/app acceptance. A skipped, queued, cancelled, stale-parent, or pre-fix run is not green.

A terminal green workflow on an older source blob is not enough if later product-source commits change the evidence boundary. Repair, compose, then re-gate the **exact final product head**.

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
- keep Nembra in the active foreground for the entire correlation, selected-target session, observation horizon, and artifact finalization;
- any foreground-integrity loss, Bluetooth-authority loss, correlation-series invalidation, ambiguous target result, finite-acquisition failure, boundary-ordering failure, or artifact-finalization failure makes the attempt unusable. Do not reconstruct a pass from partial evidence.

## Physical setup

1. Put the ES80 on stable level ground in a safe area away from traffic.
2. Leave the charger disconnected.
3. Begin with the scooter powered **off**.
4. Use the exact accepted Debug research build identified above on the iPhone 12.
5. Keep only one physical ES80 intentionally under test. Nearby BLE devices may remain present; they are uncontrolled candidates, not automatically “noise” to discard.
6. Keep the stock app closed. Battery %, voltage, current, watts, speed, and other stock-app values are deliberately deferred to a later evidence-driven correlation experiment.

## Target correlation — accepted repeated flow only

The former one-cycle `OFF -> ON` procedure is not sufficient.

Experiment one proceeds only through the accepted live descendant of the repeated policy:

`OFF₁ -> ON₁ -> OFF₂ -> ON₂`

For this first procedure, each measurement window uses a **10-second minimum accepted callback-receipt window**. Ten seconds is an operator/runbook sampling duration, not a claimed BLE cadence or proof that OFF-window non-observation equals physical absence.

Required product behavior:

- all four completed snapshots belong to one sealed package-issued observation-series authority;
- the live producer mechanically isolates adjacent transport windows. Under the current #361 design, each window gets a fresh `CBCentralManager`; delayed callbacks from a retired manager fail exact-manager identity rather than inheriting a local scan-generation counter;
- one completed window must never be reused after explicit series abandonment, foreground loss, Bluetooth-authority failure, controller/producer reset, invalid receipt chronology, or another known authority gap;
- whole-series invalidation must work during a live window **and between** windows;
- window chronology is strictly increasing inside the one series;
- snapshots use **full CoreBluetooth UUIDs**, never shortened prefixes;
- snapshots contain callbacks actually admitted inside the bounded window, not a cumulative candidate catalog carried from another window;
- a UUID seen in either complete OFF window is ineligible as the positive “new when powered on” candidate for that cycle;
- explicitly non-connectable ON candidates are excluded; unknown connectability may remain only as the accepted policy permits;
- the same full UUID must satisfy the ON-vs-OFF pattern in both cycles;
- zero repeatable candidates fails closed;
- more than one repeatable candidate remains ambiguous;
- only `.singleRepeatableCandidate(fullUUID)` may be offered for explicit operator selection;
- local name, RSSI, advertised service/product guesses, short UUID prefixes, ordering, or Tuya signatures never break a tie or manufacture authority;
- the report is **physical-correlation evidence only**, not scooter authentication or permanent identity.

### Operator sequence

Use the accepted shell; do not manually improvise raw CoreBluetooth scans.

1. Confirm the shell shows `OFF₁` as the expected operator phase. Leave the scooter powered off.
2. Start the first correlation window and keep the app foreground for at least 10 accepted seconds. Finish the window only when the product says the minimum receipt window is satisfied.
3. Power the stationary scooter on normally. Wait for the accepted shell's transition/settling instruction; transition time is outside the measurement window and is not RF-emission evidence.
4. Run the `ON₁` window for at least 10 accepted seconds and finish it through the product flow.
5. Power the scooter off normally. Follow the accepted transition/settling instruction, then run `OFF₂` for at least 10 accepted seconds.
6. Power the scooter on normally. Follow the accepted transition/settling instruction, then run `ON₂` for at least 10 accepted seconds.
7. Do not continue if the product reports series invalidation, zero repeatable candidates, or ambiguity.
8. Continue to selected-target capture only if the accepted producer returns exactly one repeatable **full** UUID and the operator explicitly selects that UUID.

A fresh-manager transport epoch or another accepted isolation mechanism is a software evidence boundary only. The repeated result remains correlation, not physical authentication.

## Selected-target passive capture

After the accepted correlation flow returns exactly one repeatable full UUID and the operator explicitly selects it:

1. Leave the scooter powered on, stationary, and untouched for the settling interval required by the accepted shell.
2. Start the target-scoped connection/capture for that exact full UUID.
3. Keep Nembra foregrounded while it performs finite service / included-service / characteristic / descriptor discovery plus only GATT-permitted reads/subscriptions.
4. Wait until the trusted finite acquisition ledger reaches accepted ready state.
5. The controller must place a `finiteAcquisitionReady` observation boundary into the **same ordered evidence authority** after every raw callback admitted through that ready transition. A boundary written merely because a UI label changed is insufficient.
6. If finite acquisition fails closed, times out, disconnects before readiness, changes authority, reports lifecycle-integrity loss, or cannot preserve the ready boundary ordering, stop. Preserve diagnostics only as failure evidence; do not claim an unobserved service/field is absent.
7. After the accepted ready boundary, keep the scooter untouched and Nembra foregrounded for a **minimum 60 seconds of monotonic observation time**. BLE may be quiet; do not generate periodic fake events to make the interval visible.
8. Finish becomes eligible only when the accepted observation-horizon producer can append a terminal `observationHorizon` boundary at least 60,000,000,000 monotonic nanoseconds after the accepted ready boundary, under unchanged target/lifecycle authority.
9. The terminal horizon must be ordered after every raw callback admitted through its controller cutoff and must watermark the final raw-record prefix included in the immutable artifact. Later teardown callbacks must not mutate or fail that frozen artifact.
10. Tap **Finish Capture once** while still stationary. Keep Nembra active/foreground and the screen awake until immutable artifact preparation/share UI is complete.
11. Export the prepared schema-versioned JSON unchanged.
12. Verify the immutable artifact itself contains the accepted ready→horizon evidence with a monotonic interval of at least 60 seconds. A UI timer, wall clock, or first/last BLE callback span is not a substitute.
13. If the accepted provenance tooling is wired, generate and verify the stationary sidecar **mechanically** from those exact raw bytes. Do not type a short UUID into it or manually reconstruct the full UUID.
14. End the experiment. Do not add a decoder, rename streams, or send a write from the phone.

## First-run provenance values

For the accepted stationary-capture manifest/sidecar contract, the intended setup is:

- experiment kind: `stationaryBaseline`;
- charger state: `disconnected`;
- execution context: `foregroundUnlockedScreenOn`;
- stock-app reference setup: `none`;
- raw stock-app marker count: `0`;
- target-correlation provenance: accepted repeated `OFF₁/ON₁/OFF₂/ON₂` result and full selected UUID, if/when the accepted sidecar schema has a truthful representation for it;
- observation interval: derive from the immutable capture's accepted `finiteAcquisitionReady` -> `observationHorizon` monotonic boundary evidence, not from operator memory.

These are experiment/procedure facts or structured Nembra observation evidence, not scooter telemetry, permanent identity, RF emission timestamps, or OS attestation. If the immutable raw artifact contradicts metadata that can be checked mechanically, fail closed.

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

- exact schema-versioned raw capture JSON bytes;
- exact Nembra build/commit identity;
- accepted repeated-correlation report/provenance, including the full selected CoreBluetooth UUID;
- immutable `finiteAcquisitionReady` and terminal `observationHorizon` boundaries proving the accepted post-ready observation interval;
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
- immutable capture evidence contains an accepted `finiteAcquisitionReady` boundary;
- immutable capture evidence contains a terminal `observationHorizon` boundary at least 60 seconds later on the same valid experiment/target authority;
- the horizon watermarks the final raw-record prefix through the accepted cutoff and no later callback mutates/fails the frozen artifact;
- one immutable target-scoped artifact exported successfully;
- target attribution is non-ambiguous;
- no capture-integrity / foreground / Bluetooth-authority failure occurred;
- the stock app was unused and the raw artifact contains zero stock-app markers;
- accepted offline tooling can open the raw artifact;
- accepted provenance tooling, when part of the run gate, verifies its sidecar against those exact bytes.

A pass means only: **Nembra has a usable passive physical fingerprint artifact for one repeatedly correlated observed CoreBluetooth target, including a truthful stationary post-ready observation horizon.**

It does **not** mean: Nembra decoded the ES80 protocol, permanently authenticated scooter identity, verified a telemetry field, or authorized any command.

## FAIL / RETRY REQUIRED

Retry later with a completely fresh accepted correlation/capture series if:

- repeated correlation yields zero or multiple candidates;
- observation-series authority/window integrity is invalid;
- a known correlation abandonment/lifecycle gap occurs, including between windows;
- correlation product wiring is not accepted;
- finite acquisition never becomes ready;
- ready/horizon ordering or watermark evidence is invalid;
- the accepted monotonic post-ready interval is less than 60 seconds;
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