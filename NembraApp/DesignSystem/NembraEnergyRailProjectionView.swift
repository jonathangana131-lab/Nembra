import SwiftUI
import struct NembraCore.PropulsionEnergyRailAccessibilityPresentation
import struct NembraCore.PropulsionEnergyRailAccessibilitySemanticRevision
import struct NembraCore.PropulsionEnergyRailAppProjection
import enum NembraCore.PropulsionEnergyRailCurrentness

/// App-facing Energy Rail boundary that keeps the 60 Hz visual clock separate from
/// assistive-technology semantic cadence.
///
/// The package projection remains the single authority subject. The existing visual
/// renderer is explicitly hidden from accessibility because it can redraw on every
/// display frame. A tiny accessibility-only sibling is instead keyed by the package's
/// `semanticRevision`, which excludes interpolated watts/rail geometry while still
/// changing when accepted evidence identity or currentness meaningfully changes.
struct NembraEnergyRailProjectionView: View {
    let projection: PropulsionEnergyRailAppProjection

    var body: some View {
        ZStack {
            NembraEnergyRailView(
                state: NembraEnergyRailVisualState(projection: projection)
            )
            .accessibilityHidden(true)

            NembraEnergyRailAccessibilityElement(
                presentation: projection.accessibilityPresentation
            )
            .equatable()
        }
    }
}

/// Accessibility-only state. Equality intentionally follows the package semantic
/// revision rather than render watts, rail fraction, peak geometry, or any other
/// display-clock field.
///
/// `value` is derived from the same sealed accessibility presentation. If two states
/// have the same semantic revision, NembraCore's cadence contract guarantees their
/// accepted/currentness semantics are the same; SwiftUI may therefore skip rebuilding
/// this subtree while the visible rail continues animating independently.
private struct NembraEnergyRailAccessibilityElement: View, Equatable {
    let semanticRevision: PropulsionEnergyRailAccessibilitySemanticRevision
    let value: String

    init(presentation: PropulsionEnergyRailAccessibilityPresentation) {
        semanticRevision = presentation.semanticRevision
        value = Self.accessibilityValue(for: presentation)
    }

    static func == (
        lhs: NembraEnergyRailAccessibilityElement,
        rhs: NembraEnergyRailAccessibilityElement
    ) -> Bool {
        lhs.semanticRevision == rhs.semanticRevision
    }

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Propulsion power")
            .accessibilityValue(value)
            .accessibilityIdentifier("dashboard.energy-rail")
    }

    private static func accessibilityValue(
        for presentation: PropulsionEnergyRailAccessibilityPresentation
    ) -> String {
        switch presentation.currentness {
        case .live:
            guard let watts = admittedWatts(presentation.acceptedWatts) else {
                return "Unavailable"
            }
            return "\(formattedWatts(watts)) watts"

        case .retained:
            guard let watts = admittedWatts(presentation.acceptedWatts) else {
                return "Unavailable"
            }
            return "\(formattedWatts(watts)) watts, last known"

        case .unavailable:
            return "Unavailable"
        }
    }

    private static func admittedWatts(_ watts: Double?) -> Double? {
        guard let watts, watts.isFinite, watts >= 0 else { return nil }
        return watts == 0 ? 0 : watts
    }

    private static func formattedWatts(_ watts: Double) -> String {
        watts.formatted(.number.precision(.fractionLength(0)))
    }
}
