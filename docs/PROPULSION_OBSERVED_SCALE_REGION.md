# Propulsion Observed-Scale Region Presentation

## Purpose

Nembra's live cockpit needs a restrained way to emphasize when the newest **accepted** propulsion-power measurement is genuinely near the edge of a compatible observed-power presentation scale. That state must never be driven by render interpolation and must never be described as throttle position or a certified/rated hardware maximum.

`PropulsionObservedScaleRegionSnapshot` is the semantic handoff for that state.

## Accepted measurement, never display interpolation

The projection consumes `PropulsionGaugeDisplayModel.accessibilitySnapshot(...)`, not `PropulsionGaugeFrame.displayWatts` or `normalizedPropulsion`.

Therefore:
- a newly accepted high-power sample may enter the near-edge region immediately while the animated gauge is still rising from a lower value;
- a newly accepted low-power sample leaves the region immediately even while the animated gauge is visually falling from an earlier high value;
- display-refresh calls cannot manufacture repeated observations or extend near-edge evidence;
- retained/unavailable evidence never remains near-edge;
- incompatible or absent scale authority keeps accepted watts available but withholds the observed-scale region.

## Freshness is not animation

After propulsion freshness PR #315, animation response and accepted-measurement currentness are independent policies. This projection intentionally inherits currentness from the canonical accepted-only snapshot. Visual animation tuning, including a slower or faster response, cannot extend how long near-edge semantics stay live.

The focused regressions include a model with long animation settling time and a very short freshness interval; near-edge semantics become retained exactly when the freshness policy expires even though animation timing is unchanged.

## Region states

- `unavailable`: source/session presentation is unavailable or render chronology is invalid;
- `retained`: last accepted power remains known but is stale;
- `observedScaleUnavailable`: live accepted power exists but no compatible presentation scale is admitted;
- `normal`: accepted power is below the selected presentation threshold;
- `nearObservedScaleEdge`: accepted power is at or above the threshold on a compatible presentation scale.

The enum region is intentionally authority-agnostic so Simulator QA can exercise the same visual state. It is **not** by itself permission to display verified physical wording.

## Threshold policy

`PropulsionObservedScaleRegionPolicy` requires a finite `nearEdgeFraction` in `(0, 1]`. NembraCore deliberately provides no production default because selecting when subtle cockpit emphasis begins is product policy, not scooter truth.

The fraction is against the compatible **presentation scale**, which may include learned observed-envelope headroom. It is not a percentage of rated motor power, controller capacity, throttle travel, or any certified physical maximum.

## Product wording authority

The snapshot exposes two deliberately different conveniences:
- `isSimulatorNearObservedScaleEdge`: Simulator-QA classification for exercising the visual region;
- `permitsVerifiedNearObservedMaximumWording`: the production wording gate.

`permitsVerifiedNearObservedMaximumWording` can become true only when all of the following are simultaneously true:
1. the region is current and near the observed-scale edge;
2. the accepted measurement authority is `.verifiedVehicleMeasurement`;
3. the compatible presentation scale origin is `.verifiedObservedEnvelope`.

A future production cockpit may use that verified gate for restrained wording such as **Near observed max**. SwiftUI must not reconstruct or weaken this authority test from `isNearObservedScaleEdge` alone.

Even the verified wording gate does **not** mean throttle position, rated/certified motor or controller maximum, or a perfect continuous-time physical maximum. Do not derive or display **Full throttle**, **100% throttle**, **rated max**, or equivalent language from this state.

## Composition with the cockpit projection

Merged PR #322 owns the complementary cockpit-facing separation between accepted numeric power and render-only presentation:
- `measurement` is accepted numeric watts and provenance;
- `visualPropulsionFraction` is display-clock motion only;
- `recentAcceptedPeakMarkerFraction` is short-lived presentation context only.

This slice owns accepted observed-scale-region semantics and verified near-observed-maximum wording eligibility. A later app integration should compose the two layers rather than reimplementing either policy in SwiftUI.

The current branch is deliberately based on main **after #322 merged**, so package validation covers the real combined propulsion composition rather than a merely conflict-free pre-#322 ancestor.

## Integration status

This slice is package/domain-only. It does not modify `DashboardView.swift`, `Nembra.xcodeproj/project.pbxproj`, BLE/Tuya acquisition, observed-envelope persistence, rides, battery/range, navigation, or commands. The production app still manually compiles selected NembraCore source files, so a package test does not by itself prove this new type is app-visible.

## Truth boundary

**SOFTWARE / PRESENTATION SEMANTICS ONLY — NOT PHYSICAL AOVOPRO ES80 PROOF.**

No ES80 power/current/voltage DP, GATT characteristic, units, scaling, signedness, cadence, rated maximum, throttle position, regen behavior, battery/thermal state, or physical full-power ceiling is established here. Simulator evidence remains Simulator evidence. A learned observed gauge scale remains presentation calibration, not a certified hardware maximum.
