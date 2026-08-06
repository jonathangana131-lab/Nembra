# Nembra Production Visual + Performance Overhaul — Mandatory Release Phase

This document is a permanent product directive for the existing Nembra application.

The current systems-era UI is **not** the finished product. Correct architecture, correct telemetry, correct rides, correct maps, correct battery/range logic, and passing tests are necessary foundations, but they do not make Nembra complete.

## Scale of the final product phase

Once the major truthful systems are sufficiently complete, the Production Visual + Performance Overhaul becomes one of the largest remaining bodies of work in the project.

Treat this as a major product-development phase, **not** a polish sprint. It is reasonable for visual design, interaction design, animation, performance, accessibility, haptics, responsive layout, real Simulator iteration, and final product refinement to consume **roughly half or more of the remaining development effort after the underlying systems are ready**.

Do not rush this phase because the app is already functionally complete. Do not declare Nembra nearly finished merely because most backend/domain systems exist. The user-facing experience is a first-class half of the product.

## Quality bar

Nembra should feel like a world-class native iOS 27 vehicle product: premium, fluid, deliberate, fast, tactile, glanceable, and visually memorable.

Tesla and Stark VARG software may be used as references for confidence, hierarchy, animation quality, instrumentation clarity, and premium vehicle feel. Apple first-party apps may be used as references for native interaction, typography, motion, accessibility, materials, and restraint. Nembra must remain original; do not copy another product pixel-for-pixel.

The target is not “clean enough.” The target is a product that looks and feels unusually good even when compared with expensive automotive and first-party mobile software.

## This phase may redesign accepted systems-era UI

Current Home, Dashboard, Rides, maps, stats, controls, and supporting screens are functional baselines. Their prior acceptance protects truthful behavior and regression safety; it does **not** freeze their composition or visual treatment.

During the final overhaul, substantially redesign them when necessary while preserving accepted domain truth and safety semantics.

A screen can be technically correct and still require a near-total visual rebuild.

## Mandatory screen-by-screen iteration

For every major screen/state:

1. run the actual current app on iPhone 12 / iOS 27 Simulator;
2. capture real screenshots;
3. critique hierarchy, spacing, typography, materials, balance, wasted space, glanceability, state clarity, and overall desirability;
4. redesign materially where needed;
5. implement production SwiftUI rather than static mockup-only work;
6. run and interact with the result;
7. capture new screenshots;
8. compare before/after critically;
9. fix anything that still looks generic, cheap, cramped, empty, inconsistent, prototype-like, or visually weak;
10. repeat until the screen reaches the product quality target.

Do not stop after one redesign pass merely because it is better than the old screenshot.

## Motion and interaction are part of the design, not decoration

Static screenshots are insufficient for final acceptance.

The final product must deliberately design and test:

- rolling speed digits;
- battery percentage changes;
- `% ↔ estimated range` tap transition;
- mode changes;
- connection/reconnection states;
- ride start/active/end state transitions;
- navigation entering/exiting and cockpit rearrangement;
- map camera behavior;
- control press/confirmation behavior;
- sheet/navigation transitions;
- charging and low-battery transitions where verified;
- error/recovery state changes;
- Reduce Motion alternatives.

Animations must be interruptible, responsive, native-feeling, and grounded in real state. Never create fake telemetry merely to make motion look smoother.

## Performance is co-equal with appearance

A beautiful UI that drops frames, burns battery, delays controls, or becomes janky during maps/telemetry is not accepted.

The final overhaul includes an explicit performance program on the iPhone 12 baseline:

- maintain excellent interactive responsiveness and target 60 Hz presentation where appropriate;
- localize high-frequency telemetry rendering;
- prevent speed/battery animation from invalidating unrelated screen trees;
- profile map/route rendering;
- profile long ride-history and statistics lists;
- profile navigation + live telemetry together;
- inspect CPU/main-thread work during realistic ride simulation;
- inspect memory growth/leaks where tooling permits;
- avoid unnecessary blur/material cost;
- avoid needless timers and full-screen refresh loops;
- minimize persistence/network/BLE work on the main actor;
- validate launch and screen-transition responsiveness;
- test long-running sessions rather than only short screenshots.

If a premium visual effect materially hurts iPhone 12 performance, redesign the effect rather than accepting jank.

## Signature final experiences

The final product should pay disproportionate attention to the experiences users see most:

### Portrait Home
Make connection, vehicle identity, battery/range, mode, immediate controls, ride context, and recent activity feel cohesive rather than like independent cards.

### Landscape Dashboard
This is a signature Nembra experience. It should have a dominant beautiful speed instrument, excellent battery/range treatment, mode and ride context, minimal wasted space, and a premium cockpit hierarchy. Navigation must transform the same composition rather than feeling bolted on.

### Battery + adaptive range
The battery instrument should feel premium and trustworthy. Tapping the battery toggles percentage and estimated remaining range. Rolling values, fill behavior, charging/low-battery states, learning/confidence behavior, and range corrections should feel deliberate and stable.

### Live ride + navigation
Live data, map, route progress, maneuver information, speed, battery/range, trip, and duration must behave like one designed system.

### History, maps, and stats
Completed rides and statistics should feel like a desirable product experience, not a developer evidence viewer, while still preserving source truth and uncertainty.

## Anti-goals

Final Nembra must not look like:

- a generic Tuya dashboard;
- a developer/debug panel presented as product UI;
- a collection of unrelated rounded cards;
- a giant empty black screen with numbers floating in it;
- a gamer RGB dashboard;
- a cheap cross-platform port;
- a template SwiftUI app;
- a static mockup whose real interactions feel worse than the screenshot.

## Acceptance rule

Do not mark the Production Visual + Performance Overhaul complete because:

- all screens have been touched once;
- the code compiles;
- tests pass;
- one screenshot looks good;
- the UI is cleaner than before;
- every feature is visible;
- a reviewer says it is “fine.”

Final acceptance requires both:

1. **world-class visual/interaction quality across the major product surfaces and states**, and
2. **excellent real runtime behavior on the iPhone 12 / iOS 27 baseline**, including smoothness, responsiveness, accessibility, and long-session stability.

The project should reserve serious time for this phase. When underlying systems are done, do not immediately call Nembra 90–100% complete; a large amount of product work may still remain in turning those systems into an exceptional app.