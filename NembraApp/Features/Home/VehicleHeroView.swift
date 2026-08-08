import SwiftUI

/// Decorative vehicle artwork for Home.
///
/// Identity, connection, lock, battery, range, and command truth stay in Home's
/// semantic UI. This view is intentionally visual-only so it cannot duplicate or
/// overstate vehicle state in VoiceOver.
struct VehicleHeroView: View {
    let profile: VehicleProfile
    let state: VehicleState

    var body: some View {
        vehicleArtwork
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var vehicleArtwork: some View {
        if profile.identity.manufacturer == "AOVOPRO" && profile.identity.model == "ES80" {
            AOVOPROES80SideArtwork(
                headlightOn: state.isHeadlightOn == true,
                connected: state.connection == .connected
            )
        } else if profile.identity.manufacturer == "MAXSHOT" && profile.identity.model == "V1S Pro" {
            MaxshotV1SProSideArtwork(
                headlightOn: state.isHeadlightOn == true,
                connected: state.connection == .connected
            )
        } else {
            GenericScooterArtwork(connected: state.connection == .connected)
        }
    }
}

/// Presentation-only silhouette for the primary AOVOPRO ES80 target. Public
/// product appearance informs the compact dark frame, reflector/cable detailing,
/// front lamp, mudguard and rear disc hardware. Decorative details stay neutral so
/// semantic green/amber/red remains reserved for meaningful product state. No
/// Bluetooth capability or telemetry meaning is inferred from the drawing.
private struct AOVOPROES80SideArtwork: View {
    let headlightOn: Bool
    let connected: Bool

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let frontWheel = CGPoint(x: w * 0.22, y: h * 0.77)
            let rearWheel = CGPoint(x: w * 0.80, y: h * 0.77)
            let wheelSize = min(h * 0.34, w * 0.16)

            ZStack {
                if connected {
                    Ellipse()
                        .fill(.primary.opacity(0.028))
                        .frame(width: w * 0.72, height: h * 0.21)
                        .position(x: w * 0.51, y: h * 0.84)
                }

                Path { path in
                    path.move(to: CGPoint(x: w * 0.29, y: h * 0.69))
                    path.addLine(to: CGPoint(x: w * 0.71, y: h * 0.69))
                    path.addLine(to: CGPoint(x: w * 0.76, y: h * 0.65))
                }
                .stroke(
                    .primary.opacity(0.92),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round)
                )

                Capsule(style: .continuous)
                    .fill(.secondary.opacity(0.48))
                    .frame(width: w * 0.31, height: 3)
                    .position(x: w * 0.52, y: h * 0.73)

                Path { path in
                    path.move(to: CGPoint(x: w * 0.31, y: h * 0.61))
                    path.addLine(to: CGPoint(x: frontWheel.x, y: frontWheel.y - wheelSize * 0.08))
                    path.move(to: CGPoint(x: w * 0.34, y: h * 0.61))
                    path.addLine(to: CGPoint(x: frontWheel.x + wheelSize * 0.10, y: frontWheel.y - wheelSize * 0.08))
                }
                .stroke(.primary.opacity(0.84), style: StrokeStyle(lineWidth: 5, lineCap: .round))

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.secondary.opacity(0.72))
                    .frame(width: 18, height: 11)
                    .rotationEffect(.degrees(-10))
                    .position(x: w * 0.34, y: h * 0.57)

                Path { path in
                    path.move(to: CGPoint(x: w * 0.34, y: h * 0.58))
                    path.addLine(to: CGPoint(x: w * 0.43, y: h * 0.15))
                }
                .stroke(.primary.opacity(0.94), style: StrokeStyle(lineWidth: 9, lineCap: .round))

