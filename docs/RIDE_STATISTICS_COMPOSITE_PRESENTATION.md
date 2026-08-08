# Ride Statistics Composite Presentation

Nembra presents completed-ride distance, observed duration, and accepted observed propulsion power as separate evidence domains. A premium product surface may show them together, but visual adjacency must not silently imply that independently aggregated values describe the same completed rides.

`RideStatisticsCompositePresenter` is the package-level population-identity boundary for that composition.

## Product guarantee

The producer accepts the prepared distance, duration, and power ride inputs for one requested `RideStatisticsPeriod`. It first delegates validation, period selection, deduplication, evidence aggregation, and disclosure semantics to the existing authoritative metric aggregators/presenters.

It then reconstructs only the selected population identity needed for safe cross-metric composition and requires exact equality of:

- completed session UUID;
- calendar-attribution date;
- selected ride count;
- requested period.

If the three metric inputs select different sessions, or if the same session is attributed to different ride-began/ride-ended dates, composition fails closed.

Equal period labels and equal ride counts alone are intentionally insufficient.

## Evidence independence

The composite snapshot does not create a new all-or-nothing quality grade. Each metric keeps its own accepted disclosure contract:

- trustworthy distance can be complete, partial, unavailable, or no-rides;
- monotonic observed duration can independently be complete, partial, unavailable, or no-rides;
- accepted observed propulsion power can independently be complete, partial, unavailable, or no-rides.

Complete evidence in one metric never upgrades another metric. Partial numeric evidence keeps the original metric-specific incomplete-evidence wording requirements.

## Calendar truth

Calendar attribution is product policy, not measurement evidence. A ride that crosses midnight can belong to a bucket by ride beginning or ride ending. The composite boundary requires the exact attributed date to match across all three domains so a future Stats surface cannot accidentally combine, for example, begin-attributed distance with end-attributed duration while calling both “Today.”

For bounded periods, unrelated history outside the requested period does not poison a valid current snapshot. The underlying aggregators remain authoritative for duplicate/conflict validation and period isolation; the composite scope check only verifies the identities that survived the requested selection.

## Dependency and integration boundary

The truthful distance disclosure dependency is now accepted on `main` through PR #415. This recovery re-anchors only the composite source/tests/documentation onto that accepted descendant; it does not replay stale PR #346/#369 ancestry.

The composite source/tests are additive NembraCore package work. They do not wire Home, Dashboard, Ride Details/AppRoot, persistence, Bluetooth/Tuya, navigation, battery/range, or Xcode project files. App integration should consume this product-safe boundary only after a production adapter can mechanically bind the required evidence to the same immutable completed rides and the relevant UI lane is free.

## Hardware / truth boundary

Software statistics composition only.

This work does not verify any physical AOVOPRO ES80 ODO/GPS distance source, BLE/Tuya field, speed cadence, battery/current/power semantics, command acknowledgement, or hardware behavior. Simulator power evidence used by tests remains explicitly Simulator-only. Accepted observed power remains an observed measurement concept, not throttle position, rated motor/controller power, or a perfect physical maximum.
