import Foundation
import NembraBluetoothCapture
import NembraCore
import SwiftUI

private enum ES80ResearchBuildPreflightState: Equatable {
    case notApplicable
    case matched(PassiveBluetoothCaptureRuntimeBuildBinding)
    case blocked(String)

    var permitsFieldRuntime: Bool {
        if case .matched = self { return true }
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
    private let researchBuildPreflight: ES80ResearchBuildPreflightState
    @State private var runtime: AppRuntime?
    @State private var researchController: ForegroundCoreBluetoothCaptureController?

    init() {
        let launchMode = Self.resolveLaunchMode()
        self.launchMode = launchMode
        _runtime = State(initialValue: launchMode == .standard ? AppBootstrap.makeRuntime() : nil)

        let researchBuildPreflight: ES80ResearchBuildPreflightState = launchMode == .es80PassiveCapture
            ? Self.resolveES80ResearchBuildPreflight()
            : .notApplicable
        self.researchBuildPreflight = researchBuildPreflight

        let fieldCaptureAuthorized = launchMode == .es80PassiveCapture
            && PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure
            && researchBuildPreflight.permitsFieldRuntime
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
                    if PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure,
                       researchBuildPreflight.permitsFieldRuntime {
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
                        ES80ExperimentOneFieldNoGoView(buildPreflight: researchBuildPreflight)
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

    private static func resolveES80ResearchBuildPreflight() -> ES80ResearchBuildPreflightState {
        do {
            return .matched(try PassiveBluetoothCaptureBuildPreflight.currentApplication())
        } catch let error as PassiveBluetoothCaptureRuntimeBuildIdentityError {
            switch error {
            case .missingBuildIdentifier, .missingSourceCommitSHA:
                return .blocked("Required field-build metadata is missing from this app. The accepted build pipeline must inject the Nembra build identifier and exact source commit automatically.")
            default:
                return .blocked("The running app's build metadata or executable cannot satisfy the trusted V14 field-build preflight.")
            }
        } catch let error as PassiveBluetoothCaptureTrustedBuildRecordError {
            switch error {
            case .missingTrustedBuildRecord:
                return .blocked("The trusted V14 field-build record is missing from this app. A field build must carry the acceptance-pipeline record for its exact executable bytes.")
            default:
                return .blocked("The bundled trusted field-build record is malformed or outside the accepted V14 recipe/procedure contract.")
            }
        } catch is PassiveBluetoothCaptureBuildPreflightError {
            return .blocked("The running executable does not match the trusted V14 field-build record. Nembra will not create a field capture controller for mismatched bytes or provenance.")
        } catch {
            return .blocked("Trusted field-build provenance could not be established for the running app.")
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
private struct ES80ExperimentOneFieldNoGoView: View {
    let buildPreflight: ES80ResearchBuildPreflightState

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

                buildPreflightPanel

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

                Text("No physical action is required. A future accepted build must unlock this mechanically from package-owned authorization and matching trusted build provenance; a UI flag, local preference, typed SHA, or matching label cannot do it.")
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
    private var buildPreflightPanel: some View {
        switch buildPreflight {
        case let .matched(binding):
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("BUILD PREFLIGHT")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("MATCHED")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.white)
                }

                Text(binding.buildIdentifier)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Commit \(String(binding.sourceCommitSHA.prefix(12))) · \(binding.procedureVersion)")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("The running executable digest, build declaration, recipe, and procedure match the trusted acceptance-pipeline record. This is software provenance only; it does not authorize the physical scooter procedure.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("es80.capture.build-preflight")

        case let .blocked(message):
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shield.slash.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Text("BUILD PREFLIGHT / BLOCKED")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.secondary)

                    Text("Field build identity not accepted")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("No field capture controller is created while this preflight is blocked.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("es80.capture.build-preflight")

        case .notApplicable:
            EmptyView()
        }
    }
}