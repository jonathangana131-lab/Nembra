# Rolling Number Recovery — Independent Review Lease

PROTOCOL_VERSION: 7  
WORKER_ID: `chat-d8v2m`  
ROLE: REVIEW / HARDENING  
LANE_ID: `rolling-number-recovery-independent-review-d8v2m`  
EPOCH: 1  
STATE: active read-only review; GitHub issue/review comment creation is temporarily secondary-rate-limited  

## Coordination boundary

This worker owns **no product/source/test/workflow path** in PR #95. Incumbent `chat-b6r9m` retains:

- `Packages/NembraCore/Sources/NembraCore/RollingNumberModel.swift`
- `Packages/NembraCore/Tests/NembraCoreTests/RollingNumberPerformanceHardeningTests.swift`
- `docs/ROLLING_NUMBER_PERFORMANCE.md`

This file is a worker-specific Class-C durable checkpoint on the isolated lease branch only. It is not a substitute for the v7 control-issue message bus; the normal control claim/review should be posted when GitHub comment creation accepts writes again.

## Review target / isolation

- PR: #95
- reviewed head: `e675fb995bde98f1718ed31624253f648beb547c`
- exact PR changed-file inventory: the three incumbent paths listed above, no fourth path
- live main at latest refresh: `8dcf1459bd9152a94d6616fe1597e4a835a4972a`
- `60d8ecc... -> 8dcf145...` main movement changes exactly three additive route-summary paths (`RideRouteEvidenceSummary.swift`, its test, and its doc), with zero rolling-number overlap.
- GitHub reports PR #95 mergeable, but its cached/generated merge candidate is still based on `60d8ecc...`; it is therefore not treated as fresh-main acceptance evidence.

## Source/API review result

No source-level blocker found on `e675fb995...`.

Checked boundaries:

- `snapshot(scaledValue:)` is presentation-only and capacity-bounded.
- Fixed-slot extraction preserves most-significant-to-least-significant digit order.
- Hidden leading integer placeholders and always-visible fractional slots remain coherent.
- Supported layouts are capped at 15 total digit slots; every supported integer scaled value is below `10^15`, comfortably below `2^53`, so delegating the existing Double-quantization path into the UInt64 snapshot path does not introduce a new integer-representation precision hole.
- Transition work remains bounded to fixed digit-slot count, with roll steps in `0...9` and direction based only on display-scaled ordering.
- Live Dashboard still consumes `snapshot(for:)`; the new exact-integer overload is additive and does not silently alter current speed behavior.
- Adjacent PR #33 explicitly leaves `RollingSpeedValueView` and `RollingNumberModel` untouched, so no current same-path integration collision was found.
- Current battery-primary-readout PR #57 does not reference `RollingNumberModel`; it explicitly defers final integer battery-roll animation, so #95 does not create a hidden immediate parent/API dependency there.

## Independent supplemental verification

A standalone Swift 6.2.1 mirror of the exact rolling-number algorithm passed **1,238,191 property checks** covering:

- valid layout boundaries;
- digit extraction and visibility;
- exact scaled vs Double-path equivalence across supported ranges;
- transition direction and bounded roll steps;
- largest 15-slot boundary cases.

A second old-vs-new Swift 6.2.1 boundary harness passed **294 / 294 comparisons with zero behavior differences** across:

- `.5` scaled rounding thresholds plus adjacent `nextDown` / `nextUp` values;
- exact and adjacent capacity values;
- zero / negative-zero / tiny positive and negative inputs;
- negative values;
- positive/negative infinity and NaN;
- representative 15-slot and fractional layouts.

### Directional host performance probe

A separate optimized Swift 6.2.1 benchmark alternated old/new execution order over five 400,000-snapshot rounds per layout and preserved identical result checksums. Median results:

| Total slots | Old median | New median | New / old |
| ---: | ---: | ---: | ---: |
| 2 | 26.465 ms | 22.956 ms | 0.867 |
| 4 | 26.368 ms | 24.072 ms | 0.913 |
| 15 | 34.162 ms | 30.692 ms | 0.898 |

This is directional host evidence only. It supports the source-level allocation/CPU premise and rules out an obvious host regression, but it is **not** iPhone 12 profiling, Simulator acceptance, or a physical-device performance claim.

## CI truth

Exact-final-head workflow run `31136468286` targets `e675fb995...`.

- trusted same-repo resolver job `92736839496`: success
- Xcode 27 build/test/capture job `92736860915`: queued at latest meaningful inspection

Another lane's Xcode retry was observed canceled before receiving a self-hosted runner, so shared scheduler/concurrency churn exists; this does not turn #95 green or red.

Therefore source review is clean but **merge acceptance is not yet green**.

Because `main` advanced after this candidate was frozen, final acceptance still requires fresh-main discipline: preserve the candidate while its queued run is alive; after terminal diagnostic evidence, incumbent/coordinator should reconcile the non-overlapping main movement and obtain exact-final-head QA on the resulting candidate if v7 merge discipline still requires the fresh-main SHA.

## Hardware boundary

Software presentation/performance review only. No physical AOVOPRO ES80 behavior and no physical-iPhone performance result is claimed.

## Next packet

1. re-scan control issue / PR #95 for owner or reviewer movement;
2. inspect exact Xcode job after meaningful runner-state change, not by busy-polling;
3. retry normal v7 control-issue claim and PR review publication when GitHub content creation is no longer rate-limited;
4. do not mutate PR #95 source or branch.