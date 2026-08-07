import SwiftUI
import UIKit

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

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: NembraMetrics.controlRadius,
            style: .continuous
        )

        if reduceTransparency {
            content
                .background(Color(uiColor: .secondarySystemBackground), in: shape)
                .overlay {
                    shape.stroke(
                        .primary.opacity(colorSchemeContrast == .increased ? 0.34 : 0.14),
                        lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                    )
                    .allowsHitTesting(false)
                }
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.interactive(),
                    in: .rect(cornerRadius: NembraMetrics.controlRadius)
                )
                .overlay {
                    if colorSchemeContrast == .increased {
                        shape.stroke(.primary.opacity(0.28), lineWidth: 1.25)
                            .allowsHitTesting(false)
                    }
                }
        } else {
            content
                .background(.thinMaterial, in: shape)
                .overlay {
                    if colorSchemeContrast == .increased {
                        shape.stroke(.primary.opacity(0.28), lineWidth: 1.25)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

extension View {
    func nembraGlassControl() -> some View { modifier(NembraGlassButtonStyle()) }
}
