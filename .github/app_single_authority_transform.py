from pathlib import Path
import subprocess

COORD = Path('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneCoordinator.swift')
APP = Path('NembraApp/App/NembraApp.swift')
SHELL = Path('NembraApp/Features/Research/ES80CaptureShellView.swift')
TEST = Path('NembraAppTests/NembraAppTests.swift')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected 1 match, found {count}')
    return text.replace(old, new, 1)

# Package-owned coordinator also creates the canonical ES80 controller, so app code
# never constructs a generic controller and then labels it field authority.
s = COORD.read_text()
needle = '''    /// Experiment One is ES80-specific. Canonical vehicle context is selected inside the package,
    /// never injected by app/UI code merely to make a run eligible.
    public init(controller: ForegroundCoreBluetoothCaptureController) throws {
        self.controller = controller
        run = try PassiveBluetoothExperimentOneRun(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
    }
'''
replacement = needle + '''
    /// Creates the complete app-facing ES80 Experiment One software owner. Both the
    /// controller and run are minted inside this package boundary so SwiftUI cannot
    /// splice a separately-created generic controller into field provenance.
    public convenience init() throws {
        let controller = try ForegroundCoreBluetoothCaptureController(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
        try self.init(controller: controller)
    }
'''
s = replace_once(s, needle, replacement, 'coordinator convenience init')
COORD.write_text(s)

# Research bootstrap owns exactly one package coordinator rather than a generic controller.
s = APP.read_text()
s = replace_once(
    s,
    '@State private var researchController: ForegroundCoreBluetoothCaptureController?\n',
    '@State private var experimentOneCoordinator: PassiveBluetoothExperimentOneCoordinator?\n',
    'app state owner',
)
s = replace_once(
    s,
    '''        _researchController = State(
            initialValue: fieldCaptureAuthorized
                ? Self.makeES80ResearchController()
                : nil
        )
''',
    '''        _experimentOneCoordinator = State(
            initialValue: fieldCaptureAuthorized
                ? Self.makeExperimentOneCoordinator()
                : nil
        )
''',
    'app init owner',
)
s = replace_once(
    s,
    '''                        if let researchController {
                            ES80CaptureShellView(controller: researchController)
                        } else {
                            ContentUnavailableView(
                                "Capture unavailable",
                                systemImage: "antenna.radiowaves.left.and.right.slash",
                                description: Text("The passive Bluetooth research controller could not be created.")
                            )
''',
    '''                        if let experimentOneCoordinator {
                            ES80CaptureShellView(coordinator: experimentOneCoordinator)
                        } else {
                            ContentUnavailableView(
                                "Capture unavailable",
                                systemImage: "antenna.radiowaves.left.and.right.slash",
                                description: Text("The package-owned Experiment One workflow could not be created.")
                            )
''',
    'app shell injection',
)
old_helper = '''    private static func makeES80ResearchController() -> ForegroundCoreBluetoothCaptureController? {
        // This is the declared software context required by the ES80 Experiment One authority.
        // It is metadata consistency only and must never be presented as physical authentication.
        try? ForegroundCoreBluetoothCaptureController(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
    }
'''
new_helper = '''    private static func makeExperimentOneCoordinator() -> PassiveBluetoothExperimentOneCoordinator? {
        // The package owns both the canonical ES80 software context and its controller.
        // Construction remains software provenance only, never physical authentication.
        try? PassiveBluetoothExperimentOneCoordinator()
    }
'''
s = replace_once(s, old_helper, new_helper, 'app coordinator factory')
APP.write_text(s)

