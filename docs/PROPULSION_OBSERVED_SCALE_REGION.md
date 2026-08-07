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

## Generic visual-region threshold policy

`PropulsionObservedScaleRegionPolicy` requires a finite `nearEdgeFraction` in `(0, 1]`. NembraCore deliberately provides no production default because selecting when subtle cockpit emphasis begins is product presentation policy, not scooter truth.

This generic threshold may also be intentionally loose in Simulator QA or visual experimentation. For example, a caller may choose `0.01` to exercise the near-edge visual state across a broad synthetic range. That flexibility is useful, but it means the generic threshold can never be the sole authority for language such as **Near observed max**.

The fraction is against the compatible **presentation scale**, which may include learned observed-envelope headroom. It is not a percentage of rated motor power, controller capacity, throttle travel, or any certified physical maximum.

## Product-owned verified wording policy

Verified near-observed-maximum language has a separate source-owned semantic boundary: `PropulsionVerifiedNearObservedMaximumWordingPolicy.product`.

The current product wording floor is `0.90` of a compatible learned observed-envelope presentation scale. Its initializer is private, so ordinary callers cannot weaken the wording gate by passing an arbitrary low fraction. Changing this language boundary therefore requires an explicit Nembra source change and review rather than a visual configuration tweak.

This `0.90` boundary is deliberately **not** an AOVOPRO ES80 hardware claim. It does not mean 90% throttle, 90% rated motor/controller output, a certified full-power threshold, or 90% of a perfect physical maximum. It is only a conservative product-language boundary on Nembra's learned observed **presentation scale**.

The generic visual region and verified wording policy are intentionally intersected:
- the generic region decides whether the current presentation is considered near-edge for visual semantics;
- the product-owned wording floor independently prevents a loose generic region from weakening language integrity.

Therefore a generic `nearEdgeFraction = 0.01` may legitimately produce `.nearObservedScaleEdge` at 1% for visual QA, while `permitsVerifiedNearObservedMaximumWording` remains false until accepted evidence is at least the product-owned wording floor and all verified-authority requirements are also satisfied.

A stricter generic visual threshold remains conservative: if the visual region is still `.normal`, verified wording remains unavailable even when the accepted fraction has crossed the product wording floor.

## Product wording authority

The snapshot exposes two deliberately different conveniences:
- `isSimulatorNearObservedScaleEdge`: Simulator-QA classification for exercising the visual region;
- `permitsVerifiedNearObservedMaximumWording`: the production wording gate.

`permitsVerifiedNearObservedMaximumWording` can become true only when all of the following are simultaneously true:
1. the configurable observed-scale region is current and `.nearObservedScaleEdge`;
2. the accepted observed-scale fraction is finite, valid, and at or above `PropulsionVerifiedNearObservedMaximumWordingPolicy.product.minimumObservedScaleFraction`;
3. the accepted measurement authority is `.verifiedVehicleMeasurement`;
4. the compatible presentation scale origin is `.verifiedObservedEnvelope`.

A caller-selected generic visual threshold cannot weaken item 2. A future production cockpit may use this verified gate for restrained wording such as **Near observed max**. SwiftUI must not reconstruct or weaken this authority test from `isNearObservedScaleEdge` alone.

Simulator evidence cannot satisfy the verified wording gate even at the visual scale edge because Simulator measurement and scale origins remain explicitly Simulator-only.

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
