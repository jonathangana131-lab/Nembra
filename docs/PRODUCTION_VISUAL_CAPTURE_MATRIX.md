# Production visual capture matrix — UI-test evidence lane

Date: 2026-08-06
Worker: `chat-p7w3k`
Lane: `visual-capture-matrix`
Baseline: iPhone 12 / iOS 27

This lane closes specific evidence gaps identified by `PRODUCTION_VISUAL_CAPTURE_GAPS_2026-08-06.md` using **UI-test screenshot attachments only**. It does not redesign production UI, change navigation, change simulation behavior, edit CI workflows/scripts, or claim physical-device evidence.

## Why UI-test attachments

The existing Xcode 27 Simulator QA already preserves the test result bundle and its UI-test attachments in the uploaded artifact. Landscape Dashboard mode screenshots are already captured this way and were successfully inspected from prior exact-head artifacts.

That makes test attachments the lowest-contention way to preserve additional portrait states without duplicating the top-level `simctl io screenshot` script or modifying accepted production screens.

## Owned scope

Implementation ownership for this lane is intentionally narrow:

- `NembraUITests/NembraUITests.swift`
- this document

Explicitly not owned:

- `NembraUITests/RideUITests.swift` — route/location workers own that area;
- `NembraApp/App/AppRootView.swift` / navigation shell — navigation baseline already landed separately;
- production feature views;
- `scripts/ci/xcode27_simulator_capture.sh`;
- `.github/workflows/**`;
- project-file wiring.

## Capture set

The first implementation checkpoint restores already-proven portrait scenario tests that existed before the navigation-baseline rewrite and preserves their final asserted UI state as keep-always screenshots:

1. cold/disconnected recovery state;
2. connected/riding Home telemetry state;
3. low-battery warning state;
4. Bluetooth-off recovery guidance;
5. current connected-control / unavailable / permission-denied tests on the navigation baseline also preserve their final asserted state;
6. existing landscape cockpit and Walk/Eco/Drive/Sport attachment behavior remains unchanged.

The restored scenarios reuse existing `AppBootstrap` simulation contracts rather than inventing new fixtures.

## Evidence boundaries

A screenshot proves only the rendered Simulator state for the exact test head and scenario arguments.

It does not prove:

- physical iPhone color/brightness/thermal behavior;
- real ES80 Bluetooth behavior;
- outdoor GPS or route behavior;
- Dynamic Type coverage unless the test explicitly launches with that configuration;
- Reduce Motion coverage unless explicitly configured;
- compact-height/device-family coverage unless that destination is actually run;
- loading/error/corrupt route-history states not represented by an accepted deterministic fixture.

The lane must not create fake data merely to fill a screenshot matrix.

## Acceptance

Before this lane can merge:

1. Swift syntax parse of the modified UI-test source;
2. exact-head Xcode 27 / iPhone 12 Simulator QA;
3. inspect the uploaded `.xcresult` / artifact and verify the new keep-always screenshots are present and correspond to the asserted states;
4. refresh main and active UI-test ownership;
5. reconcile/re-run if the final head changes;
6. merge only with expected-head protection.

Remaining visual gaps after this slice should stay explicitly listed rather than being marked complete without evidence.

## Hardware status

**SIMULATOR VISUAL EVIDENCE ONLY.** Physical iPhone 12 and AOVOPRO ES80 validation remain separate gates.
