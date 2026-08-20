# Nembra 1.0 portrait design system

This is the production contract for Home, Rides, Vehicle, Settings, profile,
and portrait secondary sheets. It extends the selected Home authority and the
existing `NembraVisuals.swift` tokens. It does not specify landscape cockpit
geometry.

## Layout

- Base spatial unit: 4pt; primary cadence: 8 / 12 / 16 / 24 / 32.
- Standard portrait content gutter: 20pt.
- Controls: minimum 44 × 44pt target; related controls share a visual group.
- Corner families: 12–14pt compact affordances, 20pt controls/rows, 28pt hero
  stages. Avoid a different radius for every surface.
- First-fold content must remain inside the window and at least 8pt above the
  native floating tab bar. Scroll reachability is not permission to ship an
  obscured standard first fold.

## Color and semantic roles

- Environment: near-black, opaque, stable.
- Primary information: warm/cool white with no alpha-dimming of thin numerals.
- Secondary information: cool neutral. Small copy crossing a variable energy
  material uses the opaque `instrumentSecondaryText` token.
- Energy and confirmed active state: warm gold.
- Connection health: green only when confirmed healthy.
- Warning: semantic red only when the real policy says low/error; warning also
  receives text/icon semantics so color is never the sole signal.
- Retained or stale state is communicated by freshness wording, read-only
  behavior, and accessibility value—not failed-contrast opacity.

## Typography

- Use Apple system/SF typography only unless a separately licensed asset is
  added with provenance.
- Hero measurements use light, rounded, tabular digits with a separately
  optically sized unit.
- Metric measurements use monospaced digits; labels use semantic system text
  roles.
- Status and card titles are semibold; explanatory copy is regular and cool
  secondary.
- Never fix a semantic text node to a pixel font or cap Dynamic Type to preserve
  a screenshot. Reflow earlier with `ViewThatFits`, stacks, and vertical growth.

## Material and elevation

- Native Liquid Glass is reserved for actual buttons, navigation, selection,
  and actionable continuation surfaces.
- Passive telemetry, battery fill, metric copy, maps, and backgrounds are not
  glass-coated.
- Reduce Transparency uses an opaque warm-graphite fallback with an explicit
  boundary. Do not assemble custom blur stacks.
- Depth is conveyed with one controlled edge response, layered contact shadow,
  and restrained environmental gold—not duplicated rings or giant glow.

## Icons

- Use SF Symbols for app controls; pair the symbol with a canonical `Label` so
  icon-only presentation retains the product title for accessibility.
- Default control weight is semibold. Icons do not replace text for warnings or
  unavailable truth.
- Product/scooter imagery must be licensed and provenance-documented; generated
  geometry cannot represent verified hardware.

## Motion and haptics

- Direct state toggle: approximately 0.20–0.28s snappy transition.
- Layout/recovery change: short spring only when it preserves causality.
- Reduce Motion removes rolling/matched-geometry motion and keeps an immediate
  state change.
- Haptics are causal: selection for a local presentation preference; success or
  warning only after corresponding confirmed outcomes. Telemetry arrival never
  produces haptics.
- No portrait surface owns a perpetual animation clock at idle.

## Truth and state hierarchy

1. Confirmed current measurement/action.
2. Explicit retained/last-confirmed state with age.
3. Learning or pending state without fabricated completion.
4. Unavailable/unknown with recovery guidance where an action exists.
5. Simulator QA is always disclosed and cannot mint physical authority.

Home may show SOC and the separately qualified range hierarchy together because
that is its selected portrait composition. The landscape cockpit has a different
contract: one value inside one unified battery instrument, toggled between SOC
and range while fill always remains SOC. Neither surface may derive range from
battery percent × advertised range.

## Release evidence

Each portrait checkpoint needs proportional source/unit checks. Visual release
acceptance additionally requires exact-head GitHub Xcode 27, iPhone 12 / iOS 27
screenshots, unchanged accessibility audits, and a same-state/reference
comparison. Local Xcode 26 is diagnostic only.
