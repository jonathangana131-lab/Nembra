# Accepted Battery -> Learned Range Bridge (V14)

This package-only bridge closes the authority seam between accepted normalized battery chronology and learned-range window candidates.

## Authority chain

`BatteryEvidenceObservation`
-> `AcceptedBatterySOCStream`
-> `AcceptedBatterySOCAnchor`
-> `AcceptedBatteryRangeLearningPipeline`
-> `AcceptedBatteryRangeLearningWindow`
-> later `AcceptedAdaptiveBatteryRangeModel` ingestion

Only a verified vehicle SoC observation whose receipt survives the battery stream validator may become an accepted SoC anchor. Public estimated/imported SoC cannot manufacture this authority.

All live battery observations in one acquisition chronology should pass through the accepted stream, including non-SoC siblings. This preserves exact receipt ordering and lets a continuity boundary carried by another field rotate the learned-range span before a same-receipt SoC sibling arrives.

## Chronology is not rollbackable downstream

The battery stream admits/consumes receipt chronology before range assembly. If stream validation consumes a newer receipt watermark and rejects it, or if a later range step cannot form a learning candidate, the battery chronology is not rewound. Downstream failure must never make an older raw callback fresh again.

The ephemeral range span is independently fail-closed: invalid distance input does not partially mutate distance/coverage state; segment changes and explicit unobserved intervals discard pre-gap span evidence.

## Distance truth

The bridge does not choose GPS, wheel, map-provider, or any other distance source. A higher authority supplies nonnegative distance deltas and classifies coverage. Omitted coverage is `.unknown`, never implicitly complete. Coverage degradation and explicit transport-gap evidence are sticky until the span rebases.

## Candidate is not learned history

An emitted `AcceptedBatteryRangeLearningWindow` is only a receipt/continuity-bound candidate. It is not accepted history, not a learned range result, and not physical ES80 proof. `AcceptedAdaptiveBatteryRangeModel` still applies coverage, gap, threshold, outlier, numerical, and first-window plausibility gates.

Exactly-once persistence and vehicle-identity-bound restore remain separate closure work. This bridge intentionally does not persist or mutate accepted learned history.

## Physical boundary

Software only. No ES80 field/scaling semantics, battery percentage source, distance source, reconnect behavior, energy/current/power semantics, or physical range result is established by this bridge.
