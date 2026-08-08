from pathlib import Path

SHELL = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
RIDER_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/ES80CaptureRiderLanguageAcceptanceTests.swift")
APP = Path("NembraApp/App/NembraApp.swift")
PREFLIGHT_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/ES80CaptureStationaryPreflightRiderLanguageAcceptanceTests.swift")


def replace_required(source: str, old: str, new: str, *, label: str) -> str:
    count = source.count(old)
    if count == 0:
        raise SystemExit(f"missing expected {label}: {old!r}")
    return source.replace(old, new)


# -----------------------------------------------------------------------------
# Stationary preflight: keep the exact recipe token subordinate to engineering
# truth while preserving the disconnected-only admission/reset contract.
# -----------------------------------------------------------------------------
app = APP.read_text()
app = replace_required(
    app,
    'detail: "Required for ES80-FINGERPRINT-v1"',
    'detail: "Keep unplugged for the whole capture"',
    label="stationary-preflight recipe label",
)
preflight_start = app.index("private struct ES80ExperimentOneStationaryPreflightView")
field_no_go_start = app.index("private struct ES80ExperimentOneFieldNoGoView", preflight_start)
preflight = app[preflight_start:field_no_go_start]
if "ES80-FINGERPRINT-v1" in preflight:
    raise SystemExit("raw recipe token remains in stationary preflight")
for required in (
    "Stationary preflight",
    "Confirm the charger state before OFF 1 becomes available.",
    "Keep unplugged for the whole capture",
    "Unplug charger to continue",
    "selectedChargerState = nil",
    "disconnectedDeclarationAccepted = false",
    "es80.capture.preflight.continue",
):
    if required not in preflight:
        raise SystemExit(f"stationary preflight invariant missing: {required}")
for required in (
    "PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure",
    "PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue",
    "Text(recipeID)",
    "Engineering details",
):
    if required not in app:
        raise SystemExit(f"field truth invariant missing: {required}")
APP.write_text(app)

PREFLIGHT_TEST.write_text(r'''import Foundation
import Testing

@Suite("ES80 Capture stationary-preflight rider language")
struct ES80CaptureStationaryPreflightRiderLanguageAcceptanceTests {
    private static func appSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("App")
                .appendingPathComponent("NembraApp.swift"),
            encoding: .utf8
        )
    }

    private static func stationaryPreflight(in source: String) throws -> Substring {
        let beginning = try #require(
            source.range(of: "private struct ES80ExperimentOneStationaryPreflightView")
        )
        let fieldNoGo = try #require(
            source.range(
                of: "private struct ES80ExperimentOneFieldNoGoView",
                range: beginning.lowerBound..<source.endIndex
            )
        )
        return source[beginning.lowerBound..<fieldNoGo.lowerBound]
    }

    @Test("stationary preflight keeps recipe identifiers out of the rider path")
    func preflightIsHumanFirst() throws {
        let source = try Self.appSource()
        let preflight = try Self.stationaryPreflight(in: source)

        #expect(!preflight.contains("ES80-FINGERPRINT-v1"))
        #expect(preflight.contains("Stationary preflight"))
        #expect(preflight.contains("Confirm the charger state before OFF 1 becomes available."))
        #expect(preflight.contains("Disconnected"))
        #expect(preflight.contains("Keep unplugged for the whole capture"))
        #expect(preflight.contains("Unplug charger to continue"))
    }

    @Test("language cleanup preserves charger fail-closed and fresh-run reset")
    func physicalPreflightTruthRemainsFailClosed() throws {
        let source = try Self.appSource()
        let preflight = try Self.stationaryPreflight(in: source)

        #expect(source.contains("PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure"))
        #expect(preflight.contains("selectedChargerState?.rawValue"))
        #expect(preflight.contains("PassiveBluetoothStationaryCaptureChargerState.disconnected.rawValue"))
        #expect(preflight.contains(".disabled(!canContinue)"))
        #expect(preflight.contains("selectedChargerState = nil"))
        #expect(preflight.contains("disconnectedDeclarationAccepted = false"))
        #expect(preflight.contains("es80.capture.preflight.continue"))
    }

    @Test("exact recipe identity remains subordinate in engineering truth")
    func recipeIdentityStillExistsOutsidePreflight() throws {
        let source = try Self.appSource()
        let preflight = try Self.stationaryPreflight(in: source)

        #expect(!preflight.contains("ES80-FINGERPRINT-v1"))
        #expect(source.contains("PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue"))
        #expect(source.contains("Text(recipeID)"))
        #expect(source.contains("Engineering details"))
    }
}
''')


