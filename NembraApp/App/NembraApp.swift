import Foundation
import NembraBluetoothCapture
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var isFieldAuthorizationImporterPresented = false
    @State private var fieldAuthorizationRejectionMessage: String?

    init() {
        let launchMode = Self.resolveLaunchMode()
        self.launchMode = launchMode
        _runtime = State(initialValue: launchMode == .standard ? AppBootstrap.makeRuntime() : nil)
        // Research transport is deliberately not constructed at launch. The default package gate is
        // NO-GO and the only live-controller initializer requires a verified exact-build authority.
        _researchCoordinator = State(initialValue: nil)
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
                    if let researchCoordinator,
                       researchCoordinator.status.physicalProcedurePermitted {
                        ES80ExperimentOneStationaryPreflightView(
                            coordinator: researchCoordinator
                        )
                    } else {
                        ES80ExperimentOneFieldNoGoView(
                            authorizationRejectionMessage: fieldAuthorizationRejectionMessage,
                            loadFieldAuthorization: {
                                isFieldAuthorizationImporterPresented = true
                            }
                        )
                    }
                }
                .preferredColorScheme(.dark)
                .fileImporter(
                    isPresented: $isFieldAuthorizationImporterPresented,
                    allowedContentTypes: [.json]
                ) { result in
                    handleFieldAuthorizationImport(result)
                }
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

    /// Imports one externally issued authorization envelope. Reading a file does not itself unlock
    /// anything: the package verifier must validate the trusted signature, exact external-record
    /// bytes, running executable/build identity, and exact runtime Info.plist before the package can
    /// mint the non-forgeable value required by the live coordinator initializer.
    private func handleFieldAuthorizationImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let envelopeData = try Data(contentsOf: url, options: .mappedIfSafe)
            let authorization = try PassiveBluetoothCaptureFieldAuthorizationVerifier
                .verifyForCurrentApplication(envelopeData)
            let coordinator = try PassiveBluetoothExperimentOneCoordinator(
                fieldAuthorization: authorization
            )
            guard coordinator.status.physicalProcedurePermitted else {
                throw FieldAuthorizationImportError.verifiedAuthorizationDidNotPermitProcedure
            }

            researchCoordinator = coordinator
            fieldAuthorizationRejectionMessage = nil
        } catch {
            // A failed/rejected import cannot preserve or create live transport. Keep the product on
            // the same physical NO-GO surface and present one concise corrective explanation.
            researchCoordinator = nil
            fieldAuthorizationRejectionMessage = Self.fieldAuthorizationMessage(for: error)
        }
    }

    private static func fieldAuthorizationMessage(for error: Error) -> String {
        if let fieldError = error as? PassiveBluetoothCaptureFieldAuthorizationError {
            switch fieldError {
            case .missingAuthorizationPublicKey, .invalidAuthorizationPublicKey:
                return "This app was not produced with the accepted field-authorization key. Use the exact approved field build."
            case .runtimeBuildMismatch, .runtimeInfoPlistMismatch:
                return "That authorization belongs to a different app build. Use the authorization issued for this exact build."
            default:
                return "That field authorization could not be verified. Use the exact signed authorization issued with the approved build."
            }
        }

        return "That field authorization could not be opened or verified. Use the exact signed authorization issued with the approved build."
    }

    private enum FieldAuthorizationImportError: Error {
        case verifiedAuthorizationDidNotPermitProcedure
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
/// It cannot bypass package-owned field authority because this view is reachable only from a
/// coordinator that retained a verified exact-build authorization.
@MainActor
private struct ES80ExperimentOneStationaryPreflightView: View {
    let coordinator: PassiveBluetoothExperimentOneCoordinator

    @State private var selectedChargerState: PassiveBluetoothStationaryCaptureChargerState?
    @State private var disconnectedDeclarationAccepted = false

    var body: some View {
        if disconnectedDeclarationAccepted {
            ES80CaptureShellView(coordinator: coordinator)
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
    let authorizationRejectionMessage: String?
    let loadFieldAuthorization: () -> Void

    private var recipeID: String {
        PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue
    }

    private var physicalLockAccessibilityLabel: String {
        "Capture locked on this build. Real scooter capture remains unavailable until this exact app build verifies its signed Nembra field authorization."
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

                    Text("Real scooter capture stays locked until this exact app build proves its field authorization.")
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
                        Text("Scooter actions remain locked")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text("Loading a file cannot bypass Nembra's safety gate. Capture unlocks only after the package verifies the signed authorization against this exact running build.")
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
                        Text("Signed field authorization required")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(18)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text("FIELD BUILD")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.secondary)

                    Text("Have the authorization issued with the approved build?")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("Nembra verifies it locally before creating any Bluetooth capture transport.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: loadFieldAuthorization) {
                        Label("Load field authorization", systemImage: "checkmark.shield")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 52)
                            .foregroundStyle(.black)
                            .background(
                                Color.white,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Select the signed authorization issued for this exact approved Nembra build.")
                    .accessibilityIdentifier("es80.capture.load-field-authorization")

                    if let authorizationRejectionMessage {
                        Text(authorizationRejectionMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("es80.capture.field-authorization-rejected")
                    }
                }
                .padding(18)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                Text("Until verification succeeds, OFF / ON steps, scanning, connection, observation, and Share remain unreachable.")
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
