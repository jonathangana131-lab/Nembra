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
}
