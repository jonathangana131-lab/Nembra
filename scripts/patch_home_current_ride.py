#!/usr/bin/env python3
from pathlib import Path

path = Path("NembraApp/Features/Home/HomeView.swift")
text = path.read_text()

env_anchor = "    @Environment(VehicleStore.self) private var vehicle\n"
env_replacement = (
    "    @Environment(VehicleStore.self) private var vehicle\n"
    "    @Environment(RideStore.self) private var ride\n"
)
if "@Environment(RideStore.self) private var ride" not in text:
    if text.count(env_anchor) != 1:
        raise SystemExit("VehicleStore environment anchor is not unique")
    text = text.replace(env_anchor, env_replacement, 1)

body_anchor = """                vehicleHeader

                if vehicle.state.connection != .connected {
"""
body_replacement = """                vehicleHeader

                if ride.presentation.isVisibleOnHome {
                    currentRideStatus
                }

                if vehicle.state.connection != .connected {
"""
if "if ride.presentation.isVisibleOnHome" not in text:
    if text.count(body_anchor) != 1:
        raise SystemExit("Home body anchor is not unique")
    text = text.replace(body_anchor, body_replacement, 1)

status_anchor = "    private var statusPanel: some View {\n"
ride_block = """    private struct CurrentRidePresentation {
        let title: String
        let message: String
        let icon: String
    }

    private var currentRidePresentation: CurrentRidePresentation {
        switch ride.presentation {
        case .active:
            CurrentRidePresentation(
                title: "Ride active",
                message: "Tracking automatically",
                icon: "location.fill"
            )
        case .reconnecting:
            CurrentRidePresentation(
                title: "Ride continuing",
                message: "Reconnecting to scooter",
                icon: "antenna.radiowaves.left.and.right"
            )
        case .finishing:
            CurrentRidePresentation(
                title: "Checking ride end",
                message: "Waiting for confirmed stop",
                icon: "hourglass"
            )
        case .saving:
            CurrentRidePresentation(
                title: "Saving ride",
                message: "Securing ride history",
                icon: "arrow.down.doc.fill"
            )
        case .blocked:
            CurrentRidePresentation(
                title: "Ride tracking paused",
                message: "Ride data is preserved",
                icon: "exclamationmark.shield.fill"
            )
        case .unavailable, .idle:
            CurrentRidePresentation(
                title: "Ride tracking",
                message: "Waiting for movement",
                icon: "circle"
            )
        }
    }

    private var currentRideStatus: some View {
        let presentation = currentRidePresentation

        return HStack(spacing: 12) {
            Image(systemName: presentation.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(.subheadline.weight(.semibold))
                Text(presentation.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if ride.presentation == .saving {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.currentRide")
    }

"""
if "private struct CurrentRidePresentation" not in text:
    if text.count(status_anchor) != 1:
        raise SystemExit("statusPanel anchor is not unique")
    text = text.replace(status_anchor, ride_block + status_anchor, 1)

required = [
    "@Environment(RideStore.self) private var ride",
    "if ride.presentation.isVisibleOnHome",
    'accessibilityIdentifier("home.currentRide")',
    'title: "Ride active"',
    'message: "Tracking automatically"',
]
if not all(marker in text for marker in required):
    raise SystemExit("Current ride Home patch did not complete")

path.write_text(text)
