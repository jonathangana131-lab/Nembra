import Foundation
import NembraBluetoothCapture
import SwiftUI

@main
@MainActor
struct NembraApp: App {
    enum LaunchMode: Equatable {
        case standard
        case es80PassiveCapture
    }

    static let captureFieldRecipeInfoPlistKey = "NembraCaptureFieldRecipe"

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
                                description: Text("The Experiment One capture workflow could not be created.")
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

    /// Routes the exact field-build recipe marker into Capture even in a Release archive.
    ///
    /// This Info.plist value is build-pipeline constructible and is therefore launch routing only,
    /// never physical authority. The package-owned Experiment One field gate remains the mechanical
    /// authority boundary for every procedure-advancing action.
    static func resolveLaunchMode(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> LaunchMode {
        if let fieldRecipe = infoDictionary[captureFieldRecipeInfoPlistKey] as? String,
           fieldRecipe == PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue {
            return .es80PassiveCapture
        }
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

                        Text("Confirm the charger state before OFF 1 becomes available.")
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
                            detail: "Unplug charger to continue",
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

                                Text("This capture requires the scooter to be unplugged. Unplug the charger, then select Disconnected.")
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

                    Text("Nembra cannot sense the charger directly. Keep it disconnected, keep Nembra open with the screen unlocked, and keep the stock scooter app closed for the whole capture.")
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
    @State private var engineeringDetailsExpanded = false
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

    private var buildIdentityAccessibilityLabel: String {
        if let runtimeBuildIdentity {
            return "Capture build, \(runtimeBuildIdentity.buildIdentifier)"
        }
        return "Capture build identity unavailable"
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

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("BUILD")
                            .font(.caption2.monospaced().weight(.bold))
                            .foregroundStyle(.secondary)

                        if let runtimeBuildIdentity {
                            Text(runtimeBuildIdentity.buildIdentifier)
                                .font(.caption.monospaced().weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        } else {
                            Text("Identity unavailable")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(buildIdentityAccessibilityLabel)
                    .accessibilityIdentifier("es80.capture.build-identity")
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

                VStack(alignment: .leading, spacing: 14) {
                    Button {
                        engineeringDetailsExpanded.toggle()
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Engineering details")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text("Recipe, build provenance, and authorization")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            Image(systemName: engineeringDetailsExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(engineeringDetailsExpanded ? "Expanded" : "Collapsed")
                    .accessibilityHint("Shows the exact software recipe, build provenance, and authorization state. It does not unlock scooter capture.")
                    .accessibilityIdentifier("es80.capture.engineering-details")

                    if engineeringDetailsExpanded {
                        Divider().overlay(.white.opacity(0.12))

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Recipe")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 12)
                                Text(recipeID)
                                    .font(.subheadline.monospaced().weight(.semibold))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.trailing)
                                    .accessibilityIdentifier("es80.capture.recipe-id")
                            }

                            HStack(alignment: .firstTextBaseline) {
                                Text("Physical authorization")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 12)
                                Text("NO-GO")
                                    .font(.subheadline.monospaced().weight(.bold))
                                    .foregroundStyle(.orange)
                            }

                            if let runtimeBuildIdentity {
                                Divider().overlay(.white.opacity(0.12))

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("SOURCE COMMIT")
                                        .font(.caption2.monospaced().weight(.bold))
                                        .foregroundStyle(.secondary)
                                    Text(runtimeBuildIdentity.sourceCommitSHA)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.white)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("es80.capture.build-source-sha")

                                    Text("BUILD INSTANCE")
                                        .font(.caption2.monospaced().weight(.bold))
                                        .foregroundStyle(.secondary)
                                    Text(runtimeBuildIdentity.buildInstanceID)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.white)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("es80.capture.build-instance-id")
                                }
                            } else {
                                Divider().overlay(.white.opacity(0.12))

                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Build identity unavailable")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.orange)
                                    Text("Nembra could not verify this running build's embedded identity. Capture stays locked and no exact source or build-instance claim is shown.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Text("Software evidence only. This does not verify a physical ES80 or unlock scooter controls.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
