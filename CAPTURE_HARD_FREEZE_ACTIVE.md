# CAPTURE P0 AUTHORITY POINTER — V14

This file is a durable routing guard for fresh Nembra Capture workers. It is **not** a substitute for re-reading live GitHub state.

## Historical freeze is retired

PR #833 / `a0f4a33451f61411d6e0541f2e70edea5438342d` is **CLOSED / SUPERSEDED** and must not be treated as the current Capture flagship or as the current physical GO authority.

The first physical passive artifact was subsequently collected as `C7D09A22-96DA-4E46-9BEF-E36F670ADB0E`. That artifact established the next evidence boundary rather than protocol/telemetry semantics: the old passive run produced no application characteristic payload callbacks and exposed repeatable approximately 29.93-second unauthenticated disconnect behavior. It did not authorize raw FD50 semantics, telemetry mappings, DP queries/commands, scooter controls, or permanent identity.

Do not restore #833's old "first artifact not yet collected" ceremony. Preserve it as historical software/provenance evidence only.

## Current flagship authority

At this file's update, the live P0 acceptance subject is PR #2178:

- feature: Nembra Capture / authenticated stationary ES80 physical truth;
- branch: `integration/v14-capture-final-stationary-convergence-sol`;
- observed exact head: `fe0a00075842e363867352971f67b300d24c7729`;
- exact-head Xcode 27 run: `31363065906` — QUEUED at last observation;
- Capture Field Build Provenance run: `31363065923` — QUEUED at last observation;
- physical status: **NO-GO / DO NOT SCAN / DO NOT RUN / DO NOT REPEAT THE OLD 17-STEP RIDE**.

**Always re-read live PR #2178 before acting.** If its head differs from the SHA above, this recorded SHA and all ancestor workflow results are stale for product acceptance. Queued/running/skipped/cancelled/ancestor results are non-evidence.

The current accepted direction is the authenticated stationary read-only path:

1. fresh package-owned OFF1 -> ON1 -> OFF2 -> ON2 target correlation using full CoreBluetooth peripheral identity;
2. explicit operator confirmation of the current-session correlated target;
3. official Tuya SDK login and exact same-account scooter membership;
4. Tuya SDK remains BLE owner after authority is established;
5. genuine same-generation application evidence plus canonical authenticated observation beyond the former disconnect horizon;
6. immutable/sealed evidence and sanitized diagnostic export;
7. no arbitrary characteristic writes, no DP query/command, and no scooter control authority.

Historical UUIDs, local names, RSSI, FD50/company hints, scores, or the old C7 artifact do not by themselves authorize current target identity.

## Current critical path

Do not churn the flagship while an unchanged exact head is undergoing final software acceptance unless a demonstrated product/truth/build blocker requires movement.

After terminal exact-head software acceptance on the unchanged current flagship head, the next legal rung is the private field candidate on the intended iPhone 12 / iOS 27:

1. invoke the private Capture installer against the **exact software-accepted 40-hex source SHA**;
2. require a clean checkout whose HEAD exactly equals that accepted SHA;
3. preserve private Tuya workspace/dependency and Apple signing provenance;
4. install/launch the signed candidate on the intended iPhone 12 / iOS 27 without substituting a descendant build;
5. verify runtime source/build identity rendezvous;
6. only after the repo's explicit final GO gate, perform the smallest stationary, charger-disconnected, authenticated read-only ES80 session.

The private installer stamps `capture-v14-<sha12>` plus the exact 40-hex source SHA into the field build. Branch names are not physical authority.

## Truth boundary

Current Capture software may establish authenticated Tuya application-session evidence and structured SDK observations. It does **not** yet establish raw authenticated FD50 bytes, verified DP meanings, battery/current/power/speed telemetry semantics, command acknowledgement, or scooter-control authority.

Only the final composed exact build and the required private intended-device gates can authorize the next physical experiment. Simulator evidence remains software evidence.