# -----------------------------------------------------------------------------
# Capture shell: finish the human-first pass across visible cards, VoiceOver,
# status helpers, and error/fallback text. Technical truth remains in Details.
# -----------------------------------------------------------------------------
shell = SHELL.read_text()
replacements = [
    ('Text("EXPERIMENT ONE")', 'Text("CAPTURE PROGRESS")'),
    ('It never sends application characteristic-value writes, and names, signal strength, or service hints never decide which signal belongs to this run.', 'It never sends control commands to the scooter, and names, signal strength, or service hints never decide which signal belongs to this run.'),
    ('eyebrow: "FIELD AUTHORITY"', 'eyebrow: "CAPTURE LOCKED"'),
    ('Confirm only when those are your declared setup conditions for this Experiment One run.', 'Confirm only when those are the setup conditions for this Capture run.'),
    ('This records your operator declaration; it is not independent proof that the condition held continuously.', 'This records what you confirmed. Nembra cannot independently verify that the condition stayed true for the whole Capture.'),
    ('The package producer, not this timer, decides whether the window has enough evidence.', 'This timer is guidance only. Nembra verifies the required observation before accepting this step.'),
    ('eyebrow: "CORRELATION STOPPED"', 'eyebrow: "SIGNAL CHECK STOPPED"'),
    ('"Restart Experiment One"', '"Restart Capture"'),
    ('eyebrow: "NO UNIQUE TARGET"', 'eyebrow: "NO UNIQUE SIGNAL"'),
    ('No selectable full Bluetooth identifier was absent in both OFF windows and repeated in both ON windows. Nembra will not guess from name, signal strength, service hints, or short IDs.', 'No single Bluetooth signal disappeared in both OFF checks and returned in both ON checks. Nembra will not guess from name, signal strength, service hints, or short IDs.'),
    ('"Repeat all four windows"', '"Repeat all four checks"'),
    ('eyebrow: "AMBIGUOUS TARGET"', 'eyebrow: "MULTIPLE MATCHES"'),
    ('More than one selectable full Bluetooth identifier repeated the OFF / ON pattern. Nembra refuses to break the tie with display name, RSSI, services, or a short identifier.', 'More than one Bluetooth signal followed the same OFF / ON pattern. Nembra will not guess which one is the scooter from name, signal strength, services, or a short ID.'),
    ('title: "One target repeated twice"', 'title: "One signal matched twice"'),
    ('"Confirm correlated target"', '"Confirm scooter signal"'),
    ('title: "Reacquiring the exact signal"', 'title: "Checking the same signal again"'),
    ('"Restart rediscovery"', '"Restart signal check"'),
    ('eyebrow: "CORRELATED TARGET"', 'eyebrow: "MATCHED SIGNAL"'),
    ('title: "Exact signal reacquired"', 'title: "Same signal found again"'),
    ('The same Bluetooth signal has reappeared after confirmation. It is ready for read-only observation, but it is still correlated signal evidence—not permanent hardware identity.', 'The same Bluetooth signal appeared again after confirmation. It is ready for read-only observation, but this match applies only to this Capture and does not permanently identify the scooter.'),
    ('eyebrow: "PASSIVE CONNECTION"', 'eyebrow: "READ-ONLY CONNECTION"'),
    ('title: "Opening the correlated target"', 'title: "Opening the matched signal"'),
    ('This workflow remains read only and does not send application characteristic-value writes.', 'This workflow remains read only and sends no control commands to the scooter.'),
    ('eyebrow: "PASSIVE ACQUISITION"', 'eyebrow: "READ-ONLY DISCOVERY"'),
    ('title: "Learning the readable surface"', 'title: "Learning what is available"'),
    ('Available only after the package accepts the required monotonic observation duration.', 'Available only after Nembra verifies the required observation time.'),
    ('eyebrow: "HORIZON READY"', 'eyebrow: "READY TO SEAL"'),
    ('"Start a fresh Experiment One"', '"Start a fresh Capture"'),
    ('healthItem("FINITE", value: observationReady ? "READY" : "WAIT")', 'healthItem("DISCOVERY", value: observationReady ? "READY" : "WAIT")'),
    ('healthItem("HORIZON", value: horizonReady ? "READY" : "HOLD")', 'healthItem("SEAL", value: horizonReady ? "READY" : "HOLD")'),
    ('"Capture health. Target \\(connection == .connected ? \\"bound\\" : \\"waiting\\"). Finite acquisition \\(observationReady ? \\"ready\\" : \\"waiting\\"). Horizon \\(horizonReady ? \\"ready\\" : \\"waiting\\")."', '"Capture health. Target \\(connection == .connected ? \\"matched\\" : \\"waiting\\"). Discovery \\(observationReady ? \\"ready\\" : \\"waiting\\"). Seal \\(horizonReady ? \\"ready\\" : \\"waiting\\")."'),
    ('return .failed("Nembra left the active foreground after Experiment One began. This evidence life cannot regain capture authority; start a fresh Experiment One.")', 'return .failed("Nembra left the active foreground after Capture began. This run cannot safely resume; start a fresh Capture.")'),
    ('return .failed(coordinator.lastDiagnostic ?? "The passive target connection ended before an accepted observation could be sealed. Start a fresh Experiment One rather than replaying consumed authority.")', 'return .failed(coordinator.lastDiagnostic ?? "The passive Bluetooth connection ended before observation was ready to seal. This run cannot safely continue; start a fresh Capture.")'),
    ('return .bluetoothUnavailable("The package-owned CoreBluetooth controller is unavailable for this coordinator.")', 'return .bluetoothUnavailable("Bluetooth capture is unavailable in this session.")'),
    ('return .correlationFailed("The four windows did not preserve one valid package-issued observation authority and required OFF 1, ON 1, OFF 2, ON 2 ordering.")', 'return .correlationFailed("The four Bluetooth checks did not preserve the required OFF 1, ON 1, OFF 2, ON 2 evidence order. Start again from OFF 1.")'),
    ('return .correlationFailed("The package-owned Experiment One workflow has no active correlation progress and no final result.")', 'return .correlationFailed("This Capture has no active OFF / ON progress and no completed result. Start a fresh Capture.")'),
    ('return .failed("Simulator QA interruption fixture. This synthetic state represents a foreground-invalidated evidence life; it is not physical evidence.")', 'return .failed("Simulator QA interruption fixture. A foreground interruption invalidated this synthetic Capture run; it is not physical evidence.")'),
    ('localFailureMessage = "Nembra could not create a fresh package-owned Experiment One workflow: \\(String(describing: error))"', 'localFailureMessage = "Nembra could not start a fresh Capture session: \\(String(describing: error))"'),
    ('return "The package-owned physical execution gate is closed for this build."', 'return "This build is locked for real scooter capture."'),
    ('return "The correlated-target admission is already prepared. Continue the current rediscovery."', 'return "The matched Bluetooth signal is already prepared. Continue the current signal check."'),
    ('return "No sealed correlated-target admission is ready for this step."', 'return "No confirmed Bluetooth signal is ready for this step."'),
    ('return "The four-window evidence authority or ordering is invalid."', 'return "The four OFF / ON checks are invalid or out of order."'),
    ('return "The exact correlated target has not reappeared in the fresh post-admission scan yet. Keep scanning and retry."', 'return "The matched Bluetooth signal has not reappeared yet. Keep the scooter ON and retry the signal check."'),
    ('return "The exact correlated target is visible but CoreBluetooth reports it as non-connectable."', 'return "The matched Bluetooth signal is visible but cannot accept a passive connection."'),
    ('return "The package-owned passive capture controller is unavailable."', 'return "Bluetooth capture is unavailable in this session."'),
    ('return "The accepted Ready epoch and minimum monotonic observation interval are not complete yet."', 'return "The required observation time is not complete yet."'),
    ('return "This Experiment One artifact is already immutable."', 'return "This Capture is already sealed."'),
    ('return "The accepted correlation-window duration is invalid in this build."', 'return "This build has an invalid OFF / ON observation duration."'),
    ('return "All four correlation windows are already sealed."', 'return "All four OFF / ON checks are already complete."'),
    ('return "This correlation series was invalidated by a known evidence gap."', 'return "This OFF / ON series was invalidated by a Bluetooth or foreground gap."'),
    ('return "The current correlation window is already active."', 'return "This OFF / ON check is already running."'),
    ('return "No correlation window is currently active."', 'return "No OFF / ON check is currently running."'),
    ('return "Bluetooth became unavailable during the bounded window."', 'return "Bluetooth became unavailable during this check."'),
    ('return "Scanning was requested, but the authoritative receipt window has not opened yet."', 'return "Bluetooth scanning is starting. Keep Nembra open and retry when it is ready."'),
    ('return "CoreBluetooth never confirmed scan readiness inside the bounded startup interval."', 'return "Bluetooth scanning did not become ready in time. Keep Nembra open and try this check again."'),
    ('return "The exact window\'s CoreBluetooth scan became inactive."', 'return "Bluetooth scanning stopped during this check."'),
    ('return "The producer\'s monotonic receipt window has not reached the required minimum yet."', 'return "This OFF / ON check has not recorded enough observation time yet."'),
    ('return "The producer could not establish a monotonic observation window."', 'return "Nembra could not verify the required timing for this check. Restart the four OFF / ON checks."'),
    ('return "The local observation-window sequence was exhausted."', 'return "The four OFF / ON checks are already complete."'),
    ('return "The package-owned Bluetooth controller has not been instantiated for this build."', 'return "Bluetooth capture is not ready yet."'),
    ('return "Waiting for CoreBluetooth to report its state."', 'return "Waiting for Bluetooth to become ready."'),
    ('return "CoreBluetooth reported an unknown future state. Capture remains unavailable."', 'return "Bluetooth reported an unknown state. Capture remains unavailable."'),
    ('if presentationCanFinalizeObservationHorizon(status: status) { return "H READY" }', 'if presentationCanFinalizeObservationHorizon(status: status) { return "SEAL READY" }'),
    ('if presentationConnection(status: status) == .connected { return "ACQUIRE" }', 'if presentationConnection(status: status) == .connected { return "DISCOVER" }'),
    ('if presentationHasPreparedCaptureAdmission(status: status) { return "REACQUIRE" }', 'if presentationHasPreparedCaptureAdmission(status: status) { return "MATCH" }'),
    ('? "Experiment One progress, capture sealed and ready for analysis"', '? "Capture progress, sealed and ready for analysis"'),
    (': "Experiment One progress, capture sealed; final artifact integrity not yet verified"', ': "Capture progress, sealed; final file integrity not yet verified"'),
    ('return "Experiment One progress, observation Horizon ready to seal"', 'return "Capture progress, required observation complete and ready to seal"'),
    ('return "Experiment One progress, four correlation windows complete and passive observation ready"', 'return "Capture progress, four OFF / ON checks complete and read-only observation ready"'),
    ('return "Experiment One progress, \\(min(completedWindows, 4)) of 4 correlation windows complete"', 'return "Capture progress, \\(min(completedWindows, 4)) of 4 OFF / ON checks complete"'),
    ('case .complete: return "Evidence, sealed."', 'case .complete: return "Capture sealed."'),
    ('case .readyToSeal, .observing: return "Hold the evidence line."', 'case .readyToSeal, .observing: return "Keep the capture steady."'),
    ('case .acquiring, .connecting, .rediscoveringTarget, .targetReacquired: return "Bind the real signal."', 'case .acquiring, .connecting, .rediscoveringTarget, .targetReacquired: return "Confirm the scooter signal."'),
    ('default: return "Find the real scooter signal."', 'default: return "Find the scooter signal."'),
    ('case .correlationFailed, .failed: return "Evidence stopped"', 'case .correlationFailed, .failed: return "Capture stopped"'),
    ('case .ambiguousTargets: return "Correlation ambiguous"', 'case .ambiguousTargets: return "Multiple signal matches"'),
    ('case .correlatedTarget: return "Correlated target found"', 'case .correlatedTarget: return "Scooter signal matched"'),
    ('case .rediscoveringTarget: return "Fresh rediscovery"', 'case .rediscoveringTarget: return "Checking signal again"'),
    ('case .targetReacquired: return "Target reacquired"', 'case .targetReacquired: return "Same signal found"'),
    ('case .acquiring: return "Finite acquisition"', 'case .acquiring: return "Read-only discovery"'),
    ('case .readyToSeal: return "Horizon ready"', 'case .readyToSeal: return "Ready to seal"'),
    ('case .finalizing: return "Sealing artifact"', 'case .finalizing: return "Sealing Capture"'),
]
for old, new in replacements:
    shell = replace_required(shell, old, new, label="rider copy")

