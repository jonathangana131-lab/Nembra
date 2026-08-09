import SwiftUI

enum NembraMetrics {
    static let compact: CGFloat = 8
    static let control: CGFloat = 12
    static let group: CGFloat = 16
    static let section: CGFloat = 24
    static let major: CGFloat = 32
    static let controlRadius: CGFloat = 20
    static let heroRadius: CGFloat = 28
}

struct NembraGlassButtonStyle: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityShowBorders) private var showBorders
    @Environment(\.isEnabled) private var isEnabled

    /// Normal Liquid Glass already adapts to Increased Contrast at the material layer.
    /// Nembra adds a strong explicit boundary when accessibility asks controls to be
    /// distinguishable without color or to expose their edges, or when Reduce
    /// Transparency replaces glass with our opaque fallback and therefore removes
    /// that native glass adaptation.
    private var strongExplicitBoundaryRequested: Bool {
        showBorders || differentiateWithoutColor || (reduceTransparency && colorSchemeContrast == .increased)
    }

    private var shouldShowExplicitBoundary: Bool {
        reduceTransparency || showBorders || differentiateWithoutColor
    }

    private var boundaryOpacity: Double {
        strongExplicitBoundaryRequested ? 0.42 : 0.16
    }

    private var boundaryLineWidth: CGFloat {
        strongExplicitBoundaryRequested ? 1.5 : 1
    }

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content
                    .background(
                        Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(
                            cornerRadius: NembraMetrics.controlRadius,
                            style: .continuous
                        )
                    )
            } else if #available(iOS 26.0, *) {
                content
                    .glassEffect(
                        .regular.interactive(isEnabled),
                        in: .rect(cornerRadius: NembraMetrics.controlRadius)
                    )
            } else {
                content
                    .background(
                        .thinMaterial,
                        in: RoundedRectangle(
                            cornerRadius: NembraMetrics.controlRadius,
                            style: .continuous
                        )
                    )
            }
        }
        .overlay {
            controlBoundary
        }
    }

    @ViewBuilder
    private var controlBoundary: some View {
        if shouldShowExplicitBoundary {
            RoundedRectangle(
                cornerRadius: NembraMetrics.controlRadius,
                style: .continuous
            )
            .strokeBorder(
                Color.primary.opacity(boundaryOpacity),
                lineWidth: boundaryLineWidth
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    func nembraGlassControl() -> some View { modifier(NembraGlassButtonStyle()) }
}

/// Visual currentness only. The eventual Dashboard adapter must derive this from
/// `PropulsionEnergyRailPresentation`; this enum does not grant telemetry authority.
enum NembraEnergyRailVisualCurrentness: Equatable {
    case live
    case retained
    case unavailable
}

/// App-side visual input for the signature propulsion instrument.
///
/// `acceptedWatts` is the semantic number shown to the user. `railFraction` and
/// `peakMarkerFraction` are display-only geometry and must never be converted back
/// into watts, persisted, or promoted into ride/protocol evidence. The view also
/// refuses rail motion unless currentness is live and the caller explicitly admits it.
struct NembraEnergyRailVisualState: Equatable {
    let currentness: NembraEnergyRailVisualCurrentness
    let acceptedWatts: Double?
    let railFraction: Double?
    let peakMarkerFraction: Double?
    let allowsLiveMotion: Bool

    var semanticWatts: Double? {
        guard currentness != .unavailable,
              let acceptedWatts,
              acceptedWatts.isFinite,
              acceptedWatts >= 0 else {
            return nil
        }
        return acceptedWatts == 0 ? 0 : acceptedWatts
    }

    var admittedRailFraction: Double? {
        guard currentness == .live,
              semanticWatts != nil,
              allowsLiveMotion,
              let railFraction,
              railFraction.isFinite,
              railFraction >= 0,
              railFraction <= 1 else {
            return nil
        }
        return railFraction
    }

    var admittedPeakMarkerFraction: Double? {
        guard admittedRailFraction != nil,
              let peakMarkerFraction,
              peakMarkerFraction.isFinite,
              peakMarkerFraction >= 0,
              peakMarkerFraction <= 1 else {
            return nil
        }
        return peakMarkerFraction
    }
}

/// Shallow off-screen-wheel/horizon geometry used by the Energy Rail.
/// The rail is intentionally not a circular gauge and carries no regen direction.
private struct NembraEnergyRailArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseline = rect.height * 0.88
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + baseline))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + baseline),
            control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.16)
        )
        return path
    }
}

/// Accepted-watt numeral renderer using the same fixed-slot rolling primitive as
/// the speed instrument. Intermediate glyph motion is display-only; VoiceOver is
/// owned by the enclosing Energy Rail and announces only the accepted semantic value.
private struct NembraRollingPowerValueView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Double
    let fontSize: CGFloat

    private static let numberModel: RollingNumberModel? = {
        guard let layout = try? RollingNumberLayout(integerDigits: 4) else { return nil }
        return try? RollingNumberModel(layout: layout)
    }()

    /// Compact fallback capacity only, never a physical motor/controller maximum.
    private static let maximumFallbackDisplayInteger = 99_999.0

    var body: some View {
        if let numberModel = Self.numberModel,
           let snapshot = try? numberModel.snapshot(for: value) {
            HStack(spacing: -4) {
                ForEach(snapshot.digits.indices, id: \.self) { index in
                    let digit = snapshot.digits[index]
                    Text(String(digit.digit))
                        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .opacity(digit.isVisible ? 1 : 0)
                        .contentTransition(
                            reduceMotion ? .identity : .numericText(value: value)
                        )
                }
            }
            .animation(
                reduceMotion ? nil : .linear(duration: 0.08),
                value: snapshot.scaledValue
            )
        } else if let fallbackText {
            Text(fallbackText)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(
                    reduceMotion ? .identity : .numericText(value: value)
                )
        } else {
            Text("—")
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
        }
    }

    private var fallbackText: String? {
        guard value.isFinite, value >= 0 else { return nil }
        let rounded = value.rounded(.toNearestOrAwayFromZero)
        guard rounded <= Self.maximumFallbackDisplayInteger else { return nil }
        return String(Int(rounded))
    }
}

