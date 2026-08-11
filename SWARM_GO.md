# Nembra Swarm — `Go` Entrypoint

This is the short bootstrap for a fresh GPT-5.6 Sol worker when the user says **Go**, **continue**, **keep going**, or otherwise asks Nembra development to advance without assigning a specific lane.

## Do not ask the user to coordinate the swarm

The worker must recover live truth itself. The user should not need to know PR numbers, lane IDs, branch names, claim generations, or which specialist is needed next.

## Green is evidence, not completion

A `Go` worker is an **advance-the-repository worker**, not a status reporter. Seeing green CI, a green exact-head run, a clean `main`, an already-merged PR, a completed review, or one finished slice is never by itself a reason to stop.

An inspection-only `Go` turn is invalid unless the stop gate below is actually satisfied. After every green check, merge, review, handoff, blocker, lost claim, or completed slice, refresh live truth and continue to the next useful claim.

If a lane is waiting on CI/review/external evidence and another safe scheduler recommendation is available, do not spend the whole turn merely watching the wait. Preserve the first lane's ownership/evidence correctly, release any idle scarce resources, and advance another non-conflicting recommendation or reconciliation shard when policy permits.

## Fresh-worker boot sequence

1. Inspect current GitHub `main`, current open PRs/branches, recent commits, and current CI/Xcode results. Product GitHub truth outranks stale prose.
2. Read `.swarm/config.json` from trusted product source and validate its supported schema.
3. Inspect the long-lived `swarm-state` branch: lanes, claims, workers, resources, important events, and newest handoffs.
4. Reconcile live GitHub work against `swarm-state` before trusting the ready queue. If meaningful open PRs/branches/failed-main work are missing, stale, duplicated, or superseded in state, perform or claim a bounded scheduler-reconciliation shard first: group work by real objective/exact lineage, preserve salvageable heads, record superseded lineages, and create/update only the minimum durable lane records needed. Never bulk-import every duplicate PR as independent work, and never silently treat an already-owned reconciliation slot as proof that no work exists—claim another available reconciliation shard or another recommendation.
5. Read `docs/SWARM_CONTROL_PLANE.md` when control-plane behavior or recovery details are needed.
6. Register a unique worker ID matching `sol-YYYYMMDD-<unique>`; GitHub account identity is not worker identity.
7. Ask the scheduler for the current recommendations. An empty result is a prompt to re-check reconciliation/ownership/blockers, not an automatic success condition.
8. Choose the highest-value safe recommendation that matches current product truth. Do not duplicate already-owned work.
9. **Claim first. Branch second.** A recommendation is advisory; only a successful atomic claim grants ownership.
10. If the claim fails because another worker won, refresh state and choose again. Do not create a duplicate branch/PR and do not stop merely because the first claim lost a race.
11. Acquire required scarce resources in configured order before using them. Do not hold Xcode/Simulator/device/physical resources while idle.
12. Work only inside the lane's declared write scope unless a durable scope-change record is created.
13. Heartbeat at meaningful checkpoints, not by aggressive polling. Publish durable events for blockers, findings, decisions, review results, handoffs, takeovers, and evidence.
14. Respect dependencies, project/epic blockers, project/per-epic WIP limits, review backpressure, integration backpressure, and RED-main repair priority.
15. Review roles must be independent when the lane requires it. The implementation/repair/reconciliation worker cannot accept its own work.
16. Simulator success, source review, and CI success never create physical scooter authority. Physical NO-GO remains NO-GO until legitimate physical evidence changes it.
17. Validate the exact candidate head before acceptance. Existing Nembra Xcode/Simulator/exact-head gates remain authoritative for product changes.
18. When a slice is accepted, publish a handoff, release claims/resources, update durable lane state, then **loop back to steps 1, 3, and 7 in the same Go turn** and take the next useful recommendation.
19. When a slice is blocked, record the blocker/handoff, release anything that should not remain held, then **loop back and look for another safe recommendation** instead of ending the turn at the blocker.
20. Continue this work loop until the stop gate below is satisfied.

## Stop gate — all conditions required

A `Go` worker may stop only after a fresh final reconciliation pass against the **current** `main` SHA shows all of the following:

- there is no safe unowned scheduler recommendation it can claim;
- no meaningful open PR, branch, failed-main repair, review/integration opportunity, or reconciliation family is missing from `swarm-state`;
- no apparently unavailable slot is merely stale/expired ownership that is legally takeable;
- all remaining useful work is actively owned, policy-blocked, dependency-blocked, resource-blocked, or externally blocked;
- any newly discovered blocker, missing work, supersession, or handoff has been written durably before exit.

If those conditions are true, publish a durable `EVIDENCE_RESULT` describing the current main SHA, refreshed queue result, and why every remaining useful objective is owned or blocked, then idle cleanly. **“CI is green,” “main is green,” “the PR is merged,” “my slice passed,” or “the first recommendation was unavailable” are never valid stop proofs.**

## Normal user interaction

For ordinary continuation, the user should be able to say simply:

> **Go**

The worker should then perform the boot sequence and work loop above, advancing the repository without asking the user to manually assign agents or summarize previous work.

If the user gives a specific goal instead, use the same control plane but prefer work that advances that goal without violating current ownership, dependencies, safety, or exact-head truth.

## Authority boundaries

- Trusted product/control code and `.swarm/config.json` live with product source.
- High-churn coordination state lives on `swarm-state`.
- Lane/claim/resource/event/handoff records plus live GitHub product state are authoritative.
- Generated dashboards and human-readable routing summaries are caches, never scheduler authority.
- GitHub Contents API compare-and-swap semantics are the atomic boundary for claims and short scheduler-mutation guards.

Never bypass these rules just because a stale document or old issue points somewhere else.
