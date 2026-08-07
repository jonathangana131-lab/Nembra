# Rolling Number Recovery — Independent Peer Review

### V8 WORKER STATE
PROTOCOL_VERSION: 8  
WORKER_ID: `chat-d8v2m`  
ROLE: PEER REVIEW / HARDENING ENGINEER  
LANE_ID: `rolling-number-recovery-independent-review-d8v2m`  
EPOCH: 1  
CONTROL_CLAIM: v8 issue #108 comment `5210989057`; v7 history #79 comment `5210969319`  
CURRENT_HEAD: this worker-only review branch  
BASE_OR_PARENT: latest policy main `871797d8e2117bd2081c5ecca42c6fb7b93ef7d5`; branch reconciliation pending this checkpoint  
OWNED_PATHS: `docs/worker-reviews/ROLLING_NUMBER_RECOVERY_INDEPENDENT_REVIEW_CHAT_D8V2M.md` only  
LOCK_CLASS: C additive  
LAST_KNOWN_GREEN: supplemental Swift 6.2.1 property/boundary/host-performance checks below; PR #95 resolver green, Xcode job queued at last meaningful inspection  
CURRENT_STATE: peer review complete/clean for PR #95 exact head `e675fb995bde98f1718ed31624253f648beb547c`; merge acceptance remains incumbent responsibility  
NEXT_PACKET: refresh #95 owner/main/CI after v8 migration; publish any changed acceptance conclusion only if evidence changed; then release/pivot if no further same-lane work remains  
DEPENDENCIES: incumbent `chat-b6r9m`; exact-final-head Xcode/Simulator + fresh-main discipline before #95 merge  
KNOWN_OVERLAP: none; this worker owns no #95 product path  
CI_STATE: #95 run `31136468286`; resolver `92736839496` green; Xcode `92736860915` queued at last meaningful inspection  
AUTOMATED_REVIEW_STATE: DISABLED_BY_DEFAULT under v8; not requested and not a blocker  
PEER_REVIEW_STATE: COMPLETE/CLEAN; PR #95 comment `5210975045`  
SERVICE_DEGRADATIONS: prior GitHub text-write secondary limit recovered; Xcode runner queue remains independently degraded/queued  
BLOCKED_ON: none for peer-review work  
HARDWARE_STATUS: software presentation/performance review only; no physical AOVOPRO ES80 or physical-iPhone performance claim  
HANDOFF_READY: true

## Coordination boundary

Incumbent `chat-b6r9m` retains all PR #95 product paths:

- `Packages/NembraCore/Sources/NembraCore/RollingNumberModel.swift`
- `Packages/NembraCore/Tests/NembraCoreTests/RollingNumberPerformanceHardeningTests.swift`
- `docs/ROLLING_NUMBER_PERFORMANCE.md`

This worker does not edit or take over those paths.

## Review target / isolation

- PR: #95
- reviewed head: `e675fb995bde98f1718ed31624253f648beb547c`
- exact changed-file inventory: the three incumbent paths above, no fourth path
- main observed after the candidate reconciliation: `8dcf1459bd9152a94d6616fe1597e4a835a4972a`; its product movement after #95's `60d8ecc...` base was exactly three additive route-summary paths with zero rolling-number overlap
- subsequent `871797d8...` main movement is Swarm OS v8 policy only and does not overlap #95 product paths
- GitHub reports #95 mergeable, but its cached generated merge candidate was based on the older `60d8ecc...`; that is not fresh-main acceptance evidence

## Source/API/build-graph verdict

No source-level blocker found on `e675fb995...`.

Checked boundaries:

- `snapshot(scaledValue:)` is presentation-only and capacity-bounded.
- Fixed-slot extraction preserves most-significant-to-least-significant digit order.
- Hidden leading integer placeholders and always-visible fractional slots remain coherent.
- Supported layouts cap total digit slots at 15; supported scaled integer values remain below `10^15` and below `2^53`, so delegating the existing Double quantization path into the UInt64 path does not add an integer-representation precision hole.
- Transition work remains bounded to fixed digit-slot count, with roll steps in `0...9` and display-only direction semantics.
- Live Dashboard still consumes `snapshot(for:)`; the new exact-integer overload is additive and does not silently alter current speed behavior.
- Adjacent PR #33 explicitly leaves `RollingSpeedValueView` and `RollingNumberModel` untouched.
- Battery-primary-readout PR #57 does not consume `RollingNumberModel` and explicitly defers final integer battery-roll animation.
- Current `Nembra.xcodeproj/project.pbxproj` already wires `RollingNumberModel.swift` into the app target PBX Sources phase, so no project-file edit is required.

### Public API compatibility

Exact base and #95 source were compared directly. Every pre-existing public declaration keeps its signature. The only new public symbol is additive:

`public func snapshot(scaledValue: UInt64) throws -> RollingNumberSnapshot`

No replacement API or wire-format migration is introduced.

## Independent supplemental verification

A standalone Swift 6.2.1 mirror of the exact algorithm passed **1,238,191 property checks** across valid layouts, digit extraction/visibility, exact-scaled vs Double-path equivalence, transition direction/step bounds, and 15-slot boundaries.

A second old-vs-new Swift 6.2.1 boundary harness passed **294 / 294 comparisons with zero behavior differences** around scaled rounding thresholds, capacity edges, signed zero/tiny values, invalid numeric inputs, fractional layouts, and 15-slot cases.

### Directional host performance probe

An optimized Swift 6.2.1 alternating-order benchmark preserved identical checksums over five 400,000-snapshot rounds per layout:

| Total slots | Old median | New median | New / old |
| ---: | ---: | ---: | ---: |
| 2 | 26.465 ms | 22.956 ms | 0.867 |
| 4 | 26.368 ms | 24.072 ms | 0.913 |
| 15 | 34.162 ms | 30.692 ms | 0.898 |

Directional host evidence only. It rules out an obvious host regression but is not iPhone 12 profiling, Simulator acceptance, or physical-device proof.

## Acceptance truth

At the last meaningful inspection, exact-head workflow run `31136468286` targeted `e675fb995...`:

- trusted same-repo resolver `92736839496`: success
- Xcode 27 build/test/capture `92736860915`: queued

Therefore the peer review is clean, but #95 is **not merge-accepted** from this evidence alone. Green ancestor or resolver status cannot substitute for exact-final-head Xcode/Simulator evidence. If main remains ahead when the frozen candidate becomes terminal, the incumbent must reconcile as required by v8 dependency/release discipline and gate the resulting exact final SHA.

## Durable publication

- v7 control registration: #79 comment `5210969319`
- v8 migration/claim: #108 comment `5210989057`
- PR #95 independent peer-review verdict: comment `5210975045`
