# Ride History + Details Accessibility Audit — 2026-08-06

Worker: `chat-k8x5d`
Lane: `ride-history-accessibility-audit`
Role: source-backed, docs-only accessibility QA

## Scope and evidence basis

This audit is deliberately narrow. It reviews the current completed-ride list/details accessibility contract on `main@a2f8ab5535b0c311112e9cfd4fb1bed4c8529f66` without editing the high-contention `AppRootView.swift` surface.

Primary repository evidence:
- `NembraApp/App/AppRootView.swift` — current `RideHistoryView`, `RideHistoryRowView`, `RideHistoryDetailView`, and `RideRouteMapView` implementation;
- `NembraUITests/RideUITests.swift` — current end-to-end ride/history UI coverage;
- `docs/PRODUCTION_VISUAL_PERFORMANCE_OVERHAUL.md` — permanent requirement that accessibility is part of final runtime acceptance;
- active visual-audit lane PR #63 — screenshot-backed finding that Ride Details content can be obscured by floating tab chrome and that evidence terminology is too dominant in the product hierarchy.

Current Apple accessibility documentation was checked on 2026-08-06 for the semantics used here:
- SwiftUI standard controls receive basic accessibility automatically, while custom composition can add explicit labels/values;
- `.accessibilityElement(children: .ignore)` hides the child accessibility elements and creates a new element that needs its own accessibility properties;
- accessibility values should describe information different from the label rather than repeating it;
- `XCUIApplication.performAccessibilityAudit(for:_:)` is available for automated XCTest accessibility audits.

This document does not claim a VoiceOver failure that has not been observed on a real Simulator/device. Findings are classified below as either **source-proven semantic defects** or **runtime acceptance risks that require actual assistive-technology QA**.

## Existing strengths worth preserving

The completed-ride surfaces already have several good accessibility foundations:

- native `TabView`, `NavigationStack`, `List`, `NavigationLink`, `ContentUnavailableView`, and `LabeledContent` are used rather than replacing standard controls with custom gesture-only equivalents;
- the automatic ride status strip is collapsed into one explicit accessibility element with a stable label/value;
- completed ride rows intentionally provide a custom summary rather than exposing every visual sublabel independently;
- odometer and GPS evidence remain semantically separate in the row and details screen;
- persistence/loading/error/route states have stable identifiers for deterministic UI tests;
- detail evidence values use localized `VehicleDisplayFormatting` rather than hard-coded units;
- route coverage, recorded point count, and known gap count remain explicit instead of implying complete geometry when evidence is partial;
- there is no accessibility path that promotes Simulator data or unreconciled distance into physical ES80 truth.

The final redesign should preserve these truth boundaries while improving navigation efficiency and semantic clarity.

## P0 — source-proven semantic defect: normal completed rows repeat their identity

`RideHistoryRowView` currently does this:

- creates one custom accessibility element with `children: .ignore`;
- sets `accessibilityLabel("Completed ride")`;
- sets the accessibility value to date/time + distance evidence + `continuityLabel`;
- for an ordinary uninterrupted ride, `continuityLabel` is also `"Completed ride"`.

That means the normal-row semantic contract repeats the same identity in both label and value. This is not merely visual duplication: because `.ignore` hides the child accessibility elements, the custom label/value pair is the authoritative row description.

Apple's current guidance says the accessibility value should communicate value/state that is different from the element's label. Repeating `Completed ride` at both ends adds noise to every history-row traversal.

### Required behavior

A future implementation should provide one concise row identity and one non-duplicative value. For example, the semantic information must include:
- ride date/time;
- truthful available distance-source state;
- recovered-vs-normal continuity only when it changes user meaning.

The audit does **not** require those exact words or ordering. It requires that the final VoiceOver announcement avoid duplicate identity text and preserve source uncertainty.

### Required regression test

For an ordinary completed ride, query the row's exposed accessibility label/value and assert that the same completion phrase is not redundantly encoded as both identity and trailing state.

For a recovered ride, assert that recovery remains clearly discoverable without falsely implying an uninterrupted process.

## P0 — route shape has no stable Nembra-owned accessibility summary

`RideRouteMapView` renders real persisted route segments with `MapPolyline`. In `RideHistoryDetailView`, the map receives only `accessibilityIdentifier("rides.route-map")`; Nembra does not currently attach a stable app-owned accessibility label/value describing what that visual represents.

