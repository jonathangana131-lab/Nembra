import SwiftUI

/// Selected Nembra 1.0 graphite / warm-gold product palette.
///
/// These colors belong to the content layer. Native Liquid Glass remains the
/// material for navigation and interactive chrome; telemetry and information
/// surfaces must not become stacks of custom translucent effects.
enum NembraColor {
    static let gold = Color(red: 0xEF / 255, green: 0xBC / 255, blue: 0x58 / 255)
    static let activeGold = Color(red: 0xE5 / 255, green: 0xA8 / 255, blue: 0x3C / 255)
    static let deepGold = Color(red: 0x9A / 255, green: 0x5F / 255, blue: 0x18 / 255)
    static let warmGraphite = Color(red: 0x0B / 255, green: 0x0B / 255, blue: 0x0A / 255)
    static let baseBlack = Color(red: 0x06 / 255, green: 0x07 / 255, blue: 0x06 / 255)
    static let primaryText = Color(red: 0xF4 / 255, green: 0xF7 / 255, blue: 0xFB / 255)
    static let secondaryText = Color(red: 0x8D / 255, green: 0x98 / 255, blue: 0xAA / 255)
    static let quietLine = Color.white.opacity(0.10)
    static let quietSurface = Color.white.opacity(0.045)
}

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
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityShowBorders) private var showBorders
    @Environment(\.isEnabled) private var isEnabled

    /// Normal Liquid Glass already adapts to Increased Contrast at the material layer.
    /// Nembra adds a strong explicit boundary only when Show Borders asks custom
    /// controls to expose their edges, or when Reduce Transparency replaces glass
    /// with our opaque fallback and therefore removes that native glass adaptation.
    private var strongExplicitBoundaryRequested: Bool {
        showBorders || (reduceTransparency && colorSchemeContrast == .increased)
    }

    private var shouldShowExplicitBoundary: Bool {
        reduceTransparency || showBorders
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

    /// Stable product background shared by portrait content and the Horizon
    /// cockpit. This is intentionally opaque and cheap to composite.
    func nembraProductBackground() -> some View {
        background(NembraColor.baseBlack.ignoresSafeArea())
    }
}
