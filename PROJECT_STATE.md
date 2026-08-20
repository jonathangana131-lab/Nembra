# PROJECT STATE

Updated: 2026-08-20

Root `AGENTS.md`, current `main`, live PRs/reviews, current code/tests, and exact evidence are authoritative.

## Product direction

- Product: **Nembra**.
- Target: production-quality **Nembra 1.0**.
- Primary real hardware-validation target: **AOVOPRO ES80**.
- Baseline device/runtime where applicable: **iPhone 12 / iOS 27**.
- Physical/private Capture remains **NO-GO** until exact authority and evidence gates are genuinely satisfied.

## Execution mode

```text
TRUNK_HEALTH_MODE: builder
EXECUTION_MODE: full-blast-outcomes
NEMBRA_1_0_RELEASED: false
CAPTURE_USER_INPUT_READY: false
```

The repository-wide convergence phase is over. Broad `Go` work should now select a substantial coherent product/subsystem outcome and carry it through real source implementation, verification, evidence inspection, fixes, integration, and main verification.

Workflow-only, marker-only, test-only, materializer-only, and recovery-only changes are supporting work rather than the main outcome unless they are the only true blocker.

## Parallel lane rule

At most one implementation writer should own the tightly coupled Capture trust/signing/app-authorization/physical-session chain. Other agents should move independent Nembra 1.0 outcomes such as:

- Home / Rides product closure;
- Drive / cockpit closure;
- persistence / Settings / Navigation / runtime reliability;
- accessibility / performance / visual polish;
- release-candidate integration toward `main`.

Do not let Capture monopolize every broad Go session.

## Current integration truth

- #3678 remains a unified Nembra 1.0 integration candidate, not release acceptance.
- #3675 remains the strict Capture carrier.
- one focused active Capture lifecycle implementation path may own that root cause; do not spawn competing recovery ladders.
- ordinary accepted product work should move toward `main` rather than making this release branch a permanent second trunk.

## Execution truth

Codex quota exhaustion, one missing Mac, one connector-only chat, or one broken/queued hosted run is not a global stop. Use any real available execution path, including repository Xcode/macOS runners when available. Do not claim executable software PASS without real exact-source execution. If one outcome is genuinely blocked, preserve the exact blocker and move to another substantial independent outcome.

## Capture truth

Capture is an evidence utility supporting Nembra 1.0. Do not invent BLE/Tuya semantics or send unknown scooter writes/queries/controls. Simulator evidence is not physical truth. Private keys, credentials, account/device identifiers, signed private IPAs, and sensitive physical evidence must not be committed.

`CAPTURE_USER_INPUT_READY` may become true only when the exact read-only stationary software/build/install/signing/authorization/custody chain is accepted, physical status is no longer NO-GO, and the next unresolved blocker is specifically the owner's fresh iPhone/ES80/account Bluetooth session.

## 1.0 completion

`NEMBRA_1_0_RELEASED` may become true only after the exact bounded 1.0 candidate satisfies all applicable release gates and the intended tag/release/publication exists.

Broad Go behavior remains:

**refresh live truth -> select a BIG non-overlapping outcome -> implement real source -> execute verification -> inspect evidence -> fix -> integrate -> verify main -> refresh -> continue**