s = SHELL.read_text()
# Keep the current import surface; Foundation URL/Data and SwiftUI ShareLink are sufficient.
s = replace_once(
    s,
    '''        case targetReacquired(UUID)
        case targetNotConnectable(UUID)
        case failed(String)
''',
    '''        case targetReacquired(UUID)
        case targetNotConnectable(UUID)
        case connectingTarget(UUID)
        case acquiringEvidence(UUID)
        case observingHorizon(UUID)
        case horizonEligible(UUID)
        case finalizingCapture
        case captureComplete
        case failed(String)
''',
    'phase expansion',
)
s = replace_once(
    s,
    '''    let controller: ForegroundCoreBluetoothCaptureController

    @Environment(\\.scenePhase) private var scenePhase

    @State private var correlationSession: PassiveBluetoothPowerCycleObservationSession?
    @State private var correlatedTargetIdentifier: UUID?
''',
    '''    @Environment(\\.scenePhase) private var scenePhase

    @State private var coordinator: PassiveBluetoothExperimentOneCoordinator
    @State private var correlatedTargetIdentifier: UUID?
''',
    'shell authority state',
)
s = replace_once(
    s,
    '''    @State private var diagnosticMessage: String?
    @State private var lifecycleFailureMessage: String?

    var body: some View {
''',
    '''    @State private var diagnosticMessage: String?
    @State private var lifecycleFailureMessage: String?
    @State private var finalizedCaptureData: Data?
    @State private var finalizedCaptureURL: URL?
    @State private var isFinalizingCapture = false

    init(coordinator: PassiveBluetoothExperimentOneCoordinator) {
        _coordinator = State(initialValue: coordinator)
    }

    private var controller: ForegroundCoreBluetoothCaptureController {
        coordinator.controller
    }

    /// Optional only to preserve the shell's existing presentation helpers. The value
    /// always comes from this coordinator's exact package-owned Experiment One run.
    private var correlationSession: PassiveBluetoothPowerCycleObservationSession? {
        coordinator.powerCycleObservationSession
    }

    var body: some View {
''',
    'shell coordinator accessors',
)

# Reacquired target now continues the same authority rather than stopping at a binding lock.
s = replace_once(
    s,
    '''            targetIdentifierStrip(identifier)
            captureBindingLock

        case let .targetNotConnectable(identifier):
''',
    '''            targetIdentifierStrip(identifier)
            primaryButton(
                "Begin passive capture",
                systemImage: "wave.3.right",
                identifier: "es80.capture.begin-passive-capture"
            ) {
                connectPreparedCapture()
            }

        case let .targetNotConnectable(identifier):
''',
    'reacquired action',
)
# Add live downstream product states before generic failure.
marker = '''        case let .failed(message):
            statePanel(
'''
downstream = '''        case let .connectingTarget(identifier):
            statePanel(
                eyebrow: "PASSIVE CAPTURE / CONNECTING",
                title: "Opening the correlated target",
                message: "Nembra consumed the sealed Experiment One handoff only after fresh exact-target rediscovery. The phone may now connect and perform read-only finite GATT acquisition.",
                symbol: "link"
            )
            targetIdentifierStrip(identifier)
            ProgressView().tint(.white).controlSize(.large)

        case let .acquiringEvidence(identifier):
            statePanel(
                eyebrow: "PASSIVE CAPTURE / ACQUIRING",
                title: "Building finite read-only evidence",
                message: "Nembra is discovering and reading the selected target without application characteristic writes. Capture cannot advance until the finite acquisition boundary is complete.",
                symbol: "wave.3.right"
            )
            targetIdentifierStrip(identifier)
            ProgressView().tint(.white).controlSize(.large)

        case let .observingHorizon(identifier):
            statePanel(
                eyebrow: "OBSERVATION ACTIVE",
                title: "Put the phone away",
                message: "Finite evidence is Ready. Nembra is now waiting for the package-owned monotonic Experiment One observation duration. The Finish action appears only when authoritative Horizon admission becomes eligible.",
                symbol: "timer"
            )
            targetIdentifierStrip(identifier)
            Text("Do not interact with the phone while riding. If motion is part of a later accepted procedure, arm while stationary and finish only after safely stopping.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case let .horizonEligible(identifier):
            statePanel(
                eyebrow: "HORIZON READY",
                title: "Safe to seal when stopped",
                message: "The canonical Ready-to-Horizon monotonic duration is eligible. Finish freezes one immutable artifact at the accepted queue cutoff; later callbacks cannot extend it.",
                symbol: "checkmark.seal"
            )
            targetIdentifierStrip(identifier)
            primaryButton(
                "Finish & seal capture",
                systemImage: "checkmark.seal.fill",
                identifier: "es80.capture.finish"
            ) {
                finalizeCapture()
            }

        case .finalizingCapture:
            statePanel(
                eyebrow: "SEALING",
                title: "Freezing immutable evidence",
                message: "Nembra is draining the accepted prefix, recording Horizon, validating authority and integrity, and sealing the exact JSON artifact.",
                symbol: "lock.doc"
            )
            ProgressView().tint(.white).controlSize(.large)

        case .captureComplete:
            statePanel(
                eyebrow: "CAPTURE COMPLETE",
                title: "Ready for analysis",
                message: finalizedCaptureData.map { "Sealed artifact: \\($0.count) bytes. Share the exact JSON unchanged for offline analysis." } ?? "The immutable capture is sealed and ready to share.",
                symbol: "checkmark.seal.fill"
            )
            if let finalizedCaptureURL {
                ShareLink(item: finalizedCaptureURL) {
                    Label("Share capture", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 56)
                        .foregroundStyle(.black)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("es80.capture.share")
            }
            if let finalizedCaptureData {
                Text("View details · JSON bytes \\(finalizedCaptureData.count) · ES80-FINGERPRINT-v1 · software evidence only")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("es80.capture.details")
            }

'''
s = replace_once(s, marker, downstream + marker, 'downstream phase UI')

