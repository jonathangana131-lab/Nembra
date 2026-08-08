# Ride Speed Statistics Composite Presentation

## Purpose

Nembra now has independent, disclosure-safe completed-ride speed statistics for:

- elapsed-ride average speed, derived from complete paired whole-ride distance and monotonic observed duration;
- quality-qualified observed maximum speed, derived from the highest accepted observed measurement whose same-ride telemetry evidence satisfies its retained quality policy.

Those two metric producers are individually truthful, but equal period labels and equal ride counts do not prove that independently prepared summaries describe the same completed rides. A product surface that places them together needs a population-identity boundary.

`RideSpeedStatisticsCompositePresenter` provides that boundary.

## Contract

The composite producer accepts the prepared per-metric ride inputs rather than accepting already-built summaries. It:

1. runs the authoritative average-speed and observed-maximum aggregators;
2. runs their disclosure-safe presenters;
3. independently reconstructs the selected calendar population for each metric as exact `(sessionID, attributedDate)` identities;
4. requires those selected identity sets to match exactly;
5. requires each component projection's selected ride count to equal that exact shared population count;
6. returns both component projections unchanged inside one composite snapshot.

The composite does **not** create a combined evidence grade. Average-speed completeness and observed-maximum completeness remain independent.

Example: if two selected rides both have qualified observed peaks but one lacks trustworthy whole-ride distance, the composite may legitimately expose:

- partial elapsed-average evidence for one supporting ride, with incomplete-evidence disclosure; and
- complete qualified observed-maximum evidence across both rides.

The complete maximum must not upgrade the partial average, and the partial average must not downgrade or relabel the maximum.

## Why same count is insufficient

These two independently produced summaries are not safe to compose merely because both say `Today` and `2 rides`:

- average speed could describe rides A + B;
- observed maximum could describe rides C + D.

The composite therefore checks immutable ride identity, not just cardinality.

Calendar attribution is part of that identity. A cross-midnight ride attributed to its begin date for one metric and its end date for another is rejected even under All Time, because presenting the metrics together would imply a common selected population that does not actually exist.

## Bounded periods

For Today, Yesterday, Week, Month, and Year, unrelated rides outside the selected calendar window do not need to exist in both metric inputs. Each metric's own aggregator remains responsible for malformed/duplicate/conflicting evidence. The composite compares only the identities selected for the requested product period and then reconciles the resulting projection counts.

All Time means all supplied history. It does not claim the upstream store is lifetime-complete.

## Truth boundary

This is software statistics/presentation composition only.

It does not choose or verify an AOVOPRO ES80 speed source, BLE/Tuya field, cadence, latency, resolution, GPS accuracy, or quality threshold. It does not turn an observed maximum into a perfect continuous-time maximum, rated/certified scooter speed, or throttle evidence. It does not turn elapsed-ride average speed into moving speed or a mean of raw telemetry samples.

No Bluetooth, command, persistence, Dashboard, Home, navigation, battery/range, or physical-hardware behavior is changed by this slice.
