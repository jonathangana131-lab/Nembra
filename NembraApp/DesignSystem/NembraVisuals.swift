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

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(
                    Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(
                        cornerRadius: NembraMetrics.controlRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: NembraMetrics.controlRadius,
                        style: .continuous
                    )
                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                }
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: NembraMetrics.controlRadius))
        } else {
            content
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: NembraMetrics.controlRadius, style: .continuous))
        }
    }
}

extension View {
    func nembraGlassControl() -> some View { modifier(NembraGlassButtonStyle()) }
}
