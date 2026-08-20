# Nembra autonomous milestone status

Updated: 2026-08-20

These flags are deliberately simple so humans, ChatGPT/Codex sessions, and milestone watchers can determine whether the owner needs to be contacted without interpreting stale branch prose.

```text
NEMBRA_1_0_RELEASED: false
CAPTURE_USER_INPUT_READY: false
TRUNK_HEALTH_MODE: builder
EXECUTION_MODE: full-blast-outcomes
```

Live GitHub always outranks this snapshot. Root `AGENTS.md` defines execution behavior.

## `NEMBRA_1_0_RELEASED`

Set to `true` only when the bounded Nembra 1.0 product is integrated on the exact release source, all applicable release blockers/acceptance gates are genuinely satisfied, physical/BLE claims remain evidence-backed, and the intended 1.0 tag/release/publication exists.

A draft release PR, a large branch, development-main merge, green subset of tests, or Simulator-only success is not enough.

When this flag becomes true, update project/release state and GitHub release notes in the same integration window.

## `CAPTURE_USER_INPUT_READY`

Set to `true` only when all software-side prerequisites for the intended **read-only stationary** Capture attempt are genuinely accepted, including exact build/install/signing/authorization/custody requirements, the real app evidence path, and a safe documented procedure; physical status must no longer be `NO-GO`, and the next unresolved blocker must specifically be the owner's fresh iPhone/scooter/account Bluetooth session.

Do not set it true because code can scan BLE, a draft says `next physical rung`, a workflow is green, or historical capture data exists.

When this flag becomes true, record the exact accepted source/build, safe stationary procedure, what the owner must do/provide, what remains forbidden, and private-evidence handling.

## Current execution/health truth

At this update:

- development `main` has moved to the full-blast policy line;
- the open PR queue is small enough for builder mode;
- #3675 remains the active strict Capture carrier and physical/private Capture remains **NO-GO**;
- #3678 remains the unified Nembra 1.0 integration candidate and is not release acceptance;
- one focused Capture SecureLink lifecycle implementation path may own that root cause; do not spawn competing Capture implementation children;
- strict Capture branch divergence alone is not a reason to starve independent Nembra 1.0 product work.

Broad `Go` agents should choose substantial non-overlapping outcomes and carry them through real source implementation, execution, evidence inspection, fixes, integration, and main verification. One writer may own the sensitive Capture authority chain while other agents advance independent Home/Rides, Drive/cockpit, persistence/settings/navigation/runtime, accessibility/performance, and release-integration outcomes.

Workflow-only, marker-only, test-only, and recovery-only PRs do not count as primary broad-Go progress unless they are the only true blocker to a larger outcome.

## Current milestone truth

- `NEMBRA_1_0_RELEASED: false`
- `CAPTURE_USER_INPUT_READY: false`
- physical/private Capture: **NO-GO**

Every broad autonomous run should re-evaluate these flags after meaningful integration and before final handoff.