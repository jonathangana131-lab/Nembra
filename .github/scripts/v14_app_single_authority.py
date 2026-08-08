from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, got {count}")
    return text.replace(old, new, 1)


app_path = Path("NembraApp/App/NembraApp.swift")
app = app_path.read_text()
app = replace_once(
    app,
    "@State private var researchController: ForegroundCoreBluetoothCaptureController?",
    "@State private var researchCoordinator: PassiveBluetoothExperimentOneCoordinator?",
    "app state",
)
app = replace_once(
    app,
    """        _researchController = State(
            initialValue: fieldCaptureAuthorized
                ? Self.makeES80ResearchController()
                : nil
        )""",
    """        _researchCoordinator = State(
            initialValue: fieldCaptureAuthorized
                ? Self.makeES80ResearchCoordinator()
                : nil
        )""",
    "app initialization",
)
app = replace_once(
    app,
    """                        if let researchController {
                            ES80CaptureShellView(controller: researchController)""",
    """                        if let researchCoordinator {
                            ES80CaptureShellView(coordinator: researchCoordinator)""",
    "app shell handoff",
)
app = replace_once(
    app,
    """    private static func makeES80ResearchController() -> ForegroundCoreBluetoothCaptureController? {
        // This is the declared software context required by the ES80 Experiment One authority.
        // It is metadata consistency only and must never be presented as physical authentication.
        try? ForegroundCoreBluetoothCaptureController(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
    }""",
    """    private static func makeES80ResearchCoordinator() -> PassiveBluetoothExperimentOneCoordinator? {
        // Production field authority is package-owned and package-gated. The app never mints
        // an unrelated generic controller/recorder and presents it as Experiment One authority.
        try? PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80()
    }""",
    "app factory",
)
app_path.write_text(app)

