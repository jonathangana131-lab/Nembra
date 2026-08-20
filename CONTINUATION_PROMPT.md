# Nembra continuation

Use root `AGENTS.md` as the current execution authority.

When a fresh Codex or ordinary ChatGPT session is told `Go`, `continue`, `keep going`, `work on Nembra`, `finish Nembra`, or equivalent, it should not revive the historical swarm system, ask the user to choose a lane, or stop because one execution environment is unavailable. Instead:

1. refresh current `main`, open PRs, recent merges, current reviews/check results, and current product/safety/release docs;
2. read `docs/AUTONOMY_STATUS.md` for milestone flags, but let live GitHub/evidence outrank stale prose;
3. finish/converge the strongest existing near-merge product work first when practical;
4. otherwise choose the highest-value current blocker to a coherent Nembra 1.0 outcome;
5. implement real work and run relevant checks directly when execution exists;
6. if this is a connector-only session, use exact-source review and the `AGENTS.md` development-main fast path for source-complete ordinary development rather than parking everything behind unavailable Codex/Xcode/Actions;
7. never call execution-pending work a PASS, and never bypass physical BLE/Tuya, signing/key-custody, real-device, visual/accessibility/performance, release, or known fail-first/source-incomplete gates;
8. integrate accepted development work, verify/fix `main`, refresh, and continue while useful work remains in the current turn.

Use ordinary GitHub branches and PRs for coordination. Do not require worker IDs, custom claims, leases, heartbeats, mission-graph admission, capacity mining, fixed writer quotas, or synthetic stop authorization.

## Persistent product/safety facts

- Nembra is the production iOS app; Nembra Capture is an evidence utility supporting Nembra, not a second flagship product.
- Current first physical-validation target is **AOVOPRO ES80** unless newer live product docs explicitly change it.
- iPhone 12 / iOS 27 remains the binding baseline where current product/release docs require it.
- Simulator/research/stock-app displays are not automatically physical protocol truth.
- Do not invent BLE/Tuya semantics, telemetry mappings, or command behavior.
- Do not send physical scooter commands without current explicit authority and evidence for the exact operation.
- If a physical lane is blocked on unavailable phone/scooter/account evidence, preserve the blocker and make useful progress elsewhere instead of producing fake evidence or coordination paperwork.

## Milestones future chats must report

`docs/AUTONOMY_STATUS.md` owns two explicit milestone flags:

- `CAPTURE_USER_INPUT_READY`: true only when the accepted read-only stationary Capture build/procedure is software-ready and the next unresolved blocker is the user's fresh physical iPhone/scooter/account Bluetooth session. When it first becomes true, tell the user clearly what is needed and cite the accepted source/procedure.
- `NEMBRA_1_0_RELEASED`: true only after exact release acceptance and the intended 1.0 release/tag/publication. When it becomes true, report that Nembra 1.0 is actually released, not merely merged or candidate-ready.

Until those conditions are truly met, keep the flags false and continue software/product development.

Live GitHub and current exact evidence outrank historical continuation snapshots.
