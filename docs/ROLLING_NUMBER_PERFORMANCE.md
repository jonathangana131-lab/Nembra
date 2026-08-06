# Rolling Number Performance Hardening

This slice hardens Nembra's existing presentation-only rolling-number path for the iPhone 12 baseline without changing scooter telemetry, speed smoothing, ride evidence, or animation timing.

## Scope

The rolling-number model remains a display-domain utility. A snapshot or transition is never raw telemetry and must never be written back into vehicle state.

This slice makes two targeted hot-path improvements:

1. `RollingNumberModel` now builds its final fixed-slot digit array directly instead of allocating a temporary reversed-digit array and then mapping it into another array.
2. `RollingSpeedValueView` iterates the existing snapshot indices directly instead of materializing `Array(snapshot.digits.enumerated())` on every render pass.

The model also exposes `snapshot(scaledValue:)` for callers that already own an exact layout-scaled presentation integer. This avoids an unnecessary `UInt64 -> Double -> UInt64` round trip for future integer presentation sources such as displayed battery percentage. The API is explicitly presentation-only and does not promote a displayed value into measured scooter evidence.

## Truth boundaries

- No measured speed source, cadence, interpolation policy, or smoothing behavior changes.
- No battery percentage, range, or other display value becomes telemetry evidence through this API.
- No AOVOPRO ES80 hardware behavior is inferred or claimed.
- Existing fixed geometry, leading-zero visibility, decimal precision, transition direction, and Reduce Motion behavior are preserved.
- Large transitions remain bounded to one transition descriptor per fixed digit slot; the model does not manufacture intermediate telemetry samples merely to animate a jump.

## Verification contract

Deterministic package tests cover:

- equivalence between the existing Double-quantization path and the exact scaled-integer path;
- exact capacity rejection;
- the full supported 15-digit integer layout at its maximum representable value;
- fixed two-slot shape and leading visibility across every value from 0 through 99;
- bounded transition descriptors across a large display jump;
- fractional-slot visibility on the exact integer path.

The source-level allocation reductions are intentionally not labeled as a measured runtime speedup. Final performance acceptance still requires real Xcode 27 / iPhone 12 / iOS 27 Simulator profiling during the Production Visual + Performance Overhaul.

## Hardware status

**SOFTWARE PRESENTATION HARDENING ONLY.** Nothing in this slice is physical AOVOPRO ES80 validation.