# Remove the old binding-lock surface completely.
start = s.index('    private var captureBindingLock: some View {')
end = s.index('    private func correlationReadyPanel', start)
s = s[:start] + s[end:]

# Replace phase's old hard-stop with actual controller-driven downstream states.
old = '''        if controller.hasTargetSession {
            return .failed("This app slice does not authorize a standalone target capture session because it would not share the correlation producer's Experiment One authority. Relaunch the research build.")
        }

        if let identifier = correlatedTargetIdentifier {
'''
new = '''        if finalizedCaptureData != nil {
            return .captureComplete
        }
        if isFinalizingCapture {
            return .finalizingCapture
        }
        if controller.hasTargetSession {
            guard let identifier = controller.selectedTargetIdentifier ?? correlatedTargetIdentifier else {
                return .failed("Capture authority exists without a selected correlated target. Relaunch Nembra Capture.")
            }
            if controller.captureFailed {
                return .failed(controller.lastDiagnostic ?? "The passive capture failed closed.")
            }
            if controller.hasCompleteTargetEvidence {
                return controller.canFinalizeObservationHorizon
                    ? .horizonEligible(identifier)
                    : .observingHorizon(identifier)
            }
            switch controller.connectionPhase {
            case .connecting:
                return .connectingTarget(identifier)
            case .connected, .idle:
                return .acquiringEvidence(identifier)
            }
        }

        if let identifier = correlatedTargetIdentifier {
'''
s = replace_once(s, old, new, 'phase target-session continuation')

# Session setup is package-owned from construction; no app-minted producer.
old = '''    private func prepareCorrelationSessionIfNeeded() {
        guard correlationSession == nil else { return }
        do {
            correlationSession = try PassiveBluetoothPowerCycleObservationSession(
                minimumWindowDuration: Self.requiredCorrelationWindowDuration
            )
        } catch {
            diagnosticMessage = "Correlation setup failed: \\(String(describing: error))"
        }
    }
'''
new = '''    private func prepareCorrelationSessionIfNeeded() {
        // The exact producer already belongs to the package coordinator. Accessing it here
        // does not mint or replace evidence authority.
        _ = coordinator.powerCycleObservationSession
    }
'''
s = replace_once(s, old, new, 'package-owned setup')

# Restart creates an entirely fresh package-owned provenance life.
old = '''        do {
            correlationSession = try PassiveBluetoothPowerCycleObservationSession(
                minimumWindowDuration: Self.requiredCorrelationWindowDuration
            )
        } catch {
            correlationSession = nil
            diagnosticMessage = "Correlation setup failed: \\(String(describing: error))"
        }
'''
new = '''        do {
            coordinator = try PassiveBluetoothExperimentOneCoordinator()
        } catch {
            diagnosticMessage = "Experiment One setup failed: \\(String(describing: error))"
        }
'''
s = replace_once(s, old, new, 'fresh coordinator restart')

