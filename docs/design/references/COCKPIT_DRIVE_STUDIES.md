# Nembra cockpit Drive composition studies

Status: internal design evidence; **not a production pixel authority**.

These studies preserve the selected portrait Home's near-black, graphite,
white, and warm-gold language while exploring a new mounted-phone Drive
composition after the permanent rejection of Horizon V2, V3, and V4. They are
stored in the repository so a later task can recover the visual reasoning.

All four images are 1844 x 853 pixels, matching the iPhone 12 landscape
viewport ratio (844 x 390 logical points). They contain Simulator-style fixture
values and cannot establish physical AOVOPRO ES80 telemetry, scale, cadence, or
hardware capability.

## Source and provenance

| File | SHA-256 | Role |
| --- | --- | --- |
| `../../design-reference/horizon-post-v4-studies/drive-study-energy-chamber.png` | `782daaec74d19dddab679d41c5a9a5dc0b40d31df96c34707570170e32db9a3a` | Exact user-named promising direction copied from Codex ImageGen result `exec-9ab5bb3f-797f-400f-895f-8cbe673c9219.png`; layout/light reference only. Its `-18 / 18 kW`, current, and peak values are rejected fantasy fixtures. |
| `../../design-reference/horizon-post-v4-studies/drive-study-tension-horizon.png` | `609de8d696c62e247a773a2466cb57e79b59c57adfc97bb01cc44f33a2f4c7ed` | Linear instrument hypothesis with explicit zero/current/peak hierarchy. |
| `../../design-reference/horizon-post-v4-studies/drive-study-axial-stage.png` | `3576cc7b9b11931214ff65f17a97d071f11107e4c390ba55d0f00cda14b14531` | Asymmetric reflow hypothesis intended to test a future Navigation transformation. |
| `../../design-reference/horizon-post-v4-studies/drive-study-energy-chamber-refined.png` | `293410302b659415f5cd4d2bc0ed7650a24af7159907fe02e9f57e2b1034944d` | Strongest internal Drive skeleton after removing the fantasy signed scale and quieting the rail. Still not a pixel target. |

The generated files have no runtime or telemetry authority and are not shipped
app assets. App code must recreate the chosen composition natively rather than
rasterizing these PNGs.

## Comparison and decision

### Tension Horizon

Strengths: clearest left-to-right zero/current/peak reading, generous speed
hierarchy, and good lower-ledger separation. Risks: it reads like a conventional
dashboard ruler, the separate peak label competes with NOW, and the composition
does not create a sufficiently original mounted-phone instrument.

### Axial Stage

Strengths: strongest directional movement and most promising seed for the later
Navigation reflow. Risks: the left-anchored speed feels detached from battery and
vehicle identity, the power curve is too scenic, and its marker roles are not
instantly distinguishable.

### Energy Chamber

Strengths: giant centered speed, quiet top chrome, one shallow precision line,
strong black negative space, and a believable floor-light relationship. Risks:
the original signed `-18 / 18 kW` scale falsely implies regen/reverse and an
unsupported physical range; NOW, track, and peak are too ambiguous at a glance.

### Refined Energy Chamber — current internal lead

This is the selected implementation skeleton for the first Drive vertical
slice, not final visual acceptance. Native implementation must improve it:

- exactly one value inside the engineered battery (`%` by default, accepted
  range after tap), while the fill always remains SOC;
- system-only Nembra instrument typography with tabular rolling digits,
  deliberate optical width/weight, and a subordinate decimal/unit;
- a high-contrast, non-color-only NOW locator with a clear zero origin, visible
  positive propulsion direction, active segment, accepted watts, and a distinct
  recent accepted peak;
- no signed scale, regen, throttle, rated maximum, or physical peak wording
  without a separate verified contract;
- no numeric scale endpoint unless its compatible observed-envelope or Simulator
  provenance is explicitly admitted;
- native Liquid Glass only for functional Home/Navigation controls;
- no perpetual idle animation, whole-screen telemetry invalidation, or map/card
  structure inherited from V4.

## Acceptance boundary

The current lead becomes a production visual authority only after a native
same-state iPhone 12 landscape implementation is captured on the GitHub-hosted
Xcode 27/iOS 27 lane, placed beside the study, and passes functional truth,
accessibility, safe-area, Reduce Motion/Transparency, interaction, and sustained
Release performance gates. Until then, this folder records internal decisions,
not user acceptance.
