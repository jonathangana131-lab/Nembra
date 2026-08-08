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

    /// `.buttonStyle(.plain)` does not provide Nembra's custom glass surface with a
    /// reliable disabled visual treatment. Keep the label readable while making the
    /// loss of interactivity visible in every material/transparency mode. This is
    /// presentation only; SwiftUI's `isEnabled` environment remains the interaction
    /// and accessibility authority.
    private var contentOpacity: Double {
        guard !isEnabled else { return 1 }
        return colorSchemeContrast == .increased ? 0.72 : 0.58
    }

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content
                    .opacity(contentOpacity)
                    .background(
                        Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(
                            cornerRadius: NembraMetrics.controlRadius,
                            style: .continuous
                        )
                    )
            } else if #available(iOS 26.0, *) {
                content
                    .opacity(contentOpacity)
                    .glassEffect(
                        .regular.interactive(isEnabled),
                        in: .rect(cornerRadius: NembraMetrics.controlRadius)
                    )
            } else {
                content
                    .opacity(contentOpacity)
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
