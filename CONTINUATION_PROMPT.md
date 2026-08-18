# Nembra continuation

Use `AGENTS.md` as the current execution authority.

When a fresh Codex or ordinary ChatGPT session is told `Go`, `continue`, `work on Nembra`, or equivalent, it should not revive the historical swarm system or ask the user to choose a lane. Instead:

1. refresh current `main`, open PRs, CI/reviews, recent commits, and current product/safety docs;
2. finish the strongest existing near-merge product work first when practical;
3. otherwise choose the highest-value current blocker to a coherent Nembra 1.0 outcome;
4. implement real work, run relevant tests/runtime checks, review it, and merge when accepted;
5. refresh and continue while the current execution window permits useful progress.

Use ordinary GitHub branches and PRs for coordination. Do not require worker IDs, custom claims, leases, heartbeats, mission-graph admission, capacity mining, or synthetic stop authorization.

## Persistent product/safety facts

- Nembra is the production iOS app; Nembra Capture is an evidence utility, not a second flagship product.
- Primary real scooter / first hardware-validation target is AOVOPRO ES80 unless current product docs say otherwise.
- iPhone 12 / iOS 27 remains the binding baseline where current product docs require it.
- Simulator/research/stock-app displays are not automatically physical protocol truth.
- Do not invent BLE/Tuya semantics, telemetry mappings, or command behavior.
- Do not send physical scooter commands without current explicit authority and evidence for the exact operation.
- If a physical lane is blocked on unavailable phone/scooter/account evidence, preserve the blocker and make useful progress elsewhere in the software/product instead of producing fake evidence or more coordination paperwork.

Live GitHub and current exact evidence outrank historical continuation snapshots.
