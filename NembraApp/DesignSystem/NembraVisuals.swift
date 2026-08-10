import SwiftUI
import struct NembraCore.PropulsionEnergyRailAccessibilitySemanticRevision
import struct NembraCore.PropulsionEnergyRailAppProjection

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

    /// Native glass adapts to Increased Contrast. Nembra adds an explicit structural
    /// boundary when accessibility asks controls to remain distinguishable without
    /// color, when Show Borders is enabled, or when Reduce Transparency removes glass.
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

enum NembraEnergyRailVisualCurrentness: Equatable {
    case live
    case retained
    case unavailable
}

/// Accessibility semantics are pinned to NembraCore's semantic revision. The 60 Hz
/// display clock can therefore move digits/rail geometry without creating new
/// assistive-technology evidence or announcements.
private struct NembraEnergyRailAccessibilityState: Equatable {
    let semanticRevision: PropulsionEnergyRailAccessibilitySemanticRevision
    let currentness: NembraEnergyRailVisualCurrentness
    let acceptedWatts: Double?

    var value: String {
        guard let acceptedWatts else { return "Unavailable" }
        let formatted = acceptedWatts.formatted(.number.precision(.fractionLength(0)))
        switch currentness {
        case .live:
            return "\(formatted) watts"
        case .retained:
            return "\(formatted) watts, last known"
        case .unavailable:
            return "Unavailable"
        }
    }
}

/// SwiftUI may consume this state but cannot construct numeric authority. The sole
/// initializer accepts NembraCore's sealed app projection and fails closed if semantic
/// and accessibility truth disagree. Render fields remain presentation-only.
struct NembraEnergyRailVisualState: Equatable {
    let currentness: NembraEnergyRailVisualCurrentness
    let acceptedWatts: Double?
    let displayWatts: Double?
    let railFraction: Double?
    let acceptedTargetFraction: Double?
    let peakMarkerFraction: Double?
    let allowsLiveMotion: Bool
    fileprivate let accessibilityState: NembraEnergyRailAccessibilityState

    init?(projection: PropulsionEnergyRailAppProjection) {
        let accessibility = projection.accessibilityPresentation
        let mappedCurrentness: NembraEnergyRailVisualCurrentness
        switch projection.currentness {
        case .live: mappedCurrentness = .live
        case .retained: mappedCurrentness = .retained
        case .unavailable: mappedCurrentness = .unavailable
        }

        guard accessibility.currentness == projection.currentness else { return nil }

        switch mappedCurrentness {
        case .live:
            guard let accepted = projection.acceptedWatts,
                  accepted.isFinite,
                  accepted >= 0,
                  accessibility.acceptedWatts == accepted,
                  accessibility.acceptedRevision != nil else { return nil }
            currentness = .live
            acceptedWatts = accepted == 0 ? 0 : accepted
            displayWatts = Self.validWatts(projection.displayWatts) ?? acceptedWatts
            railFraction = Self.validFraction(projection.railFraction)
            acceptedTargetFraction = Self.validFraction(projection.acceptedTargetFraction)
            peakMarkerFraction = Self.validFraction(projection.acceptedPeakMarkerFraction)
            allowsLiveMotion = projection.allowsLiveMotion && railFraction != nil

        case .retained:
            guard let accepted = projection.acceptedWatts,
                  accepted.isFinite,
                  accepted >= 0,
                  accessibility.acceptedWatts == accepted,
                  accessibility.acceptedRevision != nil else { return nil }
            currentness = .retained
            acceptedWatts = accepted == 0 ? 0 : accepted
            displayWatts = acceptedWatts
            railFraction = nil
            acceptedTargetFraction = nil
            peakMarkerFraction = nil
            allowsLiveMotion = false

        case .unavailable:
            guard projection.acceptedWatts == nil,
                  accessibility.acceptedWatts == nil,
                  accessibility.acceptedRevision == nil else { return nil }
            currentness = .unavailable
            acceptedWatts = nil
            displayWatts = nil
            railFraction = nil
            acceptedTargetFraction = nil
            peakMarkerFraction = nil
            allowsLiveMotion = false
        }

        accessibilityState = NembraEnergyRailAccessibilityState(
            semanticRevision: accessibility.semanticRevision,
            currentness: currentness,
            acceptedWatts: acceptedWatts
        )
    }

    private static func validWatts(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value == 0 ? 0 : value
    }

    private static func validFraction(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0, value <= 1 else { return nil }
        return value
    }

    var semanticWatts: Double? { acceptedWatts }

