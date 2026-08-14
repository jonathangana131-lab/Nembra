# Nembra Capture P0 — authenticated stationary secure-link gate

PROCEDURE_ID: `ES80-AUTHENTICATED-STATIONARY-v1`

Status: **PHYSICAL NO-GO.**

This is the single current next-physical-procedure authority for the authenticated read-only Capture direction. It continues from historical physical capture `C7D09A22`; **Do not repeat the completed 17-step ride capture.** Older passive/authenticated gate documents are historical only and cannot authorize execution.

Until all applicable software/private-device prerequisites are true, the final composed exact build is accepted, and the repository explicitly records `GO`, the physical secure-link experiment is **NO-GO**.

## Truth already earned — and not earned

Historical `C7D09A22` established useful Tuya/FD50 transport-family evidence and an unauthenticated disconnect pattern near 30 seconds. Its historical CoreBluetooth UUID is **descriptive capture-local evidence only**. It cannot mint target authority, break a tie, or establish permanent ES80 identity.

The current path may establish a supported SmartLife SDK-authenticated application session and same-generation structured SDK observations. Structured `dpsUpdate` observations are application-level evidence only. They do **not** establish raw authenticated FD50/ATT bytes, verified DP meanings, battery/current/power/speed telemetry semantics, command acknowledgement, or scooter-control authority.

## Current mechanical gates — all required before GO

The final field candidate must be one exact composed source/build lineage with:

1. Exact authoritative compiled Capture provenance: 40-hex source commit, exact private Tuya dependency lock digest, `capture-v14-<source-prefix>` build identifier, and exact `ES80-AUTHENTICATED-STATIONARY-v1` procedure identifier.
2. Accepted standalone software truth on that unchanged source head. Queued, running, skipped, cancelled, ancestor-green, package-only, source-review-only, and Simulator-only results do not authorize physical execution.
3. The official SmartLife App SDK as authentication provenance for the current BLE generation. Device Sharing may prove account/device authority but cannot mint BLE-authenticated state.
4. Fresh exact-device membership after complete enumeration of the current SDK account's homes, plus a lease bound to the same current account UID and exact device ID, before OFF1 and again before authenticated ownership. Nembra does not currently retain a home-ID continuity lease and this procedure must not claim one.
5. A package-owned, fresh-manager `OFF1 → ON1 → OFF2 → ON2` correlation series. Every window must prove scan readiness and the accepted receipt-bounded minimum duration; elapsed UI time is not evidence.
6. Exactly one repeatable full CoreBluetooth UUID from the accepted four-window chronology. No result or ambiguous results are terminal STOP/restart-from-OFF1 outcomes. There is no hint-based override.
7. Explicit operator action **tap `Confirm this scooter signal`** for the freshly correlated current-attempt target. Confirmation is session authority only, not permanent scooter identity.
8. Tuya SmartLife SDK becomes the sole authenticated BLE owner after target confirmation. Nembra must not open a second independent CoreBluetooth connection.
9. Every counted `ThingSmartDeviceDelegate.dpsUpdate` must be fail-closed source-attributed to the exact selected SmartLife device ID before it can enter physical-readiness evidence. Nil/wrong-device source cannot mint application chronology or acceptance and must synchronously block promotion while source authority retires.
10. Delivered application evidence must own accepted monotonic delivery chronology before any async scheduling can reorder it. The final repair must use package-visible, exact-generation, non-caller-mintable, one-shot/order-preserving admission so one callback cannot be replayed as repeated evidence and the watchdog cannot overtake an already-delivered pending prefix. Independent task execution order is not delivery-order proof.
11. Current authenticated readiness must satisfy the package contract: SmartLife SDK provenance; at least **two** genuine non-empty same-generation application observations admitted through gates 9–10; the latest accepted application payload at least **30 seconds after authentication**; and at least **45 seconds of canonical authenticated observation** with valid monotonic chronology.
12. An authenticated generation that reaches **60 seconds after authentication** without earning canonical readiness is retired fail-closed. Deadline-crossing evidence cannot rescue an already-terminal generation, and executor delay must not redefine when a physical observation was delivered.
13. Already-package-terminal app mirrors and lifecycle teardown must converge to an honest terminal presentation without repainting a newer lifecycle owner and without leaving tokenless `.observing` UI. No second ledger terminal or invented disconnect may be used to achieve this.
14. The app must seal the canonical ready prefix before presenting success. Post-seal callbacks cannot mutate the accepted artifact or create later physical authority.
15. Exact sanitized export integrity and provenance are accepted. The export must preserve the current schema and distinguish observation proof from absence of proof; it must explicitly retain `rawFD50BytesCaptured=false`, `dpQueriesSent=false`, and `dpCommandsSent=false` for this supported SDK path.
16. Real iPhone 12 / iOS 27 signed-build custody is closed on the exact accepted composition. Public/unprovisioned Simulator builds are not field-build authority.
17. The intended physical iPhone is mechanically admitted and the running app proves the exact build/source/procedure rendezvous before OFF1.
18. Required current-head visual, accessibility, failure/recovery-state, and runtime review is accepted on the final composed build. Ancestor screenshots do not accept a moved product head.
19. The repository has a definitive administrator-trusted field installer/signing handoff for that exact source/build. Candidate-controlled PR bytes may not become their own privileged/root trust anchor.
20. The final GO record names the exact accepted build, procedure, intended device, expected artifact, and stop conditions.

