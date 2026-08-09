import Foundation
import NembraBluetoothCapture
import SwiftUI

@main
@MainActor
struct NembraApp: App {
    enum LaunchMode: Equatable {
        case standard
        case es80PassiveCapture
#if DEBUG && targetEnvironment(simulator)
        case es80PassiveCaptureSimulatorQA(String)
#endif
    }

    static let captureFieldRecipeInfoPlistKey =
        PassiveBluetoothExperimentOneFieldExecutionGate.fieldRecipeInfoDictionaryKey

    private let launchMode: LaunchMode
    @State private var runtime: AppRuntime?
    @State private var researchCoordinator: PassiveBluetoothExperimentOneCoordinator?

    init() {
        let launchMode = Self.resolveLaunchMode()
        self.launchMode = launchMode
        _runtime = State(initialValue: launchMode == .standard ? AppBootstrap.makeRuntime() : nil)
        let initialResearchCoordinator: PassiveBluetoothExperimentOneCoordinator?
        switch launchMode {
        case .standard:
            initialResearchCoordinator = nil
        case .es80PassiveCapture:
            initialResearchCoordinator = try? PassiveBluetoothExperimentOneCoordinator
                .makeResearchAuthorizedES80ForCurrentApplication()
#if DEBUG && targetEnvironment(simulator)
        case .es80PassiveCaptureSimulatorQA:
            // Synthetic QA uses the inert status-only coordinator: no live CoreBluetooth controller.
            initialResearchCoordinator = try? PassiveBluetoothExperimentOneCoordinator()
#endif
        }
        _researchCoordinator = State(initialValue: initialResearchCoordinator)
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
                    if let researchCoordinator {
                        ES80ExperimentOneStationaryPreflightView(
                            coordinator: researchCoordinator
                        )
                    } else {
                        ES80ExperimentOneFieldNoGoView()
                    }
                }
                .preferredColorScheme(.dark)

#if DEBUG && targetEnvironment(simulator)
            case let .es80PassiveCaptureSimulatorQA(rawScenario):
                let scenario = PassiveBluetoothExperimentOneSimulatorQAFixture.Scenario(rawValue: rawScenario)
                    ?? .stationaryPreflight
                let snapshot = PassiveBluetoothExperimentOneSimulatorQAFixture.snapshot(for: scenario)
                NavigationStack {
                    if let researchCoordinator {
                        if scenario == .stationaryPreflight {
                            ES80ExperimentOneStationaryPreflightView(
                                coordinator: researchCoordinator,
                                simulatorQASnapshot: snapshot,
                                freshExperimentCoordinatorFactory: { try PassiveBluetoothExperimentOneCoordinator() }
                            )
                        } else {
                            ES80CaptureShellView(
                                coordinator: researchCoordinator,
                                simulatorQASnapshot: snapshot,
                                onFreshExperimentRequested: { try PassiveBluetoothExperimentOneCoordinator() }
                            )
                        }
                    } else {
                        ContentUnavailableView(
                            "Simulator QA unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text("The package-owned synthetic Capture presentation could not be created.")
                        )
                        .navigationTitle("Nembra Capture")
                        .accessibilityIdentifier("es80.capture.simulator-qa-unavailable")
                    }
                }
                .preferredColorScheme(.dark)
#endif
            }
        }
    }

    /// Routes the exact field-build recipe marker into Capture even in a Release archive.
    /// Explicit synthetic Capture QA and ordinary app Simulator requests win only in a Debug
    /// iOS Simulator build so the provenance-bound field recipe cannot steal either retained QA
    /// surface. A present-but-invalid ordinary simulation request also stays on the standard app
    /// path, preserving the simulation resolver's fail-closed contract instead of falling through
    /// to private Capture. Release/physical builds compile these overrides out and continue to
    /// route the canonical recipe to field Capture.
    static func resolveLaunchMode(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> LaunchMode {
#if DEBUG && targetEnvironment(simulator)
        if arguments.contains("--es80-passive-capture-simulator-qa") {
            let prefix = "--es80-capture-qa-scenario="
            let raw = arguments.first(where: { $0.hasPrefix(prefix) })
                .map { String($0.dropFirst(prefix.count)) }
            let scenario = raw
                .flatMap(PassiveBluetoothExperimentOneSimulatorQAFixture.Scenario.init(rawValue:))
                ?? .stationaryPreflight
            return .es80PassiveCaptureSimulatorQA(scenario.rawValue)
        }
        switch ScooterSimulationConfiguration.resolve(
            arguments: arguments,
            environment: environment
        ) {
        case .selected, .invalid:
            return .standard
        case .disabled:
            break
        }
#endif
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
/// It cannot bypass package authority because this view is reachable only after the package has
/// minted a live coordinator for the exact running research build.
@MainActor
private struct ES80ExperimentOneStationaryPreflightView: View {
    @State private var coordinator: PassiveBluetoothExperimentOneCoordinator
    @State private var selectedChargerState: PassiveBluetoothStationaryCaptureChargerState?
    @State private var disconnectedDeclarationAccepted = false
    private let simulatorQAEvidenceLabel: String?
#if DEBUG && targetEnvironment(simulator)
    private let simulatorQASnapshot: PassiveBluetoothExperimentOneSimulatorQAFixture.Snapshot?
#endif
    private let freshExperimentCoordinatorFactory: () throws -> PassiveBluetoothExperimentOneCoordinator

    init(
        coordinator: PassiveBluetoothExperimentOneCoordinator,
        simulatorQAEvidenceLabel: String? = nil,
        freshExperimentCoordinatorFactory: @escaping () throws -> PassiveBluetoothExperimentOneCoordinator = {
            try PassiveBluetoothExperimentOneCoordinator.makeResearchAuthorizedES80ForCurrentApplication()
        }
    ) {
        _coordinator = State(initialValue: coordinator)
        self.simulatorQAEvidenceLabel = simulatorQAEvidenceLabel
#if DEBUG && targetEnvironment(simulator)
        simulatorQASnapshot = nil
#endif
        self.freshExperimentCoordinatorFactory = freshExperimentCoordinatorFactory
    }

#if DEBUG && targetEnvironment(simulator)
    init(
        coordinator: PassiveBluetoothExperimentOneCoordinator,
        simulatorQASnapshot: PassiveBluetoothExperimentOneSimulatorQAFixture.Snapshot,
        freshExperimentCoordinatorFactory: @escaping () throws -> PassiveBluetoothExperimentOneCoordinator = {
            try PassiveBluetoothExperimentOneCoordinator()
        }
    ) {
        _coordinator = State(initialValue: coordinator)
        simulatorQAEvidenceLabel = simulatorQASnapshot.evidenceLabel
        self.simulatorQASnapshot = simulatorQASnapshot
        self.freshExperimentCoordinatorFactory = freshExperimentCoordinatorFactory
    }
#endif

    var body: some View {
        if disconnectedDeclarationAccepted {
#if DEBUG && targetEnvironment(simulator)
            if let simulatorQASnapshot {
                ES80CaptureShellView(
                    coordinator: coordinator,
                    simulatorQASnapshot: simulatorQASnapshot,
                    onFreshExperimentRequested: makeFreshExperimentCoordinator
                )
            } else {
                ES80CaptureShellView(
                    coordinator: coordinator,
                    onFreshExperimentRequested: makeFreshExperimentCoordinator
                )
            }
#else
            ES80CaptureShellView(
                coordinator: coordinator,
                onFreshExperimentRequested: makeFreshExperimentCoordinator
            )
#endif
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let simulatorQAEvidenceLabel {
                        Text("\(simulatorQAEvidenceLabel) · SYNTHETIC SOFTWARE STATE")
                            .font(.caption.monospaced().weight(.bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.orange.opacity(0.10), in: Capsule())
                            .accessibilityLabel("Simulator QA. Synthetic software state. Physical scooter capture remains locked.")
                            .accessibilityIdentifier("es80.capture.simulator-qa")
                    }
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

                    if let researchBuild = researchBuildForRendezvous {
                        fieldBuildRendezvous(researchBuild)
                    } else if simulatorQAEvidenceLabel == nil {
                        fieldBuildRendezvousUnavailable
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("CHARGER STATE")
                            .font(.caption.monospaced().weight(.bold))
                            .foregroundStyle(.secondary)

                        chargerStateButton(
                            title: "Disconnected",
                            detail: "Keep charger unplugged for the whole capture",
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
                                == PassiveBluetoothStationaryCaptureChargerState.disconnected.rawValue,
                              hasAcceptedPreflightAuthority else {
                            return
                        }
                        disconnectedDeclarationAccepted = true
                    } label: {
                        Label("Continue to setup confirmation", systemImage: "checkmark.shield.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 56)
                            .foregroundStyle(canContinue ? Color.black : Color.white)
                            .background(
                                canContinue ? Color.white : Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canContinue)
                    .accessibilityHint("Available only after declaring that the charger is disconnected and this running build has package-owned research authority.")
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
        let freshCoordinator = try freshExperimentCoordinatorFactory()
        coordinator = freshCoordinator
        selectedChargerState = nil
        disconnectedDeclarationAccepted = false
        return freshCoordinator
    }

    private var researchBuildForRendezvous: PassiveBluetoothExperimentOneFieldExecutionGate.ResearchBuild? {
        let status = coordinator.status
        guard status.physicalProcedurePermitted else { return nil }

        switch status.fieldExecutionStatus {
        case let .goPrivateResearchBuild(build):
            return build
        case .noGo:
            return nil
        }
    }

    private var hasAcceptedPreflightAuthority: Bool {
#if DEBUG && targetEnvironment(simulator)
        if simulatorQASnapshot != nil {
            return true
        }
#endif
        return researchBuildForRendezvous != nil
    }

    private var canContinue: Bool {
        selectedChargerState?.rawValue
            == PassiveBluetoothStationaryCaptureChargerState.disconnected.rawValue
            && hasAcceptedPreflightAuthority
    }

    private func fieldBuildRendezvous(
        _ build: PassiveBluetoothExperimentOneFieldExecutionGate.ResearchBuild
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("PRIVATE RESEARCH BUILD")
                        .font(.caption.monospaced().weight(.bold))
                        .tracking(1.0)
                        .foregroundStyle(.secondary)
                    Text("Runtime provenance ready")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Compare these running-build values with the independently inspected retained IPA before any Bluetooth scan.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider().overlay(.white.opacity(0.12))

            provenanceRow(
                title: "Recipe",
                value: PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue,
                identifier: "es80.capture.preflight.field-recipe"
            )
            provenanceRow(
                title: "Build",
                value: build.buildIdentifier,
                identifier: "es80.capture.preflight.field-build-identifier"
            )
            provenanceRow(
                title: "Source commit",
                value: build.sourceCommitSHA,
                identifier: "es80.capture.preflight.field-source-sha"
            )
            provenanceRow(
                title: "Build instance",
                value: build.buildInstanceID,
                identifier: "es80.capture.preflight.field-build-instance"
            )

            Text("Package research admission is available for this exact running build. Final GO is still required before the physical ES80 procedure; this does not verify scooter identity or protocol/telemetry semantics.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("es80.capture.preflight.field-rendezvous")
    }

    private var fieldBuildRendezvousUnavailable: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.lock.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Research build identity unavailable")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Nembra cannot prove package-owned research admission for this running build. Continue stays locked; do not begin the physical procedure.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("es80.capture.preflight.field-rendezvous-unavailable")
    }

    private func provenanceRow(
        title: String,
        value: String,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var engineeringDetailsExpanded = false
    @State private var runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity?
    @State private var runtimeBuildIdentityCheckFinished = false

    private var recipeID: String {
        PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue
    }

    private var physicalLockAccessibilityLabel: String {
        "Capture locked on this build. This exact build has not been explicitly cleared for physical scooter capture. Final exact-build checks are still in progress. No scooter action is needed yet."
    }

    private var buildIdentityAccessibilityLabel: String {
        if let runtimeBuildIdentity {
            return "Capture build, \(runtimeBuildIdentity.buildIdentifier)"
        }
        return runtimeBuildIdentityCheckFinished
            ? "Capture build identity unavailable"
            : "Capture build identity checking"
    }

    private var buildIdentityVisualLabel: String? {
        guard let runtimeBuildIdentity else { return nil }
        guard isAccessibilityLayout else { return runtimeBuildIdentity.buildIdentifier }

        let prefix = "Capture Build "
        let compact = runtimeBuildIdentity.buildIdentifier.hasPrefix(prefix)
            ? String(runtimeBuildIdentity.buildIdentifier.dropFirst(prefix.count))
            : runtimeBuildIdentity.buildIdentifier
        let components = compact.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        guard components.count == 2 else { return compact }
        return "\(components[0]) · \(components[1].prefix(8))"
    }

    private var isAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: verticalSizeClass == .compact ? 10 : (isAccessibilityLayout ? 8 : 28)
            ) {
                VStack(
                    alignment: .leading,
                    spacing: verticalSizeClass == .compact ? 6 : (isAccessibilityLayout ? 4 : 14)
                ) {
                    HStack(spacing: isAccessibilityLayout ? 0 : 12) {
                        if !isAccessibilityLayout {
                            ZStack {
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .fill(.white.opacity(0.08))
                                    .frame(
                                        width: verticalSizeClass == .compact ? 44 : 52,
                                        height: verticalSizeClass == .compact ? 44 : 52
                                    )

                                Image(systemName: "lock.shield.fill")
                                    .font(.system(
                                        size: verticalSizeClass == .compact ? 20 : 23,
                                        weight: .semibold
                                    ))
                                    .foregroundStyle(.white)
                            }
                            .accessibilityHidden(true)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            if !isAccessibilityLayout {
                                Text("NEMBRA CAPTURE")
                                    .font(.caption.monospaced().weight(.bold))
                                    .tracking(1.4)
                                    .foregroundStyle(.secondary)
                            }

                            Text("Capture locked")
                                .font(.system(
                                    isAccessibilityLayout || verticalSizeClass == .compact ? .title2 : .largeTitle,
                                    design: .rounded,
                                    weight: .semibold
                                ))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if isAccessibilityLayout {
                        Text("Final exact-build checks are still in progress.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("BUILD")
                            .font(.caption2.monospaced().weight(.bold))
                            .foregroundStyle(.secondary)

                        if let buildIdentityVisualLabel {
                            Text(buildIdentityVisualLabel)
                                .font(
                                    isAccessibilityLayout
                                        ? .caption2.monospaced().weight(.semibold)
                                        : .caption.monospaced().weight(.semibold)
                                )
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(isAccessibilityLayout ? 0.85 : 0.75)
                                .layoutPriority(1)
                        } else if runtimeBuildIdentityCheckFinished {
                            Text("Identity unavailable")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        } else {
                            Text("Checking…")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(buildIdentityAccessibilityLabel)
                    .accessibilityIdentifier("es80.capture.build-identity")

                    if !isAccessibilityLayout {
                        Text("This build is still finishing its final checks before it can collect real ES80 data.")
                            .font(
                                verticalSizeClass == .compact
                                    ? .subheadline.weight(.medium)
                                    : .title3.weight(.medium)
                            )
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(alignment: .top, spacing: isAccessibilityLayout ? 8 : 12) {
                    Image(systemName: "exclamationmark.lock.fill")
                        .font(isAccessibilityLayout ? .body.weight(.semibold) : .title3.weight(.semibold))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(isAccessibilityLayout ? "PHYSICAL CAPTURE · NO-GO" : "Not ready for scooter capture yet")
                            .font(.headline)
                            .foregroundStyle(.white)

                        if !isAccessibilityLayout {
                            Text("Nembra keeps every scooter action locked until the exact app build passes its required checks and is explicitly cleared for this physical procedure. When this screen unlocks, Capture will guide the OFF / ON sequence step by step.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(verticalSizeClass == .compact ? 12 : (isAccessibilityLayout ? 10 : 18))
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(physicalLockAccessibilityLabel)
                .accessibilityIdentifier("es80.capture.physical-run-locked")

                VStack(alignment: .leading, spacing: isAccessibilityLayout ? 0 : 14) {
                    Button {
                        engineeringDetailsExpanded.toggle()
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Engineering details")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                if !isAccessibilityLayout {
                                    Text("Recipe, build provenance, and authorization")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer(minLength: 8)

                            Image(systemName: engineeringDetailsExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
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
                            } else if runtimeBuildIdentityCheckFinished {
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
                            } else {
                                Divider().overlay(.white.opacity(0.12))

                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .accessibilityHidden(true)
                                    Text("Checking build identity…")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Checking capture build identity")
                            }

                            Text("Software evidence only. This does not verify a physical ES80 or unlock scooter controls.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(verticalSizeClass == .compact ? 12 : (isAccessibilityLayout ? 10 : 18))
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                if !isAccessibilityLayout {
                    Text("No scooter action is required yet. Capture can only unlock on a Nembra build explicitly cleared for this physical procedure; changing a setting or preference cannot bypass this lock.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 660)
            .padding(.horizontal, isAccessibilityLayout ? 16 : 22)
            .padding(.top, verticalSizeClass == .compact ? 8 : (isAccessibilityLayout ? 8 : 18))
            .padding(.bottom, verticalSizeClass == .compact ? 20 : (isAccessibilityLayout ? 12 : 42))
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("es80.capture.field-no-go-scroll")
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Nembra Capture")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("es80.capture.field-no-go")
        .task { await loadRuntimeBuildIdentity() }
    }

    private func loadRuntimeBuildIdentity() async {
        guard runtimeBuildIdentity == nil, !runtimeBuildIdentityCheckFinished else { return }

        let identity = await Task.detached(priority: .utility) {
            try? PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()
        }.value

        guard !Task.isCancelled else { return }
        runtimeBuildIdentity = identity
        runtimeBuildIdentityCheckFinished = true
    }
}
