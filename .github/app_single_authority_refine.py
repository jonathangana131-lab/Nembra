from pathlib import Path
import subprocess

COORD = Path('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneCoordinator.swift')
SHELL = Path('NembraApp/Features/Research/ES80CaptureShellView.swift')
TEST = Path('NembraAppTests/NembraAppTests.swift')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected 1 match, found {count}')
    return text.replace(old, new, 1)

s = COORD.read_text()
old = '''        defer {
            pendingCaptureAdmission = nil
            preparedCorrelatedTargetIdentifier = nil
        }
        try controller.connectUsingExperimentOneAdmission(admission, timeout: timeout)
'''
new = '''        do {
            try controller.connectUsingExperimentOneAdmission(admission, timeout: timeout)
        } catch let error as ForegroundCoreBluetoothCaptureController.ControllerError {
            // These failures happen before the controller's irreversible admission.consume().
            // Preserve the same sealed evidence life so passive scanning / terminal-callback
            // recovery can continue without forcing the rider to repeat four valid windows.
            switch error {
            case .unknownPeripheral,
                 .peripheralNotConnectable,
                 .peripheralAwaitingTerminalCallback:
                throw error
            default:
                pendingCaptureAdmission = nil
                preparedCorrelatedTargetIdentifier = nil
                throw error
            }
        } catch {
            // Unknown downstream failure may have crossed the one-shot handoff. Fail closed.
            pendingCaptureAdmission = nil
            preparedCorrelatedTargetIdentifier = nil
            throw error
        }

        pendingCaptureAdmission = nil
        preparedCorrelatedTargetIdentifier = nil
'''
s = replace_once(s, old, new, 'coordinator recoverable handoff')
COORD.write_text(s)

s = SHELL.read_text()
# Update stale pre-coordinator documentation.
old = '''/// This surface consumes the accepted public four-window CoreBluetooth producer directly:
/// OFF1 -> ON1 -> OFF2 -> ON2. A single repeatable UUID is only correlated Bluetooth-target
/// evidence. It is never presented as authenticated/permanent ES80 identity.
///
/// Critical authority boundary: the current package-owned `PassiveBluetoothExperimentOneRun`
/// creates and owns its own four-window producer, and its recorder/final H-bounded seal remains
/// intentionally internal. This app must not take an independently-created public correlation
/// result and start a separate capture recorder as if those two evidence lives were one Experiment
/// One authority. Therefore this shell can complete real correlation and exact read-only target
/// reacquisition, but it deliberately does not expose Start Capture, Finish, or Share until the
/// accepted controller composes the same package-issued Experiment One run end-to-end.
'''
new = '''/// This surface is only presented behind the package-owned field-execution gate and consumes one
/// `PassiveBluetoothExperimentOneCoordinator` from OFF1 -> ON1 -> OFF2 -> ON2 correlation through
/// sealed admission, exact-target rediscovery, passive finite acquisition, monotonic Ready/Horizon,
/// immutable JSON seal, and Share. SwiftUI never receives the hidden admission or mutable recorder.
///
/// A repeated full CoreBluetooth UUID remains correlated Bluetooth-target evidence only. Nothing on
/// this surface authenticates permanent AOVOPRO ES80 identity, RF completeness, or protocol meaning.
'''
s = replace_once(s, old, new, 'shell authority docs')
# The outer app already owns the physical NO-GO screen; once this shell is reachable the package gate
# has mechanically permitted the procedure, so do not render a contradictory second lock card.
s = replace_once(s, '                    physicalRunLock\n', '', 'remove contradictory shell lock')
start = s.index('    private var physicalRunLock: some View {')
end = s.index('    private var correlationProgress: some View {', start)
s = s[:start] + s[end:]
# Re-entry must never restart correlation rediscovery once the sealed target session exists.
s = replace_once(
    s,
    '''        if newScenePhase == .active {
            if let identifier = correlatedTargetIdentifier,
               !rediscoveryRequested,
               lifecycleFailureMessage == nil {
                startExactTargetRediscovery(identifier)
            }
            return
        }
''',
    '''        if newScenePhase == .active {
            if !controller.hasTargetSession,
               let identifier = correlatedTargetIdentifier,
               !rediscoveryRequested,
               lifecycleFailureMessage == nil {
                startExactTargetRediscovery(identifier)
            }
            return
        }
''',
    'foreground reentry guard',
)
SHELL.write_text(s)

# Add executable app-source regression coverage in the existing test compilation unit.
s = TEST.read_text()
block = '''

/// V14 app-visible Experiment One authority regression. These source checks intentionally live in
/// the already-wired NembraAppTests compilation unit; they prove product wiring shape only, never
/// physical scooter identity or runtime BLE behavior.
extension NembraAppTests {
    func testCaptureFieldLaunchUsesPackageOwnedExperimentOneCoordinator() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let app = try String(
            contentsOf: root.appendingPathComponent("NembraApp/App/NembraApp.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(app.contains("PassiveBluetoothExperimentOneCoordinator"))
        XCTAssertFalse(app.contains("try? ForegroundCoreBluetoothCaptureController("))
    }

    func testCaptureShellContinuesSameAuthorityThroughSealAndShare() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let shell = try String(
            contentsOf: root.appendingPathComponent("NembraApp/Features/Research/ES80CaptureShellView.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(shell.contains("PassiveBluetoothPowerCycleObservationSession("))
        XCTAssertFalse(shell.contains("Passive capture binding not available in this build"))
        XCTAssertTrue(shell.contains("coordinator.prepareCaptureRediscovery()"))
        XCTAssertTrue(shell.contains("coordinator.connectPreparedCapture()"))
        XCTAssertTrue(shell.contains("encodedFinalizedObservationHorizonJSON"))
        XCTAssertTrue(shell.contains("ShareLink(item: finalizedCaptureURL)"))
    }
}
'''
if 'testCaptureFieldLaunchUsesPackageOwnedExperimentOneCoordinator' in s:
    raise RuntimeError('app authority regression already exists')
s += block
TEST.write_text(s)

assert 'Passive capture binding not available in this build' not in SHELL.read_text()
assert 'PassiveBluetoothPowerCycleObservationSession(' not in SHELL.read_text()
assert '!controller.hasTargetSession' in SHELL.read_text()
assert 'case .unknownPeripheral,' in COORD.read_text()
subprocess.run(['git', 'diff', '--check'], check=True)
subprocess.run(['git', 'add', str(COORD), str(SHELL), str(TEST)], check=True)
subprocess.run(['git', 'diff', '--cached', '--check'], check=True)