Gates 9, 10, and 13 are software evidence-custody requirements, not extra operator actions. A source test or validation child that merely describes them is not product acceptance; the final composed app must implement them and re-earn exact-head gates.

## Smallest physical test — only after repository status explicitly flips to GO

This procedure is indoors and stationary. It requires no riding. Setup and all phone interaction happen while the scooter is stationary.

### Preflight

1. Install the exact accepted signed Capture build on the intended iPhone 12 / iOS 27.
2. In Engineering Details, verify the exact Build, Source commit, and Procedure tuple. Procedure must be `ES80-AUTHENTICATED-STATIONARY-v1`.
3. Keep the scooter stationary and initially **OFF**.
4. Use the official Tuya SDK verification-code account flow when login is required. Require a fresh exact-device membership check after complete enumeration of the current account's homes and retain the same-account-UID + exact-device identity lease.
5. If build authority, SDK login, exact-device membership, account identity, foreground integrity, private dependency provenance, or any software evidence-custody gate is unavailable or changes, **STOP**. Do not begin OFF1.

### Fresh four-window target correlation

6. Tap **`Start with scooter OFF`** with the scooter OFF. Wait for package scan readiness and the accepted receipt-bounded minimum duration, then tap **`Finish OFF1`**.
7. Turn the scooter **ON**, let the physical state settle, then tap **`Start ON1`**. Wait for scan readiness and the accepted receipt-bounded minimum duration, then tap **`Finish ON1`**.
8. Turn the scooter **OFF**, let the physical state settle, then tap **`Start OFF2`**. Wait for scan readiness and the accepted receipt-bounded minimum duration, then tap **`Finish OFF2`**.
9. Turn the scooter **ON**, let the physical state settle, then tap **`Start ON2`**. Wait for scan readiness and the accepted receipt-bounded minimum duration, then tap **`Finish ON2`**.
10. Require exactly one repeatable full CoreBluetooth UUID from the accepted chronology. None, ambiguity, invalid order, invalid liveness, invalid duration, or invalid provenance means **STOP** and restart only from a fresh OFF1 after correcting the blocker.
11. Treat the result only as a correlated Bluetooth target for this attempt. Do not use historical UUID, name, RSSI, FD50 presence, Tuya manufacturer/product hints, or service-name similarity as fallback authority.
12. Tap **`Confirm this scooter signal`**. If current same-account exact-device authority is no longer valid, confirmation must fail closed.

### Supported read-only Tuya session

