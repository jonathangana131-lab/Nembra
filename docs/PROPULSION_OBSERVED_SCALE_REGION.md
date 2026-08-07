# Propulsion Observed-Scale Region Presentation

## Purpose

Nembra's live cockpit needs a restrained way to emphasize when the newest **accepted** propulsion-power measurement is genuinely near the edge of a compatible observed-power presentation scale. That state must never be driven by render interpolation and must never be described as throttle position or a certified/rated hardware maximum.

`PropulsionObservedScaleRegionSnapshot` is the semantic handoff for that state. `PropulsionGaugeCockpitCompositionSnapshot` now lets the future high-frequency cockpit consume this semantic state together with accepted numeric/render presentation from one canonical frame evaluation.

## Accepted measurement, never display interpolation

The standalone projection evaluates the canonical frame once, derives an accepted-only `PropulsionGaugeAccessibilitySnapshot`, then applies observed-scale semantics. The combined cockpit projection reuses the same accepted-only helper from the exact frame already used for cockpit render geometry.

Neither path consumes `PropulsionGaugeFrame.displayWatts` or `normalizedPropulsion` as semantic evidence.

Therefore:
- a newly accepted high-power sample may enter the near-edge region immediately while the animated gauge is still rising from a lower value;
- a newly accepted low-power sample leaves the region immediately even while the animated gauge is visually falling from an earlier high value;
- display-refresh calls cannot manufacture repeated observations or extend near-edge evidence;
- retained/unavailable evidence never remains near-edge;
- incompatible or absent scale authority keeps accepted watts available but withholds the observed-scale region.

## Freshness is not animation

Animation response and accepted-measurement currentness are independent policies. This projection intentionally inherits currentness from canonical accepted evidence. Visual animation tuning, including a slower or faster response, cannot extend how long near-edge semantics stay live.

The focused regressions include long animation settling with a short freshness interval; near-edge semantics become retained exactly when freshness expires even though render timing is unchanged.

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

The cockpit-facing projection owns:
- `measurement` as accepted numeric watts and provenance;
- `visualPropulsionFraction` as display-clock motion only;
- `recentAcceptedPeakMarkerFraction` as short-lived presentation context only.

This layer owns accepted observed-scale-region semantics and verified near-observed-maximum wording eligibility.

`cockpitCompositionSnapshot(...)` is the integration seam between them. It evaluates the canonical gauge frame exactly once, then:
1. derives the cockpit snapshot from that frame;
2. derives accepted-only accessibility/scale evidence from that same frame;
3. derives this semantic region from that accepted-only evidence.

The combined snapshot is sealed against arbitrary cross-tick pairing. This avoids duplicated frame/interpolation work on a future 60 Hz render path without weakening either truth contract.

Standalone projection APIs remain available and behaviorally identical for focused consumers. SwiftUI should prefer the combined snapshot when it needs both layers on the same render tick.

## Integration status

This remains package/domain-only. It does not modify `DashboardView.swift`, `Nembra.xcodeproj/project.pbxproj`, BLE/Tuya acquisition, observed-envelope persistence, rides, battery/range, navigation, or commands. The production app still requires deliberate source visibility/wiring and real Simulator/runtime acceptance before this composition is a shipped cockpit feature.

## Truth boundary

**SOFTWARE / PRESENTATION SEMANTICS ONLY — NOT PHYSICAL AOVOPRO ES80 PROOF.**

No ES80 power/current/voltage DP, GATT characteristic, units, scaling, signedness, cadence, rated maximum, throttle position, regen behavior, battery/thermal state, or physical full-power ceiling is established here. Simulator evidence remains Simulator evidence. A learned observed gauge scale remains presentation calibration, not a certified hardware maximum.