    var admittedDisplayWatts: Double? {
        guard let acceptedWatts else { return nil }
        guard currentness == .live,
              allowsLiveMotion,
              let displayWatts else { return acceptedWatts }
        return displayWatts
    }

    var admittedRailFraction: Double? {
        guard currentness == .live, allowsLiveMotion else { return nil }
        return railFraction
    }

    var admittedAcceptedTargetFraction: Double? {
        guard currentness == .live else { return nil }
        return acceptedTargetFraction
    }

    var admittedPeakMarkerFraction: Double? {
        guard admittedRailFraction != nil else { return nil }
        return peakMarkerFraction
    }
}

/// Extremely shallow wheel-horizon geometry. It deliberately carries no regen,
/// throttle, rated-power, or controller-maximum semantics.
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

/// Localized money-roll renderer. Intermediate digit motion is display-only and is
/// hidden from accessibility; accepted semantic watts remain owned by the parent.
private struct NembraRollingPowerValueView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Double
    let fontSize: CGFloat

    private static let numberModel: RollingNumberModel? = {
        guard let layout = try? RollingNumberLayout(integerDigits: 4) else { return nil }
        return try? RollingNumberModel(layout: layout)
    }()

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
                        .contentTransition(reduceMotion ? .identity : .numericText(value: value))
                        .animation(reduceMotion ? nil : .snappy(duration: 0.10), value: digit.digit)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: digit.isVisible)
                        .clipped()
                }
            }
        } else {
            Text(value.formatted(.number.precision(.fractionLength(0))))
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}

private struct NembraEnergyRailAccessibilityRepresentation: View, Equatable {
    let state: NembraEnergyRailAccessibilityState

    var body: some View {
        Text("Propulsion power")
            .accessibilityLabel("Propulsion power")
            .accessibilityValue(state.value)
            .accessibilityIdentifier("dashboard.energy-rail")
    }
}

/// Signature bottom propulsion instrument. The caller owns the display clock; this
/// view adds no second smoothing queue. Reduce Motion snaps to exact accepted watts
/// and package-derived accepted target geometry while preserving freshness semantics.
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
        .accessibilityRepresentation {
            NembraEnergyRailAccessibilityRepresentation(state: state.accessibilityState)
                .equatable()
        }
    }

    private var railLayer: some View {
        GeometryReader { proxy in
            ZStack {
                NembraEnergyRailArc()
                    .stroke(
                        Color.primary.opacity(colorSchemeContrast == .increased ? 0.28 : 0.14),
                        style: StrokeStyle(
                            lineWidth: colorSchemeContrast == .increased ? 3.5 : 2.5,
                            lineCap: .round
                        )
                    )

                if let admittedFraction = displayedRailFraction {
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
                            style: StrokeStyle(
                                lineWidth: colorSchemeContrast == .increased ? 7 : 5.5,
                                lineCap: .round
                            )
                        )

                    if !reduceMotion,
                       let marker = state.admittedPeakMarkerFraction {
                        peakMarker(at: CGFloat(marker), in: proxy.size)
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
                if let watts = displayedWatts {
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

    private var displayedWatts: Double? {
        reduceMotion ? state.semanticWatts : state.admittedDisplayWatts
    }

    private var displayedRailFraction: Double? {
        reduceMotion ? state.admittedAcceptedTargetFraction : state.admittedRailFraction
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
        let inverse = 1 - fraction
        let baseline = size.height * 0.88
        let controlY = size.height * 0.16
        let y = inverse * inverse * baseline
            + 2 * inverse * fraction * controlY
            + fraction * fraction * baseline
        return CGPoint(x: size.width * fraction, y: y)
    }

    private var currentnessLabel: String {
        switch state.currentness {
        case .live where state.semanticWatts != nil:
            return "LIVE POWER"
        case .retained where state.semanticWatts != nil:
            return "LAST KNOWN POWER"
        default:
            return "POWER UNAVAILABLE"
        }
    }

    private var currentnessForeground: Color {
        switch state.currentness {
        case .live where state.semanticWatts != nil:
            return Color.primary.opacity(colorSchemeContrast == .increased ? 0.88 : 0.68)
        case .retained where state.semanticWatts != nil:
            return Color.primary.opacity(colorSchemeContrast == .increased ? 0.66 : 0.50)
        default:
            return Color.primary.opacity(colorSchemeContrast == .increased ? 0.50 : 0.32)
        }
    }

    private var componentMinimumHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 156 : 94
    }

    private var railTopPadding: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 76 : 22
    }
}