13. Re-prove current same-account exact-device authority. Tuya's official SDK becomes the sole authenticated BLE owner. Nembra sends no scooter DP query/control command and opens no second CoreBluetooth connection.
14. After authentication, preserve one current generation only. Require valid accepted observation chronology, supported SmartLife SDK provenance, exact callback-device source attribution, and observed local-BLE-online proof from the accepted source before readiness can be earned.
15. Keep the scooter stationary, keep Capture in the foreground, and do not change mode/light/brake/throttle/charger state during this preflight. This freezes the physical setup; charger state is not measured or sensed by Nembra.
16. Require at least **two** genuine non-empty same-generation `ThingSmartDeviceDelegate.dpsUpdate` application observations admitted through the final source/chronology custody path. Require the latest accepted application payload to occur at least **30 seconds after authentication** and require at least **45 seconds of canonical authenticated observation**.
17. If the current generation reaches **60 seconds after authentication** without satisfying the full readiness contract, it must retire fail-closed. Do not wait indefinitely and do not let a callback physically delivered after the retirement boundary rescue the generation.
18. The app must seal the canonical ready prefix before presenting success. Delayed callbacks after seal/failure cannot mutate the accepted artifact.
19. Prepare and share the sanitized Capture JSON. It must preserve exact build/source/procedure and target-correlation provenance and explicitly carry `rawFD50BytesCaptured=false`, `dpQueriesSent=false`, and `dpCommandsSent=false` for this path.

### Stop conditions

Stop and preserve only already-legitimate evidence if any of these occurs:

- field-build provenance becomes non-authoritative or no longer matches the repository's accepted exact subject;
- SDK account logout/switch, exact-device membership change, or account-identity lease invalidation;
- any OFF/ON window fails scan readiness, accepted receipt duration, chronology, or package authority;
- correlation is none/ambiguous or explicit target confirmation is unavailable;
- unsupported authentication provenance, local-BLE settlement failure, monotonic-clock regression, or observed offline state;
- a counted application callback lacks exact selected-device source attribution, source invalidation cannot synchronously fence acceptance, or source-failure retirement can be duplicated/replayed;
- callback/liveness chronology can be determined by later executor scheduling, a receipt/admission can be caller-pre-minted or replayed, delivered callbacks can be processed out of delivery order, or an already-issued watchdog mutation can overtake a pending accepted delivery;
- fewer than two accepted application payload observations, no accepted payload at least 30 seconds after authentication, or the 45-second canonical stability interval is not earned before the 60-second incomplete-observation retirement boundary;
- any stale/late callback, lifecycle transition, terminal mirror, or session generation cannot be retired/presented without contaminating current authority or leaving a false live/observing state;
- app foreground integrity or exact build/source/procedure rendezvous fails;
- any secret appears in UI, logs, screenshots, issue/chat text, or export;
- any Nembra DP query/publish, unknown characteristic write, scooter control, unbind/reset/OTA, or second post-auth CoreBluetooth ownership path is observed.

On failure, share only the sanitized diagnostic artifact if available and stop. Do not compensate by repeating the old outdoor ride or by guessing packets/DP semantics.

## GO record — intentionally unissued

- Accepted exact source commit: **NOT YET AUTHORIZED**
- Accepted signed field build / install evidence: **NOT YET AUTHORIZED**
- Accepted private dependency-lock subject: **NOT YET AUTHORIZED**
- Accepted visual/runtime exact-head subject: **NOT YET AUTHORIZED**
- Accepted evidence-admission/source-attribution subject: **NOT YET AUTHORIZED**
- Accepted administrator-trusted signing/bootstrap subject: **NOT YET AUTHORIZED**
- Procedure: `ES80-AUTHENTICATED-STATIONARY-v1`
- Baseline device: iPhone 12 / iOS 27
- Expected artifact: sanitized schema-v11 Capture JSON with exact build/source/procedure/correlation provenance and read-only truth markers
- Physical execution state: **NO-GO / NOT YET AUTHORIZED**

Only a final composed exact build may replace the NOT YET AUTHORIZED fields and change this document to GO. No ancestor SHA, branch name, PR prose, self-described artifact, skipped/queued workflow, Simulator result, public build, validation-only oracle, or candidate-controlled bootstrap may do so.