This does **not** prove that SwiftUI/MapKit exposes nothing to VoiceOver. It means Nembra has no deterministic semantic contract for the route visualization itself. The current UI test proves only that the map exists when durable geometry exists.

For a route visualization whose important truth includes complete/partial/unknown coverage and known gaps, provider-default map semantics are not enough as the product contract.

### Required behavior

When a drawable route map is present, expose one concise Nembra-owned semantic summary that communicates only facts Nembra actually has, such as:
- that this is the recorded ride route;
- coverage classification;
- recorded point count when useful;
- known gap count when nonzero.

Do not invent street names, start/end places, route legality, continuous coverage, or reconstructed geometry that the stored ride evidence does not contain.

The implementation may choose an accessibility representation/container strategy appropriate to the final map interaction design. The key requirement is that users are not forced to infer route truth from unlabeled MapKit internals.

### Required regression test

For the existing durable-route QA fixture:
- assert a stable user-facing route-map label exists;
- assert its value reflects the fixture's real coverage/gap state;
- assert a no-route record does not expose the same route-map semantic element.

## P0 — current UI tests do not exercise the accessibility contract

`RideUITests.testCompletedRideAppearsWithDurableRouteThroughRealRidePipeline()` currently proves:
- a completed row appears;
- the row can be tapped;
- odometer evidence contains a localized distance unit and is nonzero in the explicit QA fixture;
- a durable route map appears;
- the no-route fallback is absent;
- screenshots are preserved.

Those are strong lifecycle/truth checks, but they do not currently assert:
- completed-row accessibility label/value quality;
- recovered-row semantics;
- route-map accessibility summary;
- accessibility audit findings;
- large Dynamic Type layout behavior;
- focus/direct-touch operability at the bottom of Ride Details with the floating tab bar present.

### Required acceptance expansion

At the eventual Ride History accessibility implementation checkpoint, add focused accessibility assertions without weakening the existing persistence/route assertions.

Also add `XCUIApplication.performAccessibilityAudit(for:_:)` to a stable completed-history/details fixture where Xcode's automated checks are applicable. Any allowlist/issue handler must be narrow and documented; do not broadly ignore failures just to make CI green.

Automated audit success is necessary evidence, not final proof. VoiceOver traversal, large Dynamic Type, and direct interaction still require real runtime inspection.

## P0 — floating tab/content collision is also an accessibility-operability defect

PR #63's real-Simulator visual audit documents the floating Home/Rides tab control overlapping the Ride Details route/coverage region.

That is not only a visual polish issue. At final acceptance, bottom content must remain reachable and unobscured for:
- direct touch;
- VoiceOver focus;
- Switch Control / keyboard-like sequential focus where supported;
- large Dynamic Type where rows consume more vertical space.

This audit does not take ownership of the shell/safe-area implementation. It adds an accessibility acceptance requirement to the existing visual P0.

### Required runtime acceptance

On iPhone 12 / iOS 27:
1. open a ride with drawable route geometry;
2. use a large accessibility Dynamic Type category;
3. scroll to the final route metadata row;
4. verify no focusable/readable content terminates underneath the floating tab chrome;
5. verify the route/map summary and final metadata remain reachable in logical order.

## P1 — the history row layout needs an accessibility-size runtime contract

Visually, `RideHistoryRowView` is a single horizontal stack:
- continuity icon;
- date/continuity text;
- spacer;
- right-aligned ODO/GPS evidence stack.

The text uses semantic fonts, which is good, but the structure has no explicit accessibility-size fallback. At large content-size categories the left date/continuity cluster and right evidence cluster compete for horizontal width.

This is a **runtime risk**, not a source-proven clipping bug. It must be accepted with actual iPhone 12/iOS 27 rendering rather than assumed safe because SwiftUI fonts scale.

### Required behavior

At accessibility text sizes:
- date/time remains readable;
- distance-source evidence remains readable;
- recovered status remains discoverable;
- no evidence line becomes visually ambiguous through truncation/overlap;
- the row remains a comfortably tappable navigation target.

A future implementation may switch to a vertical/adaptive composition. This audit intentionally does not prescribe a layout before runtime evidence.

## P1 — evidence prose needs progressive disclosure for VoiceOver efficiency too

The current Rides list footer and Ride Details distance/route explanations truthfully describe evidence separation. The active visual audit correctly recommends moving detailed evidence architecture behind progressive disclosure in the final product hierarchy.

