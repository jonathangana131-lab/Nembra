# Adaptive Range Primary Presentation — V14

## Purpose

This contract defines when Nembra may place a learned-range number in an unqualified primary battery/range readout.

It is presentation policy only. It does not decode battery transport, establish ES80 SoC semantics, choose distance evidence, train the range model, or create physical vehicle truth.

## Owner-bound authority input

The policy consumes only `AdaptiveBatteryRangeLiveEstimate`.

It deliberately does not accept a caller-selected `BatteryEvidenceStreamValidator`, whole-vehicle availability, a caller-selected freshness enum, or a raw `AdaptiveBatteryRangeEstimate`.

The live estimate carries the opaque process-local currentness lease minted by the owning `AcceptedBatterySOCStream`. Presentation asks only `liveEstimate.isCurrent`. When the real owner crosses a proven gap or advances chronology, previously minted leases are revoked. Copying an older validator or replaying matching receipt metadata under another owner cannot re-mint that currentness.

Consequences:

- a marked evidence gap immediately demotes the old estimate;
- a newer accepted battery receipt immediately demotes the old estimate;
- reconnecting transport cannot make an old estimate look fresh;
- a newer receipt at the same uptime tick still demotes the old estimate because owner generation/receipt chronology, not a wall-clock heuristic, owns currentness;
- persisted candidate/history bytes are not process-local live authority.

## Primary decision ladder

`nil` live estimate
→ `unavailable(.noEstimate)`

owner-revoked estimate
→ `unavailable(.retainedEstimateRequiresQualifier)`

current provisional seed
→ `learning(.provisionalSeed)`

current learned estimate below the low-confidence floor
→ `learning(.learningConfidence)`

current learned estimate at low confidence
→ `learning(.lowConfidenceRequiresQualifier)`

current learned estimate at normal/high confidence
→ `valueMeters(...)`

The policy never substitutes advertised range × battery percentage, trip distance, voltage-derived SoC, Wh/mi, or another invented numeric fallback.

## Persistence boundary

The owner-bound currentness lease is intentionally process-local and non-persistable. Durable learned-range candidate identity and the exactly-once journal are separate concerns. Restoring persisted range history may reconstruct model/history state only through its own accepted restore policy; it must not restore an old live-currentness lease or mark a retained estimate current by itself.

## Accessibility / app integration boundary

This package policy chooses truth state only. A future Battery component should map the decision into concise visible and VoiceOver language:

- numeric learned range only for `.valueMeters`;
- explicit learning language for `.learning`;
- explicit unavailable/last-known treatment for `.unavailable` as appropriate to the detailed surface.

Battery fill must continue to represent charge even when the selected text mode is learned range. Render interpolation must never be written back into this policy, the model, persistence, ride records, or telemetry evidence.

## Acceptance boundary

This successor is stacked directly on the owner-bound Battery currentness lineage. Focused tests include the original primary-decision cases plus the critical replay regression: retain an R1 validator and R1 live estimate, advance the real owner through gap/R2, and require the old estimate to remain non-current with no validator parameter available at the presentation boundary.

Package/source tests are software evidence only. No physical AOVOPRO ES80 battery source, scaling, cadence, current/power semantics, charging behavior, learned physical range, or hardware behavior is established here.
