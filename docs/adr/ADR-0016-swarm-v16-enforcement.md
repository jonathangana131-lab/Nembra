# ADR-0016 — Swarm V16 trusted-base enforcement

Status: **Accepted**  
Date: 2026-08-11  
Scope: engineering coordination only; no change to Nembra product or physical authority.

## Context

ADR-0015 chose a GitHub-native hybrid architecture: trusted control code on product `main`, high-churn runtime state on `swarm-state`, deterministic claim paths for atomic ownership, expiring leases, generation-fenced takeover, structured events/handoffs, dependency routing, resource leases, and gradual rollout.

The shadow phase proved the core mechanics, including deterministic 30-worker races and real GitHub Contents API create/CAS conflicts. It also exposed the remaining gap: shadow warnings could not mechanically stop newly created work from bypassing ownership, and generated dashboard state was not cryptographically bound to one exact authoritative runtime snapshot.

Nembra also has a very large pre-V16 Capture backlog. Hard-requiring new metadata retroactively on those existing PRs would destroy useful lineage and conflict with the migration goal.

## Decision

Promote Nembra to **enforced coordination for PRs created at or after the configured V16 cutoff**, while grandfathering earlier PRs by creation time.

New controlled work must pass a trusted-base validation path that:

1. loads control code/config from the PR base generation;
2. materializes the exact current `swarm-state` runtime snapshot;
3. validates the authoritative state;
4. creates/verifies a SHA-256 validation fence for that snapshot;
5. requires exact lane/slot/worker/generation/branch ownership;
6. enforces lane write scope;
7. enforces every scarce resource declared by the slot.

The PR's own modified validator is never used as its authority. The first V16 installation PR is a one-generation bootstrap exception: the previous trusted base can observe its metadata, but cannot grant itself V16 authority. After merge, every new PR uses the trusted V16 base implementation.

A scheduled/push projection job renders dashboard/metrics/fence from one exact `swarm-state` head and performs a branch-head compare immediately before publication. If runtime state advanced, publication refuses rather than overwriting newer coordination truth.

Add a mechanical state-side stop proof that refuses intentional idle while safe scheduler work, stale recoverable ownership, review backlog, or integration backlog remains. Live GitHub reconciliation remains mandatory because runtime state alone cannot prove the absence of unrecorded branches/PRs.

## Invariants retained

- claim first, branch second;
- at most one live owner per exclusive slot;
- takeover increments generation and fences old owners;
- workers are peer GPT-5.6 Sol sessions with temporary roles;
- dependencies and malformed/unknown state fail closed;
- generated state is never ownership authority;
- resource leases use deterministic acquisition order;
- implementer and accepting reviewer are independent worker identities when required;
- no scheduler transition can create `PHYSICAL_GO`;
- Simulator/CI/Xcode success never becomes physical scooter evidence;
- no arbitrary executable text is accepted from swarm runtime state;
- no secrets or private credentials are stored in control records.

## Legacy policy

The cutoff is a migration boundary, not a loophole. Existing pre-cutoff Capture PRs may continue under explicit grandfathering and reconciliation. Newly created work after the cutoff requires the V16 ownership metadata and live claim path.

If a legacy PR is superseded or re-created after the cutoff, the new PR is controlled work and must use V16 ownership.

## Acceptance

V16 is not considered fully proven by its installation PR alone. Required closure is:

- exact-head control-plane tests green;
- deterministic 30-worker race green;
- product/Xcode QA unaffected;
- V16 merged to trusted `main`;
- generated state projection published and digest fence verified;
- a fresh post-merge worker performs claim-first ownership;
- a fresh post-cutoff PR passes the trusted-base V16 enforcement path;
- the proof lane/claims/resources are then released cleanly.

Only after that post-merge proof should V16 be treated as the enforced operational generation.