                Path { path in
                    path.move(to: CGPoint(x: w * 0.35, y: h * 0.14))
                    path.addLine(to: CGPoint(x: w * 0.53, y: h * 0.14))
                }
                .stroke(.primary.opacity(0.94), style: StrokeStyle(lineWidth: 7, lineCap: .round))

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.primary.opacity(0.86))
                    .frame(width: 20, height: 11)
                    .rotationEffect(.degrees(-5))
                    .position(x: w * 0.435, y: h * 0.155)

                Path { path in
                    path.move(to: CGPoint(x: w * 0.405, y: h * 0.19))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.335, y: h * 0.54),
                        control: CGPoint(x: w * 0.365, y: h * 0.34)
                    )
                }
                .stroke(.secondary.opacity(0.38), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                Path { path in
                    path.move(to: CGPoint(x: rearWheel.x - wheelSize * 0.42, y: rearWheel.y - wheelSize * 0.20))
                    path.addQuadCurve(
                        to: CGPoint(x: rearWheel.x + wheelSize * 0.39, y: rearWheel.y - wheelSize * 0.17),
                        control: CGPoint(x: rearWheel.x, y: rearWheel.y - wheelSize * 0.61)
                    )
                }
                .stroke(.primary.opacity(0.76), style: StrokeStyle(lineWidth: 5, lineCap: .round))

                wheel(at: frontWheel, size: wheelSize, showsDisc: false)
                wheel(at: rearWheel, size: wheelSize, showsDisc: true)

                Capsule(style: .continuous)
                    .fill(.secondary.opacity(0.52))
                    .frame(width: w * 0.052, height: 4)
                    .rotationEffect(.degrees(-5))
                    .position(x: w * 0.73, y: h * 0.67)

                if headlightOn {
                    Circle()
                        .fill(.yellow)
                        .frame(width: 7, height: 7)
                        .position(x: w * 0.395, y: h * 0.24)
                        .shadow(color: .yellow.opacity(0.68), radius: 9, x: -5, y: 0)
                }
            }
        }
    }

    private func wheel(at point: CGPoint, size: CGFloat, showsDisc: Bool) -> some View {
        ZStack {
            Circle()
                .fill(.primary.opacity(0.93))
            Circle()
                .stroke(.secondary.opacity(0.48), lineWidth: 2)
                .padding(size * 0.16)
            Circle()
                .fill(.secondary.opacity(0.28))
                .padding(size * 0.39)

            if showsDisc {
                Circle()
                    .stroke(.secondary.opacity(0.62), lineWidth: 1.5)
                    .padding(size * 0.29)
                Capsule(style: .continuous)
                    .fill(.secondary.opacity(0.54))
                    .frame(width: size * 0.09, height: size * 0.18)
                    .offset(x: size * 0.19)
            }
        }
        .frame(width: size, height: size)
        .position(point)
    }
}

private struct MaxshotV1SProSideArtwork: View {
    let headlightOn: Bool
    let connected: Bool

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let frontWheel = CGPoint(x: w * 0.22, y: h * 0.76)
            let rearWheel = CGPoint(x: w * 0.79, y: h * 0.76)
            let wheelSize = min(h * 0.34, w * 0.17)

            ZStack {
                if connected {
                    Ellipse()
                        .fill(.primary.opacity(0.028))
                        .frame(width: w * 0.72, height: h * 0.22)
                        .position(x: w * 0.51, y: h * 0.83)
                }

                Path { path in
                    path.move(to: CGPoint(x: w * 0.30, y: h * 0.72))
                    path.addLine(to: CGPoint(x: w * 0.70, y: h * 0.72))
                    path.addLine(to: CGPoint(x: w * 0.76, y: h * 0.68))
                }
                .stroke(.primary.opacity(0.90), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))

                Path { path in
                    path.move(to: CGPoint(x: w * 0.29, y: h * 0.68))
                    path.addLine(to: CGPoint(x: w * 0.34, y: h * 0.54))
                    path.addLine(to: CGPoint(x: w * 0.39, y: h * 0.48))
                    path.addLine(to: CGPoint(x: w * 0.33, y: h * 0.66))
                    path.closeSubpath()
                }
                .fill(.secondary.opacity(0.58))

                Path { path in
                    path.move(to: CGPoint(x: w * 0.29, y: h * 0.58))
                    path.addLine(to: CGPoint(x: frontWheel.x - wheelSize * 0.08, y: frontWheel.y - wheelSize * 0.05))
                    path.move(to: CGPoint(x: w * 0.32, y: h * 0.59))
                    path.addLine(to: CGPoint(x: frontWheel.x + wheelSize * 0.08, y: frontWheel.y - wheelSize * 0.05))
                }
                .stroke(.primary.opacity(0.82), style: StrokeStyle(lineWidth: 5, lineCap: .round))

                Path { path in
                    path.move(to: CGPoint(x: w * 0.35, y: h * 0.54))
                    path.addLine(to: CGPoint(x: w * 0.43, y: h * 0.14))
                }
                .stroke(.primary.opacity(0.92), style: StrokeStyle(lineWidth: 10, lineCap: .round))

