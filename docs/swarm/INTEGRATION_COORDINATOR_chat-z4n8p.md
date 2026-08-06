# Integration coordinator — chat-z4n8p

Started: 2026-08-06
Role: swarm integration/recovery coordinator
Branch: `parallel/integration-coordinator/chat-z4n8p`
Base main: `3fcf0afd090b075373cbae113a27477c10a3dc4b`

## Live boot snapshot

At claim time, no other integration-coordinator branch existed and no Actions runs were queued or in progress. Six open PR lanes were present: adaptive range core (#10), passive ES80 protocol capture (#11), ride/location lifecycle (#13), adaptive-range persistence (#16), ride transport-gap provenance (#21), and ES80 CoreBluetooth passive capture adapter (#22).

The open lanes had not produced a durable GitHub update for roughly eight hours at coordinator claim time, so they are treated as stale/recoverable unless newer branch movement appears during each pre-action refresh.

Known dependency chains:
- #16 depends on #10.
- #22 depends on #11.

Coordinator priorities:
1. repair/retarget near-ready stale lanes without writing another worker's branch;
2. merge only exact-head-green, refreshed, mergeable PRs with expected-head protection;
3. reconcile dependent lanes onto fresh main after parent merges;
4. keep global project-memory edits single-writer and defer them until integration state stabilizes.

### V5 RECOVERY CAPSULE
WORKER_ID: chat-z4n8p
LANE: integration-coordinator
ROLE: integration/reconciliation
CURRENT_HEAD: pending first checkpoint
BASE_OR_PARENT: main@3fcf0afd090b075373cbae113a27477c10a3dc4b
OWNED_FILES_OR_SUBSYSTEM: this worker-specific coordinator note; integration/recovery branches only
LAST_KNOWN_GREEN: main@3fcf0afd090b075373cbae113a27477c10a3dc4b inherited accepted merge state
CURRENT_STATE: coordinator claimed; stale PR/CI reconciliation in progress
NEXT_CONCRETE_ACTION: inspect exact current heads and gates of #21, #13, #10/#16, and #11/#22; recover or merge in dependency-safe order
DEPENDENCIES: live GitHub state and exact-head CI
KNOWN_OVERLAP: none; worker-specific doc only
BLOCKED_ON: none
HARDWARE_STATUS: coordination/software only; no physical ES80 claims
