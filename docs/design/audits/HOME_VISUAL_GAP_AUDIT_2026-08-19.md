# Portrait Home 1.0 visual gap audit — 2026-08-19

## Evidence compared

- Selected composition source:
  `docs/design/references/portrait-home/selected-home-composition-source.png`
  (`0aed2710…`, 853 × 1844).
- Gold color authority:
  `docs/design-reference/nembra-1.0-gold-glass/selected-home-gold-glass.png`
  (`dff0d084…`, 780 × 1688).
- Exact runtime baseline: integration commit
  `cf817a8b1c1f74640055af317671497a202e4f74`, GitHub `Xcode 27 Simulator QA`
  run `32310434323`, artifact `9386781377`, iPhone 12 / iOS 27 / Xcode
  27.0 (`27A5228h`).
- Runtime Home attachment:
  `FFAE67FE-728C-4E75-B742-013221C10FBD.png`, 1170 × 2532,
  SHA-256 `1ce89ef8f3f3f0f7095297255cdb96298ae5b609fd0490eb6c84d1564a53d766`.

The runtime screenshot is functional evidence only. It is not a Home 1.0
visual-acceptance screenshot.

## What is already production-directed

- Battery fill remains SOC; range is a separate authority-gated projection.
- Missing production adaptive range remains `Unavailable`; Simulator values do
  not become physical truth.
- Retained battery includes explicit freshness and does not enable commands.
- Today projects the durable local-day ledger rather than a scooter-session
  trip counter.
- Light, lock, and mode controls wait for confirmed command state.
- The passive battery and grounding canvases have no perpetual timeline.
- Native `TabView`, native glass controls, Reduce Motion, Reduce Transparency,
  large-text reflow, and stable UI identifiers already exist.

## Visible gaps to close

1. **Hero asset and lighting** — the temporary 500 × 500 grey/red ES80 cutout
   is soft at iPhone 12 @3x, right-heavy, and visually separate from the gold
   scene. It remains a layout silhouette, not cleared 1.0 artwork.
2. **Battery refinement** — the current shell is heavy, the ribs are coarse and
   uniform, and the graphite copy well is too abrupt. Refine only from hosted
   screenshots while preserving exact SOC geometry and static idle rendering.
3. **Ground contact** — the current warm haze does not yet read as separate tire
   contacts, deck shadow, floor plane, and restrained reflection.
4. **Glass hierarchy** — the top control has a doubled custom/native ring in the
   baseline. Control tray, continuation, and native dock need one coherent
   material hierarchy rather than extra custom borders or blur stacks.
5. **Large-content composition** — reconnecting and Accessibility XXXL add
   truthful content but still need hosted evidence that all copy reflows and
   the continuation clears the floating tab.
6. **Ride continuation** — empty/loading/error truth is correct. A completed
   ride must remain fully visible and tappable without inventing route art.

## Exact functional failures at the baseline

The cf817 hosted run passed Core 1,355/1,355 and app/unit 76/76, then failed five
UI checks. Portrait-owned failures were:

- connected Home contrast on the SF-symbol-named Vehicle Controls node;
- low-battery contrast on `no learned range`;
- retained-battery contrast on `%`;
- Ride detail Dynamic Type on the synthetic `Ended` accessibility node.

Integration commit `0b7e3b27de5e9b547911558ae8ed4cb852becb59` already owns the
retained/range and Ride timeline corrections. This portrait branch must not
duplicate those hunks. Its first slice adds the canonical `Label` control
semantics and opaque portrait instrument tokens. At Accessibility XXXL, range
copy reflows below the 94pt battery instead of shrinking or crossing bright
gold; the exact fixture now retains contrast and text-clipping audits.

## Deterministic Home evidence matrix

Before visual acceptance, retain exact-head screenshots and audits for:

- connected / fresh battery / range unavailable;
- disconnected with no retained telemetry;
- reconnecting with retained battery freshness;
- loading and explicit connection error/recovery;
- low battery with a non-color warning;
- active automatic ride and recovered ride;
- completed latest ride with durable Today values;
- Accessibility XXXL, Increased Contrast, Reduce Transparency, and Reduce
  Motion.

The screenshots must remain explicitly Simulator QA where fixtures are used.