                Capsule(style: .continuous)
                    .fill(.primary.opacity(0.82))
                    .frame(width: w * 0.055, height: 9)
                    .rotationEffect(.degrees(-8))
                    .position(x: w * 0.35, y: h * 0.52)

                Path { path in
                    path.move(to: CGPoint(x: w * 0.34, y: h * 0.13))
                    path.addLine(to: CGPoint(x: w * 0.52, y: h * 0.13))
                }
                .stroke(.primary.opacity(0.92), style: StrokeStyle(lineWidth: 7, lineCap: .round))

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.primary.opacity(0.88))
                    .frame(width: 18, height: 10)
                    .position(x: w * 0.425, y: h * 0.145)

                Path { path in
                    path.move(to: CGPoint(x: rearWheel.x - wheelSize * 0.36, y: rearWheel.y - wheelSize * 0.34))
                    path.addQuadCurve(
                        to: CGPoint(x: rearWheel.x + wheelSize * 0.42, y: rearWheel.y - wheelSize * 0.20),
                        control: CGPoint(x: rearWheel.x + wheelSize * 0.06, y: rearWheel.y - wheelSize * 0.61)
                    )
                }
                .stroke(.primary.opacity(0.72), style: StrokeStyle(lineWidth: 5, lineCap: .round))

                wheel(at: frontWheel, size: wheelSize, front: true)
                wheel(at: rearWheel, size: wheelSize, front: false)

                Capsule(style: .continuous)
                    .fill(.secondary.opacity(0.48))
                    .frame(width: 5, height: 13)
                    .rotationEffect(.degrees(-8))
                    .position(x: w * 0.337, y: h * 0.50)

                Capsule(style: .continuous)
                    .fill(.secondary.opacity(0.48))
                    .frame(width: w * 0.055, height: 4)
                    .position(x: w * 0.70, y: h * 0.70)

                if headlightOn {
                    Circle()
                        .fill(.yellow)
                        .frame(width: 7, height: 7)
                        .position(x: w * 0.355, y: h * 0.18)
                        .shadow(color: .yellow.opacity(0.65), radius: 9, x: -6, y: 0)
                }
            }
        }
    }

    private func wheel(at point: CGPoint, size: CGFloat, front: Bool) -> some View {
        ZStack {
            Circle()
                .fill(.primary.opacity(0.92))
            Circle()
                .stroke(.secondary.opacity(0.42), lineWidth: 2)
                .padding(size * 0.15)
            Circle()
                .stroke(.secondary.opacity(front ? 0.46 : 0.28), lineWidth: front ? 2 : 1)
                .padding(size * 0.23)
            Circle()
                .fill(.secondary.opacity(0.28))
                .padding(size * 0.40)
        }
        .frame(width: size, height: size)
        .position(point)
    }
}

private struct GenericScooterArtwork: View {
    let connected: Bool

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                if connected {
                    Ellipse()
                        .fill(.primary.opacity(0.03))
                        .frame(width: w * 0.66, height: h * 0.20)
                        .position(x: w * 0.5, y: h * 0.82)
                }

                Path { path in
                    path.move(to: CGPoint(x: w * 0.27, y: h * 0.72))
                    path.addLine(to: CGPoint(x: w * 0.74, y: h * 0.72))
                    path.move(to: CGPoint(x: w * 0.32, y: h * 0.70))
                    path.addLine(to: CGPoint(x: w * 0.40, y: h * 0.18))
                    path.move(to: CGPoint(x: w * 0.33, y: h * 0.18))
                    path.addLine(to: CGPoint(x: w * 0.49, y: h * 0.18))
                }
                .stroke(.primary.opacity(0.85), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))

                wheel(at: CGPoint(x: w * 0.23, y: h * 0.76), size: h * 0.30)
                wheel(at: CGPoint(x: w * 0.78, y: h * 0.76), size: h * 0.30)
            }
        }
    }

    private func wheel(at point: CGPoint, size: CGFloat) -> some View {
        Circle()
            .stroke(.primary.opacity(0.85), lineWidth: 8)
            .overlay(Circle().stroke(.secondary.opacity(0.3), lineWidth: 2).padding(7))
            .frame(width: size, height: size)
            .position(point)
    }
}
