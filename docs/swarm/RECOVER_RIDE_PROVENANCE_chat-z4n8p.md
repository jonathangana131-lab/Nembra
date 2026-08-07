# Ride provenance recovery — chat-z4n8p

Recovered from stale PR #21 head `741a766edcbac31bb18a062dc2f6449bf60d9468`.

## CI failure diagnosis

Xcode 27 run `31101170525` passed project structure validation and all 227 NembraCore package tests, then failed app-target compilation because the app manually compiles selected NembraCore sources and did not include the newly added standalone `RideTransportGapEvidence.swift` file.

The recovery keeps the exact tri-state transport-gap evidence semantics but relocates the declaration into already-compiled `RideCheckpointCoordinator.swift` and removes the standalone file atomically. No `project.pbxproj` change is required.

## Truth boundary

This is software integration evidence only. It does not verify AOVOPRO ES80 disconnect/reconnect behavior and does not add or change motorized-hardware writes.

### V5 RECOVERY CAPSULE
WORKER_ID: chat-z4n8p
LANE: recover-ride-provenance
ROLE: integration/recovery
CURRENT_HEAD: set by this checkpoint commit
BASE_OR_PARENT: stale #21 head 741a766edcbac31bb18a062dc2f6449bf60d9468
OWNED_FILES_OR_SUBSYSTEM: ride transport-gap provenance recovery/integration
LAST_KNOWN_GREEN: NembraCore package tests 227/227 on 741a766edcbac31bb18a062dc2f6449bf60d9468
CURRENT_STATE: target-visibility repair prepared; exact-head Xcode 27 gate requested by this feature-branch checkpoint
NEXT_CONCRETE_ACTION: inspect exact-head Xcode 27 Simulator QA; reconcile current main before merge
DEPENDENCIES: current main
KNOWN_OVERLAP: inherited PR #21 ride/checkpoint evidence files
BLOCKED_ON: exact-head CI
HARDWARE_STATUS: software-only; physical ES80 transport behavior remains unverified