That recommendation has an accessibility benefit as well: a user should be able to traverse ride history efficiently without repeatedly stepping through long implementation-oriented explanations on every ordinary visit.

### Required behavior

Preserve all truth and uncertainty, but structure it in layers:
1. concise ride summary;
2. concise evidence/coverage state;
3. optional technical recording details.

Do not solve verbosity by deleting uncertainty or collapsing ODO/GPS into a fabricated final distance.

## P1 — accessibility identifiers are test hooks, not user-facing semantics

The ride UI has strong identifier coverage (`rides.completed-row`, `rides.detail`, `rides.route-map`, evidence/loading/error identifiers). Keep those stable where practical because they make deterministic end-to-end testing possible.

However, an identifier is not a VoiceOver label. The route map illustrates why both layers matter: the test can find `rides.route-map` today even though Nembra has not defined a stable user-facing description for the map.

Future test hardening should continue to query stable identifiers while separately asserting user-facing label/value semantics.

## P1 — preserve useful automatic semantics instead of over-labeling everything

The detail screen uses native `LabeledContent` for timeline, distance evidence, coverage, recorded points, and known gaps. SwiftUI already provides basic accessibility for standard controls/content.

Do not respond to this audit by adding custom labels to every standard row. Excessive overrides can remove useful native behavior or create duplicated announcements.

Use explicit accessibility composition where Nembra has a custom semantic unit (for example, the summarized history row or route visualization). Leave ordinary labeled rows native unless real assistive-technology testing demonstrates a problem.

## Required accessibility acceptance matrix

The final Ride History/Details implementation should cover at least:

### History states
- empty history;
- one ordinary completed ride;
- one recovered ride;
- long history;
- refresh/load failure while old records remain visible;
- history unavailable.

### Distance/route truth states
- ODO-only evidence;
- GPS-only evidence;
- both sources present but intentionally separate;
- no distance evidence;
- drawable complete route;
- drawable partial route with one or more known gaps;
- recorded points without a drawable path;
- no route geometry;
- route storage failure.

### Accessibility modes
- VoiceOver row/detail traversal;
- automated XCTest accessibility audit;
- default text size;
- at least one accessibility Dynamic Type size and the largest practical acceptance size;
- light and dark appearance for route-line/text contrast;
- portrait iPhone 12 safe-area/tab-bar interaction;
- Reduce Motion where later Ride/History transitions are introduced.

## Suggested deterministic assertions

These are acceptance contracts, not a demand that this docs-only lane edit test files now:

1. completed-row label/value do not repeat the same identity phrase;
2. recovered-row semantics expose recovery explicitly;
3. ODO-only fixture never speaks a GPS value;
4. GPS-only fixture never speaks an ODO value;
5. no-distance fixture announces unavailability rather than zero distance;
6. route-map summary exists only for real drawable geometry;
7. partial-route summary preserves `partial`/known-gap truth;
8. no-route and route-storage-error states remain distinguishable;
9. app accessibility audit passes without broad suppression;
10. large Dynamic Type screenshots show no row/detail/tab-bar collision.

## Sequencing / ownership

This audit should **not** become a competing `AppRootView.swift` implementation while the swarm is busy.

Recommended sequencing:
1. preserve this document as the Ride History accessibility acceptance contract;
2. allow current ride-location recovery and visual-audit work to settle;
3. when the final Rides redesign/integration owner touches `AppRootView.swift`, implement the semantic fixes and adaptive layout together rather than creating another conflicting root branch;
4. add focused UI accessibility assertions at that same integration checkpoint;
5. run exact-head Xcode 27 / iPhone 12 / iOS 27 Simulator QA and inspect both automated audit output and real assistive-technology behavior.

The active production visual audit remains owner of layout/product-hierarchy critique. This lane owns only the accessibility acceptance contract for completed rides and does not change production Swift.

## Truth / hardware boundary

This audit changes no product behavior and makes no physical hardware claim.

- Simulator route/history evidence remains software evidence only.
- Accessibility summaries may describe only data already present in the ride record/route geometry.
- A route-map description must never invent route legality, street identity, location coverage, scooter telemetry, or physical ES80 behavior.
- A cleaner VoiceOver summary must never hide unresolved evidence by promoting it into a false final distance.

Physical AOVOPRO ES80 behavior, outdoor GPS behavior, and physical iPhone accessibility/performance remain separate verification work.