shell_path = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
shell = shell_path.read_text()
shell = replace_once(
    shell,
    """/// Critical authority boundary: the current package-owned `PassiveBluetoothExperimentOneRun`
/// creates and owns its own four-window producer, and its recorder/final H-bounded seal remains
/// intentionally internal. This app must not take an independently-created public correlation
/// result and start a separate capture recorder as if those two evidence lives were one Experiment
/// One authority. Therefore this shell can complete real correlation and exact read-only target
/// reacquisition, but it deliberately does not expose Start Capture, Finish, or Share until the
/// accepted controller composes the same package-issued Experiment One run end-to-end.
""",
    """/// Critical authority boundary: one package-owned `PassiveBluetoothExperimentOneCoordinator`
/// owns the four-window producer, sealed admission, canonical ES80 controller, and exact target
/// handoff. SwiftUI drives that one authority but never splices a public correlation result into a
/// separately minted recorder/controller. A repeated UUID remains correlation evidence only.
""",
    "shell authority comment",
)
shell = replace_once(
    shell,
    "        case targetReacquired(UUID)\n        case targetNotConnectable(UUID)",
    "        case targetReacquired(UUID)\n        case captureSessionArmed(UUID)\n        case targetNotConnectable(UUID)",
    "phase enum",
)
shell = replace_once(
    shell,
    """    let controller: ForegroundCoreBluetoothCaptureController

    @Environment(\.scenePhase) private var scenePhase

    @State private var correlationSession: PassiveBluetoothPowerCycleObservationSession?""",
    """    @State private var coordinator: PassiveBluetoothExperimentOneCoordinator

    private var controller: ForegroundCoreBluetoothCaptureController {
        coordinator.controller
    }

    init(coordinator: PassiveBluetoothExperimentOneCoordinator) {
        _coordinator = State(initialValue: coordinator)
    }

    @Environment(\.scenePhase) private var scenePhase

    @State private var correlationSession: PassiveBluetoothPowerCycleObservationSession?""",
    "coordinator ownership",
)
shell = replace_once(
    shell,
    """                Text("This build can complete the real repeated Bluetooth correlation step. Passive capture remains locked until one package-owned Experiment One authority spans correlation, Ready, Horizon, immutable seal, and export. Nembra will not splice separate evidence lives just to make the workflow look complete.")""",
    """                Text("This field surface is driven by one package-owned Experiment One authority from correlation into passive capture. Physical execution remains mechanically controlled by the package GO gate, and Ready, Horizon, immutable seal, analysis, Share, and runtime acceptance must stay on this same evidence life.")""",
    "physical lock copy",
)
shell = replace_once(
    shell,
    """            targetIdentifierStrip(identifier)
            captureBindingLock

        case let .targetNotConnectable(identifier):""",
    """            targetIdentifierStrip(identifier)
            primaryButton(
                "Start passive capture",
                systemImage: "dot.radiowaves.left.and.right",
                identifier: "es80.capture.start-passive-capture"
            ) {
                startPassiveCapture(identifier)
            }

        case let .captureSessionArmed(identifier):
            statePanel(
                eyebrow: "PASSIVE CAPTURE",
                title: "Experiment One authority is live",
                message: "The run-owned recorder is attached to the correlated target through the package coordinator. Nembra is collecting read-only finite GATT evidence. This is not ES80 authentication, and no characteristic write is authorized.",
                symbol: "wave.3.right.circle.fill"
            )
            targetIdentifierStrip(identifier)
            HStack(spacing: 10) {
                if !controller.hasCompleteTargetEvidence {
                    ProgressView().tint(.white)
                }
                Text(controller.hasCompleteTargetEvidence
                     ? "Finite acquisition complete. Ready/Horizon presentation is the next product rung."
                     : "Collecting finite passive evidence…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("es80.capture.passive-session-armed")

        case let .targetNotConnectable(identifier):""",
    "target handoff UI",
)
start = shell.index("    private var captureBindingLock: some View {")
end = shell.index("    private func correlationReadyPanel", start)
shell = shell[:start] + shell[end:]
shell = replace_once(
    shell,
    """        if controller.hasTargetSession {
            return .failed("This app slice does not authorize a standalone target capture session because it would not share the correlation producer's Experiment One authority. Relaunch the research build.")
        }""",
    """        if controller.hasTargetSession {
            if let identifier = correlatedTargetIdentifier ?? controller.selectedTargetIdentifier {
                return .captureSessionArmed(identifier)
            }
            return .failed("Experiment One owns a target session but its correlated target context is unavailable. Relaunch the research build.")
        }""",
    "target-session phase",
)
shell = replace_once(
    shell,
    """    private func prepareCorrelationSessionIfNeeded() {
        guard correlationSession == nil else { return }
        do {
            correlationSession = try PassiveBluetoothPowerCycleObservationSession(
                minimumWindowDuration: Self.requiredCorrelationWindowDuration
            )
        } catch {
            diagnosticMessage = "Correlation setup failed: \(String(describing: error))"
        }
    }""",
    """    private func prepareCorrelationSessionIfNeeded() {
        guard correlationSession == nil else { return }
        correlationSession = coordinator.powerCycleObservationSession
    }""",
    "session source",
)
shell = replace_once(
    shell,
    """    private func restartCorrelation() {
        guard !controller.hasTargetSession else {
            diagnosticMessage = "A target capture session already exists. Relaunch Nembra Capture instead of reusing this controller for a new Experiment One attempt."
            return
        }

        correlationSession?.abandonCurrentWindow()
        controller.stopScanning()
        correlatedTargetIdentifier = nil
        rediscoveryRequested = false
        observedScanBeganAtUptimeNanoseconds = nil
        lifecycleFailureMessage = nil
        diagnosticMessage = nil

        do {
            correlationSession = try PassiveBluetoothPowerCycleObservationSession(
                minimumWindowDuration: Self.requiredCorrelationWindowDuration
            )
        } catch {
            correlationSession = nil
            diagnosticMessage = "Correlation setup failed: \(String(describing: error))"
        }
    }
""",
    """    private func restartCorrelation() {
        guard !controller.hasTargetSession else {
            diagnosticMessage = "A target capture session already exists. Relaunch Nembra Capture instead of reusing its recorder for another Experiment One life."
            return
        }

        correlationSession?.abandonCurrentWindow()
        controller.stopScanning()
        correlatedTargetIdentifier = nil
        rediscoveryRequested = false
        observedScanBeganAtUptimeNanoseconds = nil
        lifecycleFailureMessage = nil
        diagnosticMessage = nil

        do {
            coordinator = try PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80()
            correlationSession = coordinator.powerCycleObservationSession
        } catch {
            correlationSession = nil
            diagnosticMessage = "A fresh package-owned Experiment One could not be created: \(String(describing: error))"
        }
    }
""",
    "restart correlation",
)
shell = replace_once(
    shell,
    """    private func confirmCorrelatedTarget(_ identifier: UUID) {
        correlatedTargetIdentifier = identifier
        startExactTargetRediscovery(identifier)
    }

    private func startExactTargetRediscovery(_ identifier: UUID) {
        diagnosticMessage = nil
        controller.stopScanning()
        rediscoveryRequested = false

        do {
            try controller.startScanning(captureAdvertisementCadence: false)
            rediscoveryRequested = true
        } catch {
            diagnosticMessage = "Exact-target rediscovery could not start: \(String(describing: error))"
        }
    }
""",
    """    private func confirmCorrelatedTarget(_ identifier: UUID) {
        diagnosticMessage = nil
        correlatedTargetIdentifier = identifier
        rediscoveryRequested = false

        do {
            try coordinator.prepareCaptureRediscovery()
            guard coordinator.preparedCorrelatedTargetIdentifier == identifier else {
                throw PassiveBluetoothExperimentOneCoordinator.CoordinatorError.correlatedTargetUnavailable
            }
            rediscoveryRequested = true
        } catch {
            diagnosticMessage = "Experiment One could not prepare exact-target rediscovery: \(String(describing: error))"
        }
    }

    private func startExactTargetRediscovery(_ identifier: UUID) {
        diagnosticMessage = nil
        guard coordinator.preparedCorrelatedTargetIdentifier == identifier else {
            diagnosticMessage = "The sealed Experiment One admission no longer matches this correlated target. Restart from OFF 1."
            return
        }
        rediscoveryRequested = false

        do {
            try coordinator.restartPreparedRediscovery()
            rediscoveryRequested = true
        } catch {
            diagnosticMessage = "Exact-target rediscovery could not restart: \(String(describing: error))"
        }
    }

    private func startPassiveCapture(_ identifier: UUID) {
        diagnosticMessage = nil
        guard coordinator.preparedCorrelatedTargetIdentifier == identifier else {
            diagnosticMessage = "The prepared Experiment One admission no longer matches this target. Restart from OFF 1."
            return
        }

        do {
            try coordinator.connectPreparedCapture()
            rediscoveryRequested = false
        } catch {
            diagnosticMessage = "Passive capture could not start: \(String(describing: error))"
        }
    }
""",
    "coordinator handoff",
)
shell = replace_once(
    shell,
    """        if correlationEvidenceIsLive {""",
    """        if controller.hasTargetSession {
            controller.invalidateActiveCaptureForForegroundLoss()
            lifecycleFailureMessage = "Nembra left the active foreground while the package-owned passive capture was live. This Experiment One evidence life is permanently invalid for export."
            diagnosticMessage = nil
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }

        if correlationEvidenceIsLive {""",
    "foreground capture invalidation",
)
shell = replace_once(
    shell,
    "        case .correlationStarting, .correlationObserving, .rediscoveringTarget, .targetReacquired:",
    "        case .correlationStarting, .correlationObserving, .rediscoveringTarget, .targetReacquired, .captureSessionArmed:",
    "idle timer",
)
shell = replace_once(
    shell,
    "        case .targetReacquired: \"Target reacquired — capture binding locked\"",
    "        case .targetReacquired: \"Target reacquired — ready for passive capture\"\n        case .captureSessionArmed: \"Passive Experiment One capture active\"",
    "status title",
)
shell = replace_once(
    shell,
    """        case .correlatedTarget, .targetReacquired:
            "checkmark.circle.fill"""",
    """        case .correlatedTarget, .targetReacquired:
            "checkmark.circle.fill"
        case .captureSessionArmed:
            "wave.3.right.circle.fill"""",
    "status symbol",
)
shell = replace_once(
    shell,
    """        case .correlatedTarget:
            .green""",
    """        case .correlatedTarget, .captureSessionArmed:
            .green""",
    "status color",
)
shell_path.write_text(shell)

