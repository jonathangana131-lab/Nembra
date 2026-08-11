# Nembra Swarm — `Go` Entrypoint

This is the short bootstrap for a fresh GPT-5.6 Sol worker when the user says **Go**, **continue**, **keep going**, or otherwise asks Nembra development to advance without assigning a specific lane.

## Do not ask the user to coordinate the swarm

The worker must recover live truth itself. The user should not need to know PR numbers, lane IDs, branch names, claim generations, or which specialist is needed next.

## Fresh-worker boot sequence

1. Inspect current GitHub `main`, current open PRs/branches, recent commits, and current CI/Xcode results. Product GitHub truth outranks stale prose.
2. Read `.swarm/config.json` from trusted product source and validate its supported schema.
3. Inspect the long-lived `swarm-state` branch: lanes, claims, workers, resources, important events, and newest handoffs.
4. Read `docs/SWARM_CONTROL_PLANE.md` when control-plane behavior or recovery details are needed.
5. Register a unique worker ID matching `sol-YYYYMMDD-<unique>`; GitHub account identity is not worker identity.
6. Ask the scheduler for the current recommendations. It is valid for the result to be empty.
7. Choose the highest-value safe recommendation that matches current product truth. Do not duplicate already-owned work.
8. **Claim first. Branch second.** A recommendation is advisory; only a successful atomic claim grants ownership.
9. If the claim fails because another worker won, refresh state and choose again. Do not create a duplicate branch/PR.
10. Acquire required scarce resources in configured order before using them. Do not hold Xcode/Simulator/device/physical resources while idle.
11. Work only inside the lane's declared write scope unless a durable scope-change record is created.
12. Heartbeat at meaningful checkpoints, not by aggressive polling. Publish durable events for blockers, findings, decisions, review results, handoffs, takeovers, and evidence.
13. Respect dependencies, project/epic blockers, project/per-epic WIP limits, review backpressure, integration backpressure, and RED-main repair priority.
14. Review roles must be independent when the lane requires it. The implementation worker cannot accept its own work.
15. Simulator success, source review, and CI success never create physical scooter authority. Physical NO-GO remains NO-GO until legitimate physical evidence changes it.
16. Validate the exact candidate head before acceptance. Existing Nembra Xcode/Simulator/exact-head gates remain authoritative for product changes.
17. When a slice is accepted, publish a handoff, release claims/resources, update durable lane state, and immediately inspect the next useful recommendation.
18. If nothing useful is runnable, idle cleanly. Do not manufacture work merely to keep workers busy.

## Normal user interaction

For ordinary continuation, the user should be able to say simply:

> **Go**

The worker should then perform the boot sequence above and advance the repository without asking the user to manually assign agents or summarize previous work.

If the user gives a specific goal instead, use the same control plane but prefer work that advances that goal without violating current ownership, dependencies, safety, or exact-head truth.

## Authority boundaries

- Trusted product/control code and `.swarm/config.json` live with product source.
- High-churn coordination state lives on `swarm-state`.
- Lane/claim/resource/event/handoff records plus live GitHub product state are authoritative.
- Generated dashboards and human-readable routing summaries are caches, never scheduler authority.
- GitHub Contents API compare-and-swap semantics are the atomic boundary for claims and short scheduler-mutation guards.

Never bypass these rules just because a stale document or old issue points somewhere else.
