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

        let fieldCaptureAuthorized = launchMode == .es80PassiveCapture
            && PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure
        _researchController = State(
            initialValue: fieldCaptureAuthorized
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
                    if PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure {
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

    private static func makeES80ResearchController() -> ForegroundCoreBluetoothCaptureController? {
        // This is the declared software context required by the ES80 Experiment One authority.
        // It is metadata consistency only and must never be presented as physical authentication.
        try? ForegroundCoreBluetoothCaptureController(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
    }
}

@MainActor
private struct ES80ExperimentOneFieldNoGoView: View {
    private enum RuntimeBuildIdentityState: Equatable {
        case loading
        case available(PassiveBluetoothCaptureRuntimeBuildIdentity)
        case unavailable(String)
    }

    @State private var showsBuildDetails = false
    @State private var runtimeBuildIdentityState: RuntimeBuildIdentityState = .loading

    private var recipeID: String {
        PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue
    }

    private var physicalLockAccessibilityLabel: String {
        "Physical Experiment One locked. Nembra will not expose the OFF and ON field controls until the final composed app, lifecycle authority, provenance, runtime, visual, accessibility, performance, and runbook gates have all earned a deliberate GO authorization."
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

                            Text("Field capture locked")
                                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }

                    Text("This exact build is not authorized to begin the physical ES80 procedure.")
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
                        Text("Physical Experiment One locked")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text("Nembra will not expose the OFF/ON field controls until the final composed app, lifecycle authority, provenance, runtime, visual, accessibility, performance, and runbook gates have all earned a deliberate GO authorization.")
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
                        Text("PROCEDURE")
                            .font(.caption.monospaced().weight(.bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("NO-GO")
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
                        Text("Correlation workflow installed")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text("Field execution unavailable on this build")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(18)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                buildDetails

                Text("No physical action is required. A future accepted build must unlock this mechanically from package-owned authorization; a UI flag or local preference cannot do it.")
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

    private var buildDetails: some View {
        DisclosureGroup(isExpanded: $showsBuildDetails) {
            VStack(alignment: .leading, spacing: 14) {
                Divider().overlay(.white.opacity(0.12))

                switch runtimeBuildIdentityState {
                case .loading:
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                            .accessibilityHidden(true)
                        Text("Checking the running build…")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("es80.capture.build-provenance-loading")

                case let .available(identity):
                    buildProvenanceStatus(
                        symbol: "info.circle",
                        title: "Runtime build evidence available",
                        message: "Nembra hashed the exact executable bytes currently running. The embedded build label and source commit remain declarations until an independently trusted build record matches this executable digest. This does not authorize the physical procedure."
                    )
                    buildDetailRow("BUILD", value: identity.buildIdentifier)
                    buildDetailRow("SOURCE DECLARATION", value: identity.sourceCommitSHA)
                    buildDetailRow("EXECUTABLE SHA-256", value: identity.executableSHA256)

                case let .unavailable(reason):
                    buildProvenanceStatus(
                        symbol: "exclamationmark.triangle",
                        title: "Runtime provenance unavailable",
                        message: "\(reason) This is a preflight blocker, so physical execution remains locked."
                    )
                }

                buildDetailRow("PROCEDURE", value: recipeID)

                Text("Build metadata is evidence about this app build only. It is not scooter identity, GATT/Tuya truth, telemetry truth, or physical authorization.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("VIEW DETAILS")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                Text("BUILD EVIDENCE")
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .tint(.white)
        .padding(18)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("es80.capture.view-details")
        .task(id: showsBuildDetails) {
            guard showsBuildDetails, runtimeBuildIdentityState == .loading else { return }
            runtimeBuildIdentityState = await Self.readRuntimeBuildIdentity()
        }
    }

    private func buildProvenanceStatus(
        symbol: String,
        title: String,
        message: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("es80.capture.build-provenance-status")
    }

    private func buildDetailRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.monospaced())
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func readRuntimeBuildIdentity() async -> RuntimeBuildIdentityState {
        await Task.detached(priority: .utility) {
            do {
                return RuntimeBuildIdentityState.available(
                    try PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()
                )
            } catch let error as PassiveBluetoothCaptureRuntimeBuildIdentityError {
                return RuntimeBuildIdentityState.unavailable(
                    runtimeBuildIdentityFailureMessage(for: error)
                )
            } catch {
                return RuntimeBuildIdentityState.unavailable(
                    "Nembra could not verify the running build identity."
                )
            }
        }.value
    }

    nonisolated private static func runtimeBuildIdentityFailureMessage(
        for error: PassiveBluetoothCaptureRuntimeBuildIdentityError
    ) -> String {
        switch error {
        case .missingBuildIdentifier:
            "The running app has no embedded Nembra capture build identifier."
        case .invalidBuildIdentifier:
            "The embedded Nembra capture build identifier is malformed."
        case .missingSourceCommitSHA:
            "The running app has no embedded exact source commit declaration."
        case .invalidSourceCommitSHA:
            "The embedded source commit declaration is not a full 40-character Git SHA."
        case .executableUnavailable:
            "The running app executable cannot be located."
        case .executableNotRegularFile:
            "The running app executable is not a regular file."
        case .executableUnreadable:
            "The running app executable cannot be read for hashing."
        }
    }
}
