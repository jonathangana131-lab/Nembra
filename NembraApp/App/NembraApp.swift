import Foundation
import NembraBluetoothCapture
import NembraCore
import SwiftUI

@main
@MainActor
struct NembraApp: App {
    private enum LaunchMode: Equatable {
        case standard
        case es80PassiveCapture
    }

    private let launchMode: LaunchMode
    @State private var runtime: AppRuntime?
    @State private var researchController: ForegroundCoreBluetoothCaptureController?

    init() {
        let launchMode = Self.resolveLaunchMode()
        self.launchMode = launchMode
        _runtime = State(initialValue: launchMode == .standard ? AppBootstrap.makeRuntime() : nil)
        _researchController = State(
            initialValue: launchMode == .es80PassiveCapture
                ? Self.makeES80ResearchController()
                : nil
        )
    }

    var body: some Scene {
        WindowGroup {
            switch launchMode {
            case .standard:
                if let runtime {
                    AppRootView()
                        .environment(runtime.vehicleStore)
                        .environment(runtime.rideStore)
                        .environment(runtime.rideHistoryStore)
                        .environment(runtime.rideRouteStore)
                        .task { await runtime.start() }
                } else {
                    ContentUnavailableView(
                        "Nembra unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The application runtime could not be created.")
                    )
                }

            case .es80PassiveCapture:
                NavigationStack {
                    if let researchController {
                        ES80CaptureShellView(controller: researchController)
                    } else {
                        ContentUnavailableView(
                            "Capture unavailable",
                            systemImage: "antenna.radiowaves.left.and.right.slash",
                            description: Text("The passive Bluetooth research controller could not be created.")
                        )
                        .navigationTitle("Nembra Capture")
                        .accessibilityIdentifier("es80.research-capture-unavailable")
                    }
                }
                .preferredColorScheme(.dark)
            }
        }
    }

    private static func resolveLaunchMode(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LaunchMode {
#if DEBUG
        if arguments.contains("--es80-passive-capture")
            || environment["NEMBRA_ES80_PASSIVE_CAPTURE"] == "1" {
            return .es80PassiveCapture
        }
#endif
        return .standard
    }

    private static func makeES80ResearchController() -> ForegroundCoreBluetoothCaptureController? {
        try? ForegroundCoreBluetoothCaptureController(
            vehicleIdentity: NembraCore.VehicleIdentity(
                manufacturer: "AOVOPRO",
                model: "ES80",
                displayName: "AOVOPRO ES80 research target",
                protocolFamily: "unverified-passive-research"
            )
        )
    }
}
