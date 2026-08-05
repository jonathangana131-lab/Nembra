import SwiftUI

struct VehicleHeroView: View {
    let profile: VehicleProfile
    let state: VehicleState

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(profile.identity.displayName)
                        .font(.title2.weight(.bold))
                    Text(statusLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
                if state.isLocked == true {
                    Image(systemName: "lock.fill")
                        .font(.headline)
                        .padding(10)
                        .background(.thinMaterial, in: Circle())
                        .accessibilityLabel("Scooter locked")
                }
            }

            ScooterSilhouette(headlightOn: state.isHeadlightOn == true, connected: state.connection == .connected)
                .frame(height: 225)
                .accessibilityHidden(true)
        }
        .padding(.top, 10)
    }

    private var statusLine: String {
        switch state.connection {
        case .connected:
            if let speed = state.speedKilometersPerHour, speed > 0.5 {
                return "Riding · \(VehicleDisplayFormatting.speed(kilometersPerHour: speed))"
            }
            return state.isLocked == true ? "Connected · secured" : "Connected · ready"
        case .connecting:
            return "Connecting…"
        case .reconnecting:
            return "Reconnecting…"
        case .disconnected:
            return "Scooter offline"
        }
    }
}

private struct ScooterSilhouette: View {
    let headlightOn: Bool
    let connected: Bool

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                if connected {
                    Ellipse()
                        .fill(.primary.opacity(0.035))
                        .frame(width: w * 0.7, height: h * 0.3)
                        .offset(y: h * 0.28)
                }

                Path { path in
                    path.move(to: CGPoint(x: w * 0.31, y: h * 0.73))
                    path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.73))
                    path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.67))
                }
                .stroke(.primary.opacity(0.88), style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))

                Path { path in
                    path.move(to: CGPoint(x: w * 0.70, y: h * 0.68))
                    path.addLine(to: CGPoint(x: w * 0.60, y: h * 0.19))
                    path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.16))
                }
                .stroke(.primary.opacity(0.88), style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))

                Path { path in
                    path.move(to: CGPoint(x: w * 0.47, y: h * 0.16))
                    path.addLine(to: CGPoint(x: w * 0.67, y: h * 0.16))
                }
                .stroke(.primary.opacity(0.9), style: StrokeStyle(lineWidth: 8, lineCap: .round))

                wheel(at: CGPoint(x: w * 0.27, y: h * 0.76), size: h * 0.26)
                wheel(at: CGPoint(x: w * 0.78, y: h * 0.76), size: h * 0.26)

                if headlightOn {
                    Circle()
                        .fill(.yellow.opacity(0.9))
                        .frame(width: 8, height: 8)
                        .position(x: w * 0.585, y: h * 0.29)
                        .shadow(color: .yellow.opacity(0.8), radius: 12, x: -8, y: 0)
                }
            }
        }
    }

    private func wheel(at point: CGPoint, size: CGFloat) -> some View {
        Circle()
            .stroke(.primary.opacity(0.88), lineWidth: 10)
            .overlay(Circle().stroke(.secondary.opacity(0.35), lineWidth: 2).padding(8))
            .frame(width: size, height: size)
            .position(point)
    }
}
