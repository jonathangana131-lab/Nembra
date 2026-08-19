# CAPTURE P0 AUTHORITY POINTER — CURRENT

This file is a durable Capture routing guard. It does **not** replace live GitHub inspection.

## Repository authority

The root `AGENTS.md` on current `main` is the execution authority for Nembra development. The old swarm scheduler, worker/claim/lease model, recovery ladders, and historical V14/V15/V16/V17 routing packets are reference material only unless current product/safety code or docs explicitly preserve a fact from them.

For every Capture run:

1. refresh current `main`;
2. refresh open Capture PRs and their exact heads;
3. inspect exact-head checks/reviews/evidence;
4. prefer finishing the strongest current candidate instead of reviving a historical branch;
5. keep physical truth fail-closed.

Do not treat a branch name, old protocol number, stale continuation note, ancestor green, queued run, skipped run, or historical PR body as current acceptance authority.

## Current candidate

At this update, the active integrated Capture/product candidate is PR #3675:

- feature: Nembra Capture / authenticated stationary ES80 physical truth plus production Nembra surfaces;
- branch: `product/capture-1-0-main-20260818`;
- base: current `main` lineage beginning from `0bc188e41c10e4deb7e8c2d214e216f6ea5b24e6`;
- physical status: **NO-GO**.

This file intentionally does **not** pin a PR-head SHA. PR #3675 is still moving while exact-head acceptance is being earned. Always read the live PR head and require evidence for that exact immutable head. Ancestor success does not transfer across a moved head.

If PR #3675 closes, merges, or is superseded, re-resolve the strongest current Capture candidate from GitHub instead of reviving the historical PRs named below.

## Historical evidence that remains useful

PR #833 / `a0f4a33451f61411d6e0541f2e70edea5438342d` is closed and superseded.

The historical C7D09A22 physical artifact remains evidence only. It established useful Tuya/FD50 transport-family observations and an approximately 29.93-second unauthenticated disconnect pattern, but it did **not** establish authenticated application payloads, permanent CoreBluetooth identity, verified DP meanings, battery/current/power/speed telemetry semantics, command acknowledgement, or scooter-control authority.

Historical PR #2178 and its V14 branch/head/check status are stale routing information and must not be used as the current field candidate.

## Current physical procedure

The canonical current physical procedure is:

`docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md`

The only current private field installer is:

`scripts/field/install_one_time_capture.command`

Supporting `docs/ES80_TODAY_*.md` files are retired/reference material. If they conflict with the canonical current procedure or current code, the canonical procedure and live code win.

## Physical truth boundary

Physical status remains **NO-GO** until the final composed exact software candidate earns all required software/runtime gates and the private user-owned field prerequisites are present.

The next physical rung remains a stationary, read-only authenticated attempt on the intended iPhone 12 / iOS 27 and intended scooter. It must preserve all of these boundaries:

1. exact accepted source/build provenance;
2. fresh official Tuya/SmartLife account and exact-device membership;
3. deterministic fresh-attempt `OFF1 -> ON1 -> OFF2 -> ON2` target correlation using accepted CoreBluetooth identity evidence;
4. explicit confirmation of the freshly correlated target;
5. official SmartLife SDK authentication provenance for the current BLE generation;
6. genuine same-generation application/notify evidence, not generic BLE liveness or Device Sharing alone;
7. repeated authenticated application evidence surviving beyond the historical ~30-second rejection window;
8. the retained >=45-second authenticated continuity requirement before stationary mapping can unlock;
9. immutable accepted export/seal/integrity requirements;
10. no arbitrary characteristic writes, no guessed DP semantics, no unbind/reset/OTA, and no scooter-control claim.

Simulator values, public CI, source contracts, screenshots, package greens, and historical artifacts remain software/public evidence only. They cannot become physical ES80 proof.

## Worker routing rule

A fresh worker should never start from this document alone. Read live `AGENTS.md`, current `main`, the live exact head of PR #3675 (or its strongest current successor), current checks/reviews, and the canonical physical procedure before changing code or authorizing any field step.

**Live GitHub exact-head truth wins. Physical status stays NO-GO until the current composed candidate earns it.**
