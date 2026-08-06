# Rolling Number Performance Hardening

This slice hardens Nembra's existing presentation-only rolling-number core for the iPhone 12 baseline without changing scooter telemetry, speed smoothing, ride evidence, or animation timing.

## Scope

The rolling-number model remains a display-domain utility. A snapshot or transition is never raw telemetry and must never be written back into vehicle state.

`RollingNumberModel` now builds its final fixed-slot digit array directly instead of allocating a temporary reversed-digit array and then mapping it into another array. The model also exposes `snapshot(scaledValue:)` for callers that already own an exact layout-scaled presentation integer. This avoids an unnecessary `UInt64 -> Double -> UInt64` round trip for future integer presentation sources such as displayed battery percentage.

A separate SwiftUI performance lane, PR #33, owns the Dashboard render-tree/invalidation work and the view-level removal of `Array(snapshot.digits.enumerated())`. This core lane intentionally does not compete for `RollingSpeedValueView.swift`.

## Truth boundaries

- No measured speed source, cadence, interpolation policy, or smoothing behavior changes.
- No battery percentage, range, or other display value becomes telemetry evidence through this API.
- No AOVOPRO ES80 hardware behavior is inferred or claimed.
- Existing fixed geometry, leading-zero visibility, decimal precision, and transition direction are preserved.
- Large transitions remain bounded to one transition descriptor per fixed digit slot; the model does not manufacture intermediate telemetry samples merely to animate a jump.

## Verification contract

Deterministic package tests cover:

- equivalence between the existing Double-quantization path and the exact scaled-integer path;
- exact capacity rejection;
- the full supported 15-digit integer layout at its maximum representable value;
- fixed two-slot shape and leading visibility across every value from 0 through 99;
- bounded transition descriptors across a large display jump;
- fractional-slot visibility on the exact integer path.

The source-level allocation reduction is intentionally not labeled as a measured runtime speedup. Final performance acceptance still requires real Xcode 27 / iPhone 12 / iOS 27 Simulator profiling during the Production Visual + Performance Overhaul.

## Hardware status

**SOFTWARE PRESENTATION HARDENING ONLY.** Nothing in this slice is physical AOVOPRO ES80 validation.
