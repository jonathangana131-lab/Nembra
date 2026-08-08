import Foundation
import NembraBluetoothCapture
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
    @State private var researchCoordinator: PassiveBluetoothExperimentOneCoordinator?

    init() {
        let launchMode = Self.resolveLaunchMode()
        self.launchMode = launchMode
        _runtime = State(initialValue: launchMode == .standard ? AppBootstrap.makeRuntime() : nil)
        _researchCoordinator = State(
            initialValue: launchMode == .es80PassiveCapture
                ? try? PassiveBluetoothExperimentOneCoordinator()
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
                    if PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure {
                        if let researchCoordinator {
                            ES80ExperimentOneStationaryPreflightView(
                                coordinator: researchCoordinator
                            )
                        } else {
                            ContentUnavailableView(
                                "Capture unavailable",
                                systemImage: "antenna.radiowaves.left.and.right.slash",
                                description: Text("The package-owned Experiment One workflow could not be created.")
                            )
                            .navigationTitle("Nembra Capture")
                            .accessibilityIdentifier("es80.research-capture-unavailable")
                        }
                    } else {
                        ES80ExperimentOneFieldNoGoView()
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
}

/// Product-level prerequisite between accepted package field authority and the Experiment One shell.
///
/// The physical recipe requires the charger disconnected. The app therefore cannot turn a generic
/// confirmation tap into `.disconnected` setup provenance: the operator first declares the actual
/// charger state here. A connected declaration is a hard blocker. Only an explicit disconnected
/// declaration can instantiate the shell, where the existing final setup confirmation records the
/// same condition into the package-owned stationary setup object.
///
/// This remains an operator declaration, not electrical sensing or continuous-condition attestation.
/// It cannot bypass the package-owned physical execution gate because this view is reachable only
/// after `PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure` is already true.
@MainActor
private struct ES80ExperimentOneStationaryPreflightView: View {
    @State private var coordinator: PassiveBluetoothExperimentOneCoordinator
    @State private var selectedChargerState: PassiveBluetoothStationaryCaptureChargerState?
    @State private var disconnectedDeclarationAccepted = false

    init(coordinator: PassiveBluetoothExperimentOneCoordinator) {
        _coordinator = State(initialValue: coordinator)
    }

    var body: some View {
        if disconnectedDeclarationAccepted {
            ES80CaptureShellView(
                coordinator: coordinator,
                onFreshExperimentRequested: makeFreshExperimentCoordinator
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NEMBRA CAPTURE")
                            .font(.caption.monospaced().weight(.bold))
                            .tracking(1.4)
                            .foregroundStyle(.secondary)

                        Text("Stationary preflight")
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)

                        Text("Declare the scooter charger state before Experiment One can expose OFF 1.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("CHARGER STATE")
                            .font(.caption.monospaced().weight(.bold))
                            .foregroundStyle(.secondary)

                        chargerStateButton(
                            title: "Disconnected",
                            detail: "Required for ES80-FINGERPRINT-v1",
                            systemImage: "bolt.slash.fill",
                            state: .disconnected
                        )

                        chargerStateButton(
                            title: "Connected",
                            detail: "Experiment One remains blocked",
                            systemImage: "bolt.fill",
                            state: .connected
                        )
                    }

                    if selectedChargerState?.rawValue == PassiveBluetoothStationaryCaptureChargerState.connected.rawValue {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.lock.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Disconnect charger to continue")
                                    .font(.headline)
                                    .foregroundStyle(.white)

                                Text("The accepted stationary fingerprint recipe requires the scooter charger disconnected. Nembra will not convert a connected declaration into disconnected provenance. Unplug the charger, then select Disconnected.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(18)
                        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("es80.capture.preflight.charger-blocked")
                    }

                    Button {
                        guard selectedChargerState?.rawValue
                                == PassiveBluetoothStationaryCaptureChargerState.disconnected.rawValue else {
                            return
                        }
                        disconnectedDeclarationAccepted = true
                    } label: {
                        Label("Continue to setup confirmation", systemImage: "checkmark.shield.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 56)
                            .foregroundStyle(canContinue ? Color.black : Color.secondary)
                            .background(
                                canContinue ? Color.white : Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canContinue)
                    .accessibilityHint("Available only after declaring that the charger is disconnected.")
                    .accessibilityIdentifier("es80.capture.preflight.continue")

                    Text("This is an operator declaration, not charger sensing or proof that the condition remains unchanged. Keep the charger disconnected, Nembra foregrounded with the screen unlocked, and the stock scooter app closed through the run.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 660)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 42)
                .frame(maxWidth: .infinity)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Nembra Capture")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("es80.capture.stationary-preflight")
        }
    }

    /// A new Experiment One is a new declared setup life. A restart may mint a fresh
    /// package-owned coordinator, but it must also return through charger preflight instead of
    /// carrying the previous run's disconnected declaration into new evidence.
    private func makeFreshExperimentCoordinator() throws -> PassiveBluetoothExperimentOneCoordinator {
        let freshCoordinator = try PassiveBluetoothExperimentOneCoordinator()
        coordinator = freshCoordinator
        selectedChargerState = nil
        disconnectedDeclarationAccepted = false
        return freshCoordinator
    }

    private var canContinue: Bool {
        selectedChargerState?.rawValue
            == PassiveBluetoothStationaryCaptureChargerState.disconnected.rawValue
    }

    private func chargerStateButton(
        title: String,
        detail: String,
        systemImage: String,
        state: PassiveBluetoothStationaryCaptureChargerState
    ) -> some View {
        let selected = selectedChargerState?.rawValue == state.rawValue

        return Button {
            selectedChargerState = state
        } label: {
            HStack(spacing: 14) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(selected ? Color.black : Color.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(selected ? Color.black.opacity(0.7) : Color.secondary)
                }

                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .foregroundStyle(selected ? Color.black : Color.white)
            .background(
                selected ? Color.white : Color.white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Charger \(title)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityIdentifier("es80.capture.preflight.charger-\(state.rawValue)")
    }
}

@MainActor
private struct ES80ExperimentOneFieldNoGoView: View {
    private let runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity?

    init() {
        runtimeBuildIdentity = try? PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()
    }

    private var recipeID: String {
        PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue
    }

    private var physicalLockAccessibilityLabel: String {
        "Capture locked on this build. Nembra is still completing the final app and build checks required before the scooter capture can begin. No scooter action is needed yet."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(.white.opacity(0.08))
                                .frame(width: 52, height: 52)

                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 23, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("NEMBRA CAPTURE")
                                .font(.caption.monospaced().weight(.bold))
                                .tracking(1.4)
                                .foregroundStyle(.secondary)

                            Text("Capture locked")
                                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }

                    Text("This build is still finishing its final checks before it can collect real ES80 data.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.lock.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Not ready for scooter capture yet")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text("Nembra keeps every scooter action locked until the exact app build has passed its required checks. When this screen unlocks, Capture will guide the OFF / ON sequence step by step.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(physicalLockAccessibilityLabel)
                .accessibilityIdentifier("es80.capture.physical-run-locked")

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("CAPTURE RECIPE")
                            .font(.caption.monospaced().weight(.bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("LOCKED")
                            .font(.caption.monospaced().weight(.bold))
                            .foregroundStyle(.orange)
                    }

                    Text(recipeID)
                        .font(.title3.monospaced().weight(.semibold))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("es80.capture.recipe-id")

                    Divider().overlay(.white.opacity(0.12))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("BUILD")
                            .font(.caption.monospaced().weight(.bold))
                            .foregroundStyle(.secondary)

                        if let runtimeBuildIdentity {
                            Text(runtimeBuildIdentity.buildIdentifier)
                                .font(.headline.monospaced().weight(.semibold))
                                .foregroundStyle(.white)
                            Text("Source \(runtimeBuildIdentity.sourceCommitSHA)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Text("Build instance \(runtimeBuildIdentity.buildInstanceID)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        } else {
                            Text("Build identity unavailable")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text("Nembra could not verify this running build's embedded identity. Scooter capture remains locked until exact build identity is available.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("es80.capture.build-identity")

                    Divider().overlay(.white.opacity(0.12))

                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("Capture workflow installed")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text("Scooter capture unavailable on this build")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(18)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                Text("No scooter action is required yet. Capture can only unlock from an accepted Nembra build; changing a setting or preference cannot bypass this lock.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 660)
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 42)
            .frame(maxWidth: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Nembra Capture")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("es80.capture.field-no-go")
    }
}