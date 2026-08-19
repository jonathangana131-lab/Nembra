# Nembra cross-surface UI contracts

Status: shared coordination contract. Surface owners retain their own layout and
implementation files.

## Product palette

Use the existing `NembraColor` values in
`NembraApp/DesignSystem/NembraVisuals.swift` without creating a competing
cockpit palette:

- gold `#EFBC58` for energy and active-route/discovery truth;
- active gold `#E5A83C` for restrained live illumination;
- deep gold `#9A5F18` for depth, not primary copy;
- graphite `#0B0B0A` and base black `#060706`;
- primary text `#F4F7FB`, secondary text `#8D98AA`;
- semantic system green only for healthy live connection and semantic red/yellow
  only for accepted warning/error policy.

## Battery contract shared by Home and Cockpit

- The physical fill always represents accepted state of charge.
- Cockpit shows exactly one centered primary value: percentage by default or
  accepted adaptive range after tap. It never shows simultaneous or detached
  range copy.
- Range unavailable/learning/currentness replaces the single value honestly; it
  does not invent a number.
- Engineered graphite/gold shell, inner rim, clipped micro-ribs, terminal, and
  state-aware copy follow the selected Home material language. The cockpit owns
  its compact landscape geometry and does not edit portrait layout.
- VoiceOver announces current value, fill meaning, currentness, and the alternate
  action. Reduce Motion uses a static change/crossfade; haptics respect app and
  system preference.

## Instrument typography

- Use licensed system SF typography only.
- Cockpit speed uses tabular system digits, a stable fixed slot, deliberate
  optical width/weight, and a smaller decimal/unit on the same baseline.
- Do not imitate proprietary Stark/Tesla typefaces or use a bundled unlicensed
  font.
- Telemetry captions use the same cool-grey hierarchy as portrait secondary
  information, with tracking reduced at large Dynamic Type sizes.

## Native material contract

- Native Liquid Glass belongs only to functional navigation/control chrome.
- Battery, speed, power, map, ledgers, and passive telemetry are content, not
  glass cards.
- Group neighboring glass controls in one `GlassEffectContainer`, keep 44-point
  targets, stable shapes/IDs, and an opaque graphite Reduce Transparency fallback.

## Ownership boundary

- Cockpit branch owns `NembraApp/Features/Dashboard/`, its domain/test/evidence
  seams, and narrow entry wiring only when required.
- Portrait branch owns Home/Rides/Vehicle/Settings. Neither branch should refactor
  the other's composition opportunistically.
- Shared token or semantic changes must be recorded here and coordinated before
  integration.
