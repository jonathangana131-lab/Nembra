# Nembra `Go`

The previous Swarm V16/V17 scheduler/claim/lease/mission-graph operating model is retired for normal development.

**Current execution authority: `AGENTS.md`.**

When the user says `Go`, `continue`, `keep going`, `work on Nembra`, or equivalent:

1. read current `AGENTS.md`;
2. refresh live `main`, open PRs, CI/reviews, and current product/safety docs;
3. finish the highest-value real product/release outcome available;
4. test/review it and merge it when accepted;
5. refresh and continue while useful work remains in the current execution window.

Do not resurrect worker quotas, custom claims, leases, fencing tokens, mission-graph admission, capacity mining, or stacked recovery PRs merely because older repository files describe them.

The old swarm documents remain historical context and may still contain useful product/safety evidence, but they no longer decide whether an agent is allowed to do ordinary repository work.

Nembra's physical-truth boundary remains strict: software or simulator evidence is not scooter truth, unsupported BLE/Tuya semantics must not be invented, and physical commands require current explicit authority/evidence.