# Confirmation seals this exact run's evidence before the coordinator opens rediscovery.
old = '''    private func confirmCorrelatedTarget(_ identifier: UUID) {
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
            diagnosticMessage = "Exact-target rediscovery could not start: \\(String(describing: error))"
        }
    }
'''
new = '''    private func confirmCorrelatedTarget(_ identifier: UUID) {
        diagnosticMessage = nil
        correlatedTargetIdentifier = identifier
        rediscoveryRequested = false
        do {
            try coordinator.prepareCaptureRediscovery()
            rediscoveryRequested = true
        } catch {
            diagnosticMessage = "Exact-target rediscovery could not start: \\(String(describing: error))"
        }
    }

    private func startExactTargetRediscovery(_ identifier: UUID) {
        diagnosticMessage = nil
        correlatedTargetIdentifier = identifier
        rediscoveryRequested = false
        do {
            try coordinator.restartPreparedRediscovery()
            rediscoveryRequested = true
        } catch {
            diagnosticMessage = "Exact-target rediscovery could not restart: \\(String(describing: error))"
        }
    }

    private func connectPreparedCapture() {
        diagnosticMessage = nil
        do {
            try coordinator.connectPreparedCapture()
            rediscoveryRequested = false
        } catch let error as PassiveBluetoothExperimentOneCoordinator.CoordinatorError {
            switch error {
            case .targetNotRediscovered:
                diagnosticMessage = "The exact correlated target has not been freshly rediscovered yet. Keep scanning and try again."
            case .targetNotConnectable:
                diagnosticMessage = "The exact correlated target is currently reported non-connectable."
            case .captureAdmissionNotPrepared, .captureAdmissionAlreadyPrepared, .correlatedTargetUnavailable:
                lifecycleFailureMessage = "Experiment One authority is no longer eligible for this capture. Restart from OFF 1."
            }
        } catch let error as ForegroundCoreBluetoothCaptureController.ControllerError {
            switch error {
            case .unknownPeripheral:
                diagnosticMessage = "The correlated target needs one newer post-admission observation. Keep scanning and try again."
            case .peripheralNotConnectable:
                diagnosticMessage = "The correlated target is not connectable in the current scan epoch."
            default:
                lifecycleFailureMessage = "Passive capture could not begin without weakening authority: \\(String(describing: error))"
            }
        } catch {
            lifecycleFailureMessage = "Passive capture could not begin: \\(String(describing: error))"
        }
    }

    private func finalizeCapture() {
        guard !isFinalizingCapture, finalizedCaptureData == nil else { return }
        isFinalizingCapture = true
        diagnosticMessage = nil
        Task { @MainActor in
            do {
                let data = try await controller.encodedFinalizedObservationHorizonJSON(prettyPrinted: true)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Nembra-ES80-FINGERPRINT-v1-\\(UUID().uuidString).json")
                try data.write(to: url, options: .atomic)
                finalizedCaptureData = data
                finalizedCaptureURL = url
                do {
                    try controller.teardownActiveConnectionAfterFinalization()
                } catch {
                    diagnosticMessage = "Artifact sealed successfully; transport cleanup needs a fresh app session before another capture."
                }
            } catch {
                lifecycleFailureMessage = "Capture could not seal its immutable Horizon artifact: \\(String(describing: error))"
            }
            isFinalizingCapture = false
        }
    }
'''
s = replace_once(s, old, new, 'coordinator capture continuation')

# Foreground loss after target-session admission invalidates live evidence; sealed data remains immutable.
needle = '''        if correlationEvidenceIsLive {
            correlationSession?.abandonCurrentWindow()
            lifecycleFailureMessage = "Nembra left the active foreground while a bounded correlation window was live. This four-window series is no longer eligible for Experiment One correlation evidence."
            diagnosticMessage = nil
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }

        if rediscoveryRequested {
'''
replacement = '''        if correlationEvidenceIsLive {
            correlationSession?.abandonCurrentWindow()
            lifecycleFailureMessage = "Nembra left the active foreground while a bounded correlation window was live. This four-window series is no longer eligible for Experiment One correlation evidence."
            diagnosticMessage = nil
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }

        if controller.hasTargetSession, finalizedCaptureData == nil {
            controller.invalidateActiveCaptureForForegroundLoss()
            lifecycleFailureMessage = "Nembra left the active foreground during passive capture. This evidence life is permanently invalid for Experiment One export."
            diagnosticMessage = nil
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }

        if rediscoveryRequested {
'''
s = replace_once(s, needle, replacement, 'foreground capture integrity')