tests_path = Path("NembraAppTests/NembraAppTests.swift")
tests = tests_path.read_text()
if "/// V14 app single-authority source contract." not in tests:
    tests += r'''

/// V14 app single-authority source contract.
/// These executable source checks guard the product boundary without minting test-only field authority.
extension NembraAppTests {
    private func experimentOneRepositorySource(at relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testCaptureShellDoesNotMintStandalonePublicCorrelationProducer() throws {
        let shell = try experimentOneRepositorySource(at: "NembraApp/Features/Research/ES80CaptureShellView.swift")
        XCTAssertFalse(shell.contains("PassiveBluetoothPowerCycleObservationSession("))
        XCTAssertTrue(shell.contains("PassiveBluetoothExperimentOneCoordinator"))
    }

    func testResearchLaunchUsesPackageGatedCanonicalCoordinator() throws {
        let app = try experimentOneRepositorySource(at: "NembraApp/App/NembraApp.swift")
        XCTAssertFalse(app.contains("try? ForegroundCoreBluetoothCaptureController("))
        XCTAssertTrue(app.contains("PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80()"))
    }

    func testBindingLockedTerminalIsReplacedByCoordinatorHandoff() throws {
        let shell = try experimentOneRepositorySource(at: "NembraApp/Features/Research/ES80CaptureShellView.swift")
        XCTAssertFalse(shell.contains("Passive capture binding not available in this build"))
        XCTAssertTrue(shell.contains("coordinator.prepareCaptureRediscovery()"))
        XCTAssertTrue(shell.contains("coordinator.connectPreparedCapture()"))
        XCTAssertTrue(shell.contains("es80.capture.passive-session-armed"))
    }
}
'''
tests_path.write_text(tests)
