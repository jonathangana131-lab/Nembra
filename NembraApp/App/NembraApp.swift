import Foundation
import NembraBluetoothCapture
import NembraCore
import SwiftUI

private enum ES80CaptureBuildPreflight: Equatable {
    case ready(PassiveBluetoothCaptureRuntimeBuildIdentity)
    case blocked(String)

    var permitsRuntimeCapture: Bool {
        if case .ready = self {
            return true
        }
        return false
    }
}

@main
@MainActor
struct NembraApp: App {
    private enum LaunchMode: Equatable {
        case standard
        case es80PassiveCapture
    }

    private let launchMode: LaunchMode
    private let researchBuildPreflight: ES80CaptureBuildPreflight?
    @State private var runtime: AppRuntime?
    @State private var researchController: ForegroundCoreBluetoothCaptureController?

    init() {
        let launchMode = Self.resolveLaunchMode()
        self.launchMode = launchMode
        _runtime = State(initialValue: launchMode == .standard ? AppBootstrap.makeRuntime() : nil)

        let buildPreflight = launchMode == .es80PassiveCapture
            ? Self.resolveES80CaptureBuildPreflight()
            : nil
        researchBuildPreflight = buildPreflight

        let fieldCaptureAuthorized = launchMode == .es80PassiveCapture
            && PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure
            && buildPreflight?.permitsRuntimeCapture == true
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
                    es80ResearchRoot
                }
                .preferredColorScheme(.dark)
            }
        }
    }

    @ViewBuilder
    private var es80ResearchRoot: some View {
        let buildPreflight = researchBuildPreflight
            ?? .blocked("Capture build identity was not evaluated for this launch.")

        if PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure {
            switch buildPreflight {
            case .ready:
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

            case let .blocked(message):
                ES80CaptureBuildIdentityNoGoView(message: message)
            }
        } else {
            ES80ExperimentOneFieldNoGoView(buildPreflight: buildPreflight)
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

    private static func resolveES80CaptureBuildPreflight() -> ES80CaptureBuildPreflight {
        do {
            return .ready(try PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication())
        } catch let error as PassiveBluetoothCaptureRuntimeBuildIdentityError {
            return .blocked(buildIdentityFailureMessage(for: error))
        } catch {
            return .blocked("Nembra could not establish the runtime build identity for this Capture build.")
        }
    }

    private static func buildIdentityFailureMessage(
        for error: PassiveBluetoothCaptureRuntimeBuildIdentityError
    ) -> String {
        switch error {
        case .missingBuildIdentifier:
            return "This build is missing the required Nembra Capture build identifier."
        case .invalidBuildIdentifier:
            return "The embedded Nembra Capture build identifier is malformed."
        case .missingSourceCommitSHA:
            return "This build is missing its exact source commit declaration."
        case .invalidSourceCommitSHA:
            return "The embedded source commit declaration is not a full 40-character Git SHA."
        case .executableUnavailable:
            return "Nembra cannot locate the executable bytes required for runtime provenance."
        case .executableNotRegularFile:
            return "The running executable is not a regular file, so Capture provenance cannot be established."
        case .executableUnreadable:
            return "Nembra cannot read the running executable bytes required for the Capture fingerprint."
        }
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
private struct ES80CaptureBuildIdentityNoGoView: View {
    let message: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("NEMBRA CAPTURE")
                    .font(.caption.monospaced().weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)

                Text("Build identity required")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Capture preflight blocked")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                Text("No field controls are available. Rebuild through the accepted exact-head Capture build path so the build declaration and runtime executable fingerprint are produced automatically.")
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
        .accessibilityIdentifier("es80.capture.build-provenance-blocked")
    }
}

@MainActor
private struct ES80ExperimentOneFieldNoGoView: View {
    let buildPreflight: ES80CaptureBuildPreflight

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

                buildProvenance

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

    @ViewBuilder
    private var buildProvenance: some View {
        switch buildPreflight {
        case let .ready(identity):
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("BUILD PROVENANCE")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label("READY", systemImage: "checkmark.seal.fill")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.green)
                }

                Text(identity.buildIdentifier)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("es80.capture.build-identifier")

                provenanceRow(
                    label: "DECLARED SOURCE",
                    value: String(identity.sourceCommitSHA.prefix(12))
                )
                provenanceRow(
                    label: "RUNTIME BYTES",
                    value: "\(String(identity.executableSHA256.prefix(12)))…"
                )

                Text("The build label and source SHA are declarations injected by the build path. The runtime SHA-256 is byte evidence for the executable actually running. Final GO still requires the accepted trusted build record to bind those facts; this card does not claim cryptographic source attestation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("es80.capture.build-provenance-ready")

        case let .blocked(message):
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.lock.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Build provenance blocked")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("es80.capture.build-provenance-blocked")
        }
    }

    private func provenanceRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