# Keep display awake for active evidence lifecycle and sealing.
s = replace_once(
    s,
    '''        case .correlationStarting, .correlationObserving, .rediscoveringTarget, .targetReacquired:
            UIApplication.shared.isIdleTimerDisabled = true
''',
    '''        case .correlationStarting, .correlationObserving, .rediscoveringTarget, .targetReacquired,
             .connectingTarget, .acquiringEvidence, .observingHorizon, .horizonEligible, .finalizingCapture:
            UIApplication.shared.isIdleTimerDisabled = true
''',
    'idle timer downstream',
)

# Update status vocabulary / switch exhaustiveness.
s = replace_once(
    s,
    '''        case .targetReacquired: "Target reacquired — capture binding locked"
        case .targetNotConnectable: "Correlated target unavailable"
        case .failed: "Correlation failed closed"
''',
    '''        case .targetReacquired: "Target reacquired — ready for passive capture"
        case .targetNotConnectable: "Correlated target unavailable"
        case .connectingTarget: "Connecting to correlated target"
        case .acquiringEvidence: "Acquiring passive evidence"
        case .observingHorizon: "Observation active"
        case .horizonEligible: "Horizon ready to seal"
        case .finalizingCapture: "Sealing immutable capture"
        case .captureComplete: "Capture complete — ready for analysis"
        case .failed: "Capture failed closed"
''',
    'status titles',
)
s = replace_once(
    s,
    '''        case .correlatedTarget, .targetReacquired:
            "checkmark.circle.fill"
        case .correlationObserving, .correlationStarting, .rediscoveringTarget:
            "circle.dotted"
        case .failed, .correlationFailed, .ambiguousTargets, .noRepeatableTarget, .targetNotConnectable:
            "exclamationmark.triangle.fill"
        case .bluetoothUnavailable, .correlationUnavailable, .correlationReady:
            "circle.fill"
''',
    '''        case .correlatedTarget, .targetReacquired, .horizonEligible, .captureComplete:
            "checkmark.circle.fill"
        case .correlationObserving, .correlationStarting, .rediscoveringTarget,
             .connectingTarget, .acquiringEvidence, .observingHorizon, .finalizingCapture:
            "circle.dotted"
        case .failed, .correlationFailed, .ambiguousTargets, .noRepeatableTarget, .targetNotConnectable:
            "exclamationmark.triangle.fill"
        case .bluetoothUnavailable, .correlationUnavailable, .correlationReady:
            "circle.fill"
''',
    'status symbols',
)
s = replace_once(
    s,
    '''        case .correlatedTarget:
            .green
        case .failed, .correlationFailed:
            .red
        case .targetReacquired,
             .ambiguousTargets,
             .noRepeatableTarget,
             .targetNotConnectable,
             .bluetoothUnavailable,
             .correlationUnavailable:
            .orange
        case .correlationReady, .correlationStarting, .correlationObserving, .rediscoveringTarget:
            .white.opacity(0.78)
''',
    '''        case .correlatedTarget, .horizonEligible, .captureComplete:
            .green
        case .failed, .correlationFailed:
            .red
        case .targetReacquired,
             .ambiguousTargets,
             .noRepeatableTarget,
             .targetNotConnectable,
             .bluetoothUnavailable,
             .correlationUnavailable:
            .orange
        case .correlationReady, .correlationStarting, .correlationObserving, .rediscoveringTarget,
             .connectingTarget, .acquiringEvidence, .observingHorizon, .finalizingCapture:
            .white.opacity(0.78)
''',
    'status colors',
)

# Mechanical source assertions for the app-visible authority gate.
assert 'PassiveBluetoothPowerCycleObservationSession(' not in s
assert 'Passive capture binding not available in this build' not in s
assert 'connectPreparedCapture()' in s
assert 'encodedFinalizedObservationHorizonJSON' in s
assert 'ShareLink(item: finalizedCaptureURL)' in s
SHELL.write_text(s)

# The app diagnostic from #690 must now pass mechanically without merging its expected-red branch.
app = APP.read_text()
assert 'try? ForegroundCoreBluetoothCaptureController(' not in app
assert 'PassiveBluetoothExperimentOneCoordinator' in app

subprocess.run(['git', 'diff', '--check'], check=True)
subprocess.run(['git', 'add', str(COORD), str(APP), str(SHELL)], check=True)
subprocess.run(['git', 'diff', '--cached', '--check'], check=True)