/// Localized SwiftUI renderer for the Nembra Energy Rail.
///
/// The caller owns the display clock. This view does not add a second smoothing
/// algorithm to `railFraction`; every render frame is drawn immediately so a newer
/// accepted target can retarget the canonical gauge model without queued stale motion.
/// Only the semantic accepted watt number receives a brief numeric transition.
struct NembraEnergyRailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var powerFontSize: CGFloat = 30

    let state: NembraEnergyRailVisualState

    var body: some View {
        ZStack(alignment: .top) {
            railLayer
                .frame(height: 72)
                .padding(.top, railTopPadding)

            powerReadout
        }
        .frame(maxWidth: .infinity, minHeight: componentMinimumHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Propulsion power")
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("dashboard.energy-rail")
    }

    private var railLayer: some View {
        GeometryReader { proxy in
            ZStack {
                NembraEnergyRailArc()
                    .stroke(
                        Color.primary.opacity(baseRailOpacity),
                        style: StrokeStyle(lineWidth: baseRailWidth, lineCap: .round)
                    )

                if let admittedFraction = state.admittedRailFraction {
                    let fraction = CGFloat(admittedFraction)

                    if !reduceTransparency {
                        NembraEnergyRailArc()
                            .trim(from: 0, to: fraction)
                            .stroke(
                                Color.primary.opacity(0.24),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round)
                            )
                    }

                    NembraEnergyRailArc()
                        .trim(from: 0, to: fraction)
                        .stroke(
                            Color.primary,
                            style: StrokeStyle(lineWidth: activeRailWidth, lineCap: .round)
                        )

                    if let admittedMarker = state.admittedPeakMarkerFraction {
                        peakMarker(at: CGFloat(admittedMarker), in: proxy.size)
                    }
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var powerReadout: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let watts = state.semanticWatts {
                    NembraRollingPowerValueView(value: watts, fontSize: powerFontSize)
                } else {
                    Text("—")
                        .font(.system(size: powerFontSize, weight: .semibold, design: .rounded))
                }

                Text("W")
                    .font(dynamicTypeSize.isAccessibilitySize ? .body.weight(.bold) : .caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Text(currentnessLabel)
                .font(dynamicTypeSize.isAccessibilitySize ? .caption.weight(.bold) : .caption2.weight(.bold))
                .tracking(dynamicTypeSize.isAccessibilitySize ? 0.4 : 1.2)
                .foregroundStyle(currentnessForeground)
        }
    }

    @ViewBuilder
    private func peakMarker(at fraction: CGFloat, in size: CGSize) -> some View {
        let point = pointOnRail(at: fraction, in: size)

        Capsule(style: .continuous)
            .fill(Color.primary)
            .frame(width: 2, height: colorSchemeContrast == .increased ? 13 : 10)
            .position(point)
            .accessibilityHidden(true)
    }

    private func pointOnRail(at fraction: CGFloat, in size: CGSize) -> CGPoint {
        let t = fraction
        let inverse = 1 - t
        let baseline = size.height * 0.88
        let controlY = size.height * 0.16
        let y = inverse * inverse * baseline
            + 2 * inverse * t * controlY
            + t * t * baseline
        return CGPoint(x: size.width * t, y: y)
    }

    private var currentnessLabel: String {
        switch state.currentness {
        case .live:
            state.semanticWatts == nil ? "POWER UNAVAILABLE" : "LIVE POWER"
        case .retained:
            state.semanticWatts == nil ? "POWER UNAVAILABLE" : "LAST KNOWN POWER"
        case .unavailable:
            "POWER UNAVAILABLE"
        }
    }

    private var currentnessForeground: Color {
        switch state.currentness {
        case .live where state.semanticWatts != nil:
            Color.primary.opacity(colorSchemeContrast == .increased ? 0.88 : 0.68)
        case .retained where state.semanticWatts != nil:
            Color.primary.opacity(colorSchemeContrast == .increased ? 0.66 : 0.50)
        default:
            Color.primary.opacity(colorSchemeContrast == .increased ? 0.50 : 0.32)
        }
    }

    private var accessibilityValue: String {
        guard let watts = state.semanticWatts else { return "Unavailable" }
        let formatted = watts.formatted(.number.precision(.fractionLength(0)))

        switch state.currentness {
        case .live:
            return "\(formatted) watts"
        case .retained:
            return "\(formatted) watts, last known"
        case .unavailable:
            return "Unavailable"
        }
    }

    private var componentMinimumHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 156 : 94
    }

    private var railTopPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 76 : 22
    }

    private var baseRailOpacity: Double {
        colorSchemeContrast == .increased ? 0.28 : 0.14
    }

    private var baseRailWidth: CGFloat {
        colorSchemeContrast == .increased ? 3.5 : 2.5
    }

    private var activeRailWidth: CGFloat {
        colorSchemeContrast == .increased ? 7 : 5.5
    }
}
