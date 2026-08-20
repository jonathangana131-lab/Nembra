# Nembra autonomous milestone status

Updated: 2026-08-19

These flags are deliberately simple so humans, ChatGPT/Codex sessions, and milestone watchers can determine whether the user needs to be contacted without interpreting old branch prose.

```text
NEMBRA_1_0_RELEASED: false
CAPTURE_USER_INPUT_READY: false
```

## Meaning of `NEMBRA_1_0_RELEASED`

Set to `true` only when all of the following are true on current GitHub truth:

1. the bounded Nembra 1.0 product is integrated on the exact release source;
2. all applicable release blockers and acceptance gates are genuinely satisfied with honest evidence;
3. physical/BLE claims remain evidence-backed and no required P0/P1 release blocker is knowingly open;
4. the intended Nembra 1.0 release/tag/publication exists according to current release policy.

A draft release PR, a large unified branch, development-main merge, green subset of tests, or Simulator-only success is not enough.

When this flag becomes true, update the release/project state and GitHub release notes in the same integration window so future sessions can report the release without guessing.

## Meaning of `CAPTURE_USER_INPUT_READY`

Set to `true` only when current GitHub truth shows all of the following:

1. the intended Nembra Capture **read-only stationary** software carrier is source-complete and accepted for the physical rung;
2. exact build/install/signing/authorization/custody requirements needed before the session are satisfied;
3. the app path that will collect and preserve the required evidence is ready and the safe current procedure is documented;
4. physical status is no longer `NO-GO` for that exact read-only attempt;
5. the next unresolved blocker is specifically a fresh user-owned iPhone/scooter/account Bluetooth session or evidence that only the user can provide.

Do not set this true merely because code can scan BLE, because a draft says “next physical rung,” because Simulator/CI passes, or because a historical capture exists.

When this flag becomes true, the same change/handoff must record:

- exact accepted source/build identity;
- exact safe stationary procedure;
- what the user must provide/do;
- what remains forbidden (especially writes/queries/commands not explicitly authorized);
- how the resulting private/sensitive evidence must be handled.

## Current truth at creation

- `main` is still the post-swarm-cutover development trunk at `0bc188e41c10e4deb7e8c2d214e216f6ea5b24e6`.
- Draft PR #3678 is the current large Nembra 1.0 unified integration candidate; it is not release acceptance.
- Draft PR #3675 is the current Capture/Bluetooth checkpoint; it explicitly reports physical/private Capture as **NO-GO** because production trust/app capability/private physical evidence are not complete.
- Therefore both flags are correctly `false` today.

Every broad autonomous `Go` run should re-evaluate these flags after meaningful integration and before final handoff. Live GitHub/evidence outranks this timestamped prose if it becomes stale.
