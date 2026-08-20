# Nembra autonomous milestone status

Updated: 2026-08-19

These flags are deliberately simple so humans, ChatGPT/Codex sessions, and milestone watchers can determine whether the user needs to be contacted without interpreting old branch prose.

```text
NEMBRA_1_0_RELEASED: false
CAPTURE_USER_INPUT_READY: false
TRUNK_HEALTH_MODE: convergence
```

`TRUNK_HEALTH_MODE` is an operational health hint, not a release or physical-authority flag. Live GitHub always outranks this line. Root `AGENTS.md` defines when agents must enter/exit convergence mode.

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

## Current trunk-health snapshot

At this update, Nembra is intentionally in **CONVERGENCE MODE**:

- development `main` is `d8d2053549cb87b35f98280f8c749437ecb74efe`;
- there are 9 open PRs;
- draft PR #3675 (Capture carrier) is 210 commits / 241 changed files against `main` and has accumulated substantial ordinary software work off-trunk;
- draft PR #3678 (Nembra 1.0 unified candidate) is 83 commits / 218 changed files against `main`;
- several open child PRs target the Capture carrier rather than `main`.

That exceeds the trunk-health signals in root `AGENTS.md`. Broad `Go` agents should therefore prioritize shrinking the open queue, closing superseded children, and transplanting/integrating coherent safe development slices onto `main` before creating ordinary new work.

This does **not** mean merging the entire Capture authority chain blindly. Live trust roots, signing/private-key authority, physical authorization, scooter operations, and exact physical evidence remain strict. Fail-closed/non-authorizing foundations and ordinary product/UI/runtime slices should not be trapped off-trunk merely because the strict physical chain is unfinished.

When the queue/divergence becomes healthy again, change `TRUNK_HEALTH_MODE` to `normal` in the same integration window.

## Current milestone truth

- Draft PR #3678 remains a Nembra 1.0 unified integration candidate; it is not release acceptance.
- Draft PR #3675 remains the active Capture/Bluetooth carrier and still reports physical/private Capture as **NO-GO**.
- Therefore `NEMBRA_1_0_RELEASED` and `CAPTURE_USER_INPUT_READY` are both correctly `false` today.

Every broad autonomous `Go` run should re-evaluate these flags after meaningful integration and before final handoff. Live GitHub/evidence outranks this timestamped prose if it becomes stale.