# Displayed/VoiceOver leaks must be gone from production source literals. Technical
# terms are deliberately retained inside the Details surface itself.
leaks = (
    'healthItem("FINITE"',
    'healthItem("HORIZON"',
    'eyebrow: "HORIZON READY"',
    'eyebrow: "PASSIVE ACQUISITION"',
    "The package producer, not this timer",
    "selectable full Bluetooth identifier",
    "package-owned CoreBluetooth controller is unavailable",
    "package-issued observation authority",
    "fresh post-admission scan",
    "accepted Ready epoch",
    "authoritative receipt window",
    "producer's monotonic receipt window",
    "CoreBluetooth never confirmed scan readiness",
    'case .acquiring: return "Finite acquisition"',
    'case .readyToSeal: return "Horizon ready"',
    "Experiment One progress",
)
for leak in leaks:
    if leak in shell:
        raise SystemExit(f"rider-facing implementation language remains: {leak}")

for required in (
    'Text("CAPTURE PROGRESS")',
    'healthItem("DISCOVERY"',
    'healthItem("SEAL"',
    'eyebrow: "READY TO SEAL"',
    'case .acquiring: return "Read-only discovery"',
    'case .readyToSeal: return "Ready to seal"',
    "guard status.physicalProcedurePermitted else",
    "PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(artifact.json)",
    "finalShareIntegrityReport != nil",
    'Text("Truth boundary")',
    "CoreBluetooth",
):
    if required not in shell:
        raise SystemExit(f"required product/truth invariant missing: {required}")
SHELL.write_text(shell)


# -----------------------------------------------------------------------------
# Strengthen the merged #993 source contract: include the hero in the primary
# slice and explicitly pin helper/fallback strings that live outside it.
# -----------------------------------------------------------------------------
test = RIDER_TEST.read_text()
test = replace_required(
    test,
    'source.range(of: "private var passiveSafetyPanel")',
    'source.range(of: "private func hero(for phase: Phase)")',
    label="rider test primary boundary",
)
insert_marker = '\n    @Test("engineering truth remains available in Details instead of being deleted")'
if insert_marker not in test:
    raise SystemExit("rider test insertion marker missing")
extra = r'''

    @Test("rendered helper and fallback copy stays rider-first outside the main source block")
    func renderedHelpersStayHumanFirst() throws {
        let source = try Self.shellSource()

        let implementationLeaks = [
            "healthItem(\"FINITE\"",
            "healthItem(\"HORIZON\"",
            "eyebrow: \"HORIZON READY\"",
            "eyebrow: \"PASSIVE ACQUISITION\"",
            "The package producer, not this timer",
            "selectable full Bluetooth identifier",
            "package-owned CoreBluetooth controller is unavailable",
            "package-issued observation authority",
            "fresh post-admission scan",
            "accepted Ready epoch",
            "authoritative receipt window",
            "producer's monotonic receipt window",
            "CoreBluetooth never confirmed scan readiness",
            "case .acquiring: return \"Finite acquisition\"",
            "case .readyToSeal: return \"Horizon ready\"",
            "Experiment One progress"
        ]

        for leak in implementationLeaks {
            #expect(!source.contains(leak), "Rendered rider copy still exposes implementation language: \(leak)")
        }

        #expect(source.contains("Text(\"CAPTURE PROGRESS\")"))
        #expect(source.contains("healthItem(\"DISCOVERY\""))
        #expect(source.contains("healthItem(\"SEAL\""))
        #expect(source.contains("eyebrow: \"READY TO SEAL\""))
        #expect(source.contains("case .acquiring: return \"Read-only discovery\""))
        #expect(source.contains("case .readyToSeal: return \"Ready to seal\""))
    }
'''
test = test.replace(insert_marker, extra + insert_marker, 1)
RIDER_TEST.write_text(test)

# Final authority/action contract checks across the generated source.
for identifier in (
    "es80.capture.begin-window",
    "es80.capture.confirm-setup",
    "es80.capture.complete-window",
    "es80.capture.restart-correlation",
    "es80.capture.confirm-correlated-target",
    "es80.capture.restart-rediscovery",
    "es80.capture.connect-prepared-target",
    "es80.capture.finish",
    "es80.capture.share",
    "es80.capture.view-details",
    "es80.capture.restart-experiment",
    "es80.capture.experiment-progress",
    "es80.capture.single-authority",
    "es80.capture.complete",
    "es80.capture-shell",
):
    if identifier not in shell:
        raise SystemExit(f"stable action/state identifier missing: {identifier}")

print("ES80 rider-language transform complete")
