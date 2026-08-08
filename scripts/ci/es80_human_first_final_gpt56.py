from pathlib import Path

SHELL = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
RIDER_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/ES80CaptureRiderLanguageAcceptanceTests.swift")
APP = Path("NembraApp/App/NembraApp.swift")
PREFLIGHT_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/ES80CaptureStationaryPreflightRiderLanguageAcceptanceTests.swift")


def replace_exact(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count == 0:
        raise SystemExit(f"missing {label}: {old!r}")
    return source.replace(old, new)


# First field screen: show the rider instruction, not the internal recipe token.
app = APP.read_text()
app = replace_exact(
    app,
    'detail: "Required for ES80-FINGERPRINT-v1"',
    'detail: "Keep unplugged for the whole capture"',
    "stationary preflight recipe label",
)
preflight_start = app.index("private struct ES80ExperimentOneStationaryPreflightView")
field_no_go_start = app.index("private struct ES80ExperimentOneFieldNoGoView", preflight_start)
preflight = app[preflight_start:field_no_go_start]
if "ES80-FINGERPRINT-v1" in preflight:
    raise SystemExit("raw recipe token remains on stationary preflight")
for required in (
    "Stationary preflight",
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


shell = SHELL.read_text()
replacements = [
    ('Text("EXPERIMENT ONE")', 'Text("CAPTURE PROGRESS")'),
    ('eyebrow: "FIELD AUTHORITY"', 'eyebrow: "CAPTURE LOCKED"'),
    ('"Begin OFF 1 window"', '"Begin OFF 1 check"'),
    ('Confirm only when those are your declared setup conditions for this Experiment One run.', 'Confirm only when those are the setup conditions for this Capture run.'),
    ('This records your operator declaration; it is not independent proof that the condition held continuously.', 'This records what you confirmed. Nembra cannot independently verify that the condition stayed true for the whole Capture.'),
    ('"Begin \\(phaseShortName(window)) window"', '"Begin \\(phaseShortName(window)) check"'),
    ('title: "Opening a fresh scan window"', 'title: "Starting the Bluetooth check"'),
    ('message: "Nembra is waiting for Bluetooth to become ready and scanning to begin. The observation window has not started yet."', 'message: "Nembra is waiting for Bluetooth scanning to begin. This check has not started yet."'),
    ('.accessibilityHint("Nembra is recording this bounded Bluetooth observation window.")', '.accessibilityHint("Nembra is recording this Bluetooth check.")'),
    ('remaining == 0 ? "Complete \\(phaseShortName(window)) window" : "Hold state — \\(remaining)s"', 'remaining == 0 ? "Complete \\(phaseShortName(window)) check" : "Hold state — \\(remaining)s"'),
    ('.accessibilityLabel("\\(phaseShortName(window)) observation timer")', '.accessibilityLabel("\\(phaseShortName(window)) check timer")'),
    ('? "Display guidance complete; ready to request window completion"', '? "Display guidance complete; ready to finish this check"'),
    ('.accessibilityHint("The capture system, not this display timer, decides whether the window has enough evidence.")', '.accessibilityHint("This timer is guidance only. Nembra verifies the required observation before accepting this check.")'),
    ('guidanceFootnote("This countdown is display guidance only. Nembra accepts the window only after the required observation time is recorded; tapping early cannot create evidence.")', 'guidanceFootnote("This countdown is guidance only. Nembra accepts the check only after the required observation time is recorded; finishing early cannot create a valid result.")'),
    ('eyebrow: "CORRELATION STOPPED"', 'eyebrow: "SIGNAL CHECK STOPPED"'),
    ('"Restart Experiment One"', '"Restart Capture"'),
    ('eyebrow: "NO UNIQUE TARGET"', 'eyebrow: "NO UNIQUE SIGNAL"'),
    ('No Bluetooth signal was absent in both OFF windows and repeated in both ON windows. Nembra will not guess from name, signal strength, service hints, or short IDs.', 'No single Bluetooth signal disappeared in both OFF checks and returned in both ON checks. Nembra will not guess from name, signal strength, service hints, or short IDs.'),
    ('"Repeat all four windows"', '"Repeat all four checks"'),
    ('eyebrow: "AMBIGUOUS TARGET"', 'eyebrow: "MULTIPLE MATCHES"'),
    ('More than one Bluetooth signal repeated the OFF / ON pattern. Nembra refuses to break the tie with display name, signal strength, services, or a short identifier.', 'More than one Bluetooth signal followed the same OFF / ON pattern. Nembra will not guess which one is the scooter from name, signal strength, services, or a short ID.'),
    ('title: "One target repeated twice"', 'title: "One signal matched twice"'),
    ('message: "One Bluetooth signal appeared in both ON windows and stayed absent from both OFF windows during this run. Treat it only as a correlated scooter signal, not verified scooter identity."', 'message: "One Bluetooth signal appeared in both ON checks and disappeared in both OFF checks. Treat it only as the matched scooter signal for this Capture, not permanent scooter identity."'),
    ('"Confirm correlated target"', '"Confirm scooter signal"'),
    ('eyebrow: "TARGET CONFIRMED"', 'eyebrow: "SIGNAL CONFIRMED"'),
    ('title: "Reacquiring the exact signal"', 'title: "Checking the same signal again"'),
    ('message: "A fresh scan is looking for the same Bluetooth signal that passed both OFF / ON cycles. Keep the scooter in the ON state from the final window."', 'message: "Nembra is checking for the same Bluetooth signal again. Keep the scooter ON after the final check."'),
    ('"Restart rediscovery"', '"Restart signal check"'),
    ('eyebrow: "CORRELATED TARGET"', 'eyebrow: "MATCHED SIGNAL"'),
    ('title: "Exact signal reacquired"', 'title: "Same signal found again"'),
    ('message: "The same Bluetooth signal reappeared in the fresh scan after target confirmation. This remains local correlation evidence, not permanent hardware authentication."', 'message: "The same Bluetooth signal appeared again after confirmation. This match applies only to this Capture and does not permanently identify the scooter."'),
    ('eyebrow: "PASSIVE CONNECTION"', 'eyebrow: "READ-ONLY CONNECTION"'),
    ('title: "Opening the correlated target"', 'title: "Opening the matched signal"'),
    ('message: "Nembra is connecting only to the confirmed correlated signal. This workflow remains read only and sends no scooter commands."', 'message: "Nembra is connecting only to the matched scooter signal. This Capture remains read only and sends no scooter commands."'),
    ('eyebrow: "PASSIVE DISCOVERY"', 'eyebrow: "READ-ONLY DISCOVERY"'),
    ('title: "Learning the readable surface"', 'title: "Learning what is available"'),
    ('message: "Nembra is passively discovering what this target exposes. Observation starts only after that discovery is complete."', 'message: "Nembra is learning what the matched signal exposes over Bluetooth. Observation starts only after this read-only discovery is complete."'),
    ('.accessibilityHint("Available only after Nembra accepts the required observation duration.")', '.accessibilityHint("Available only after Nembra verifies the required observation time.")'),
    ('title: "Freezing final evidence"', 'title: "Sealing Capture"'),
    ('message: "Nembra is sealing the final evidence cutoff, checking capture integrity, and preparing the final capture artifact. Do not leave the app while this finishes."', 'message: "Nembra is finishing the accepted observations, checking Capture integrity, and preparing the Capture to share. Keep Nembra open until sealing finishes."'),
    ('Text("Nembra is recording Bluetooth signals for this exact window. Keep the phone nearby and the app foregrounded; do not open the stock scooter app during this series.")', 'Text("Nembra is recording nearby Bluetooth signals for this check. Keep the phone nearby and Nembra open; do not open the stock scooter app during these four checks.")'),
    ('healthItem("TARGET", value: connection == .connected ? "BOUND" : "WAIT")', 'healthItem("SIGNAL", value: connection == .connected ? "MATCHED" : "WAIT")'),
    ('"Capture health. Target \\(connection == .connected ? \"bound\" : \"waiting\"). Passive discovery \\(observationReady ? \"ready\" : \"waiting\"). Seal \\(horizonReady ? \"ready\" : \"waiting\")."', '"Capture health. Signal \\(connection == .connected ? \"matched\" : \"waiting\"). Discovery \\(observationReady ? \"ready\" : \"waiting\"). Seal \\(horizonReady ? \"ready\" : \"waiting\")."'),
    ('Text("The exact \\(report.finalShareByteCount.formatted())-byte final Share artifact passed the final Share and nested capture integrity checks. No protocol field meaning is claimed yet.")', 'Text("The exact \\(report.finalShareByteCount.formatted())-byte Capture passed every required file-integrity check and is ready to share for analysis. Nembra has not identified scooter data fields from this file yet.")'),
    ('Text("\\(artifact.captureJSON.count.formatted()) capture bytes are sealed from this run. Analysis readiness is not earned until Nembra verifies the exact final Share bytes and their nested evidence.")', 'Text("\\(artifact.captureJSON.count.formatted()) Capture bytes are sealed. Nembra still needs to verify the final Share file before this run is ready for analysis.")'),
    ('Text("The artifact remains sealed, but post-seal Bluetooth cleanup did not complete. Preserve this capture and restart Nembra before another Experiment One run.")', 'Text("The Capture is sealed, but Bluetooth cleanup did not finish. Keep this Capture and restart Nembra before starting another one.")'),
    ('return .failed("Nembra left the active foreground after Experiment One began. This capture cannot resume safely; start a fresh Experiment One.")', 'return .failed("Nembra left the foreground after Capture began. This run cannot safely resume; start a fresh Capture.")'),
    ('return .failed(coordinator.lastDiagnostic ?? "The passive target connection ended before an accepted observation could be sealed. Start a fresh Experiment One rather than replaying consumed authority.")', 'return .failed(coordinator.lastDiagnostic ?? "The Bluetooth connection ended before observation was ready to seal. This run cannot safely continue; start a fresh Capture.")'),
    ('return .correlationFailed("The four windows did not preserve one valid OFF 1, ON 1, OFF 2, ON 2 sequence. Start again from OFF 1.")', 'return .correlationFailed("The four Bluetooth checks did not preserve the required OFF 1, ON 1, OFF 2, ON 2 order. Start again from OFF 1.")'),
    ('return .correlationFailed("This Experiment One run has no active progress and no final result. Start a fresh run.")', 'return .correlationFailed("This Capture has no active OFF / ON progress and no completed result. Start a fresh Capture.")'),
    ('return .correlationFailed("A known Bluetooth, scan-liveness, or foreground gap invalidated this four-window observation series.")', 'return .correlationFailed("A Bluetooth or foreground interruption invalidated these four OFF / ON checks. Start again from OFF 1.")'),
    ('return .failed("Simulator QA interruption fixture. This synthetic state represents a foreground-invalidated evidence life; it is not physical evidence.")', 'return .failed("Simulator QA interruption fixture. A foreground interruption invalidated this synthetic Capture run; it is not physical evidence.")'),
    ('sharePreparationWarning = "Capture is sealed, but this run has no retained operator setup declaration. Start a fresh Experiment One rather than inventing setup provenance at export time."', 'sharePreparationWarning = "Capture is sealed, but the confirmed setup is missing. Start a fresh Capture instead of trying to rebuild that setup afterward."'),
    ('sharePreparationWarning = "Capture remains sealed and ready for analysis, but the temporary Share file could not be staged: \\(experimentErrorMessage(error))"', 'sharePreparationWarning = "Capture is safe and ready for analysis, but Nembra could not prepare the Share file: \\(experimentErrorMessage(error))"'),
    ('sharePreparationWarning = "Capture remains sealed, but the exact final Share artifact did not earn analysis readiness: \\(experimentErrorMessage(error))"', 'sharePreparationWarning = "Capture is sealed, but the final Share file did not pass every required check: \\(experimentErrorMessage(error))"'),
    ('localFailureMessage = "Nembra could not create a fresh Experiment One run: \\(String(describing: error))"', 'localFailureMessage = "Nembra could not start a fresh Capture. Close this screen and try again."'),
    ('return "The correlated target is already prepared. Continue the current rediscovery."', 'return "The matched scooter signal is already prepared. Continue the current signal check."'),
    ('return "No confirmed correlated target is ready for this step."', 'return "No confirmed scooter signal is ready for this step."'),
    ('return "All four OFF / ON windows must complete before target confirmation."', 'return "Complete all four OFF / ON checks before confirming the scooter signal."'),
    ('return "The four-window evidence or ordering is invalid."', 'return "The four OFF / ON checks are invalid or out of order."'),
    ('return "The four-window series did not produce exactly one repeatable target."', 'return "The four OFF / ON checks did not produce one unique scooter signal."'),
    ('return "The exact correlated target has not reappeared in the fresh scan yet. Keep scanning and retry."', 'return "The matched scooter signal has not appeared again yet. Keep the scooter ON and retry the signal check."'),
    ('return "The exact correlated target is visible but Bluetooth reports it as non-connectable."', 'return "The matched scooter signal is visible but cannot accept a read-only Bluetooth connection."'),
    ('return "Passive Bluetooth capture is unavailable."', 'return "Bluetooth capture is unavailable in this session."'),
    ('return "Passive discovery and the minimum observation period are not complete yet."', 'return "The required observation time is not complete yet."'),
    ('return "This build has an invalid observation-window duration. Capture cannot continue."', 'return "This build has an invalid OFF / ON check duration. Capture cannot continue."'),
    ('return "All four correlation windows are already sealed."', 'return "All four OFF / ON checks are already complete."'),
    ('return "The current correlation window is already active."', 'return "This OFF / ON check is already running."'),
    ('return "No correlation window is currently active."', 'return "No OFF / ON check is currently running."'),
    ('return "Bluetooth became unavailable during this observation window."', 'return "Bluetooth became unavailable during this check."'),
    ('return "Scanning was requested, but the observation window has not opened yet."', 'return "Bluetooth scanning is starting. Keep Nembra open until this check is ready."'),
    ('return "Bluetooth did not become ready in time for this observation window."', 'return "Bluetooth did not become ready in time. Keep Nembra open and try this check again."'),
    ('return "This window\'s Bluetooth scan became inactive."', 'return "Bluetooth scanning stopped during this check."'),
    ('return "The observation window has not reached the required minimum yet."', 'return "This OFF / ON check has not recorded enough observation time yet."'),
    ('return "Nembra could not establish a valid observation window."', 'return "Nembra could not verify the required timing for this check. Restart the four OFF / ON checks."'),
    ('return "Waiting for Bluetooth to report its state."', 'return "Waiting for Bluetooth to become ready."'),
    ('return "This device does not expose the Bluetooth capability required for passive capture."', 'return "This device cannot provide the Bluetooth access required for Capture."'),
    ('return "Bluetooth permission is unavailable. Allow Nembra to use Bluetooth before starting correlation."', 'return "Bluetooth permission is unavailable. Allow Nembra to use Bluetooth before starting Capture."'),
    ('return "Bluetooth reported an unknown future state. Capture remains unavailable."', 'return "Bluetooth reported an unknown state. Capture remains unavailable."'),
    ('if presentationHasPreparedCaptureAdmission(status: status) { return "REACQUIRE" }', 'if presentationHasPreparedCaptureAdmission(status: status) { return "MATCH" }'),
    ('? "Experiment One progress, capture sealed and ready for analysis"', '? "Capture progress, sealed and ready for analysis"'),
    (': "Experiment One progress, capture sealed; final artifact integrity not yet verified"', ': "Capture progress, sealed; final file integrity not yet verified"'),
    ('return "Experiment One progress, observation ready to seal"', 'return "Capture progress, required observation complete and ready to seal"'),
    ('return "Experiment One progress, four correlation windows complete and passive observation ready"', 'return "Capture progress, four OFF / ON checks complete and read-only observation ready"'),
    ('return "Experiment One progress, \\(min(completedWindows, 4)) of 4 correlation windows complete"', 'return "Capture progress, \\(min(completedWindows, 4)) of 4 OFF / ON checks complete"'),
    ('case .complete: return "Evidence, sealed."', 'case .complete: return "Capture sealed."'),
    ('case .readyToSeal, .observing: return "Hold the evidence line."', 'case .readyToSeal, .observing: return "Keep the capture steady."'),
    ('case .acquiring, .connecting, .rediscoveringTarget, .targetReacquired: return "Bind the real signal."', 'case .acquiring, .connecting, .rediscoveringTarget, .targetReacquired: return "Confirm the scooter signal."'),
    ('default: return "Find the real scooter signal."', 'default: return "Find the scooter signal."'),
    ('case .noRepeatableTarget: return "No unique target"', 'case .noRepeatableTarget: return "No unique signal"'),
    ('case .ambiguousTargets: return "Correlation ambiguous"', 'case .ambiguousTargets: return "Multiple signal matches"'),
    ('case .correlatedTarget: return "Correlated target found"', 'case .correlatedTarget: return "Scooter signal matched"'),
    ('case .rediscoveringTarget: return "Fresh rediscovery"', 'case .rediscoveringTarget: return "Checking signal again"'),
    ('case .targetReacquired: return "Target reacquired"', 'case .targetReacquired: return "Same signal found"'),
    ('case .connecting: return "Connecting passively"', 'case .connecting: return "Opening read-only connection"'),
    ('case .acquiring: return "Passive discovery"', 'case .acquiring: return "Read-only discovery"'),
]
for old, new in replacements:
    shell = replace_exact(shell, old, new, "current rider copy")

# Visible product strings that must now remain absent. These exact phrases do not
# ban the underlying authority identifiers/types, which remain intact in code/Details.
visible_leaks = (
    'Text("EXPERIMENT ONE")',
    'eyebrow: "FIELD AUTHORITY"',
    'eyebrow: "CORRELATION STOPPED"',
    'eyebrow: "NO UNIQUE TARGET"',
    'eyebrow: "AMBIGUOUS TARGET"',
    'eyebrow: "CORRELATED TARGET"',
    'eyebrow: "PASSIVE CONNECTION"',
    'setup provenance at export time',
    'temporary Share file could not be staged',
    'did not earn analysis readiness',
    'post-seal Bluetooth cleanup',
    'another Experiment One run',
    'scan-liveness',
    'replaying consumed authority',
    'Experiment One progress',
    'Evidence, sealed.',
    'Hold the evidence line.',
    'Bind the real signal.',
    'Correlation ambiguous',
    'Fresh rediscovery',
)
for leak in visible_leaks:
    if leak in shell:
        raise SystemExit(f"rider-visible implementation language remains: {leak}")

for required in (
    'Text("CAPTURE PROGRESS")',
    'healthItem("SIGNAL", value: connection == .connected ? "MATCHED" : "WAIT")',
    'healthItem("DISCOVERY"',
    'healthItem("SEAL"',
    'eyebrow: "CAPTURE LOCKED"',
    'eyebrow: "READY TO SEAL"',
    'guard status.physicalProcedurePermitted else',
    'PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(artifact.json)',
    'finalShareIntegrityReport != nil',
    'Text("Truth boundary")',
    'CoreBluetooth',
):
    if required not in shell:
        raise SystemExit(f"required product/truth invariant missing: {required}")
SHELL.write_text(shell)


# Strengthen the acceptance contract around the actual primary, failure, recovery,
# helper, and Details regions without moving engineering truth into the rider path.
test = RIDER_TEST.read_text()
test = replace_exact(
    test,
    '            "healthItem(\\\"HORIZON\\\""\n',
    '            "healthItem(\\\"HORIZON\\\"",\n            "EXPERIMENT ONE",\n            "FIELD AUTHORITY",\n            "CORRELATION STOPPED",\n            "NO UNIQUE TARGET",\n            "AMBIGUOUS TARGET",\n            "CORRELATED TARGET",\n            "PASSIVE CONNECTION"\n',
    "primary banned phrase tail",
)
test = replace_exact(
    test,
    '        #expect(riderSurface.contains("DISCOVERY"))\n        #expect(riderSurface.contains("SEAL"))',
    '        #expect(riderSurface.contains("CAPTURE PROGRESS"))\n        #expect(riderSurface.contains("SIGNAL"))\n        #expect(riderSurface.contains("DISCOVERY"))\n        #expect(riderSurface.contains("SEAL"))',
    "required primary rider copy",
)
old_details = '''        let detailsStart = try #require(source.range(of: "private var captureDetailsSheet"))\n        let details = source[detailsStart.lowerBound..<source.endIndex]\n'''
new_details = '''        let detailsStart = try #require(source.range(of: "private var captureDetailsSheet"))\n        let detailsEnd = try #require(\n            source.range(\n                of: "private func phase(",\n                range: detailsStart.lowerBound..<source.endIndex\n            )\n        )\n        let details = source[detailsStart.lowerBound..<detailsEnd.lowerBound]\n'''
test = replace_exact(test, old_details, new_details, "Details-only truth boundary")
insert_marker = '\n    @Test("engineering truth remains available in Details instead of being deleted")'
extra = r'''

    @Test("completion, Share recovery, progress, and Bluetooth fallback copy stays rider-first")
    func recoveryAndProgressCopyStaysHumanFirst() throws {
        let source = try Self.shellSource()

        let riderVisibleLeaks = [
            "Text(\"EXPERIMENT ONE\")",
            "setup provenance at export time",
            "temporary Share file could not be staged",
            "did not earn analysis readiness",
            "post-seal Bluetooth cleanup",
            "another Experiment One run",
            "scan-liveness",
            "replaying consumed authority",
            "Experiment One progress",
            "Evidence, sealed.",
            "Hold the evidence line.",
            "Bind the real signal.",
            "Correlation ambiguous",
            "Fresh rediscovery"
        ]

        for leak in riderVisibleLeaks {
            #expect(!source.contains(leak), "Rider-visible recovery/helper copy still leaks implementation language: \(leak)")
        }

        #expect(source.contains("CAPTURE PROGRESS"))
        #expect(source.contains("Keep unplugged for the whole capture") == false)
        #expect(source.contains("Capture is safe and ready for analysis, but Nembra could not prepare the Share file"))
        #expect(source.contains("Capture progress, required observation complete and ready to seal"))
        #expect(source.contains("case .ambiguousTargets: return \"Multiple signal matches\""))
    }
'''
if insert_marker not in test:
    raise SystemExit("test insertion marker missing")
test = test.replace(insert_marker, extra + insert_marker, 1)
RIDER_TEST.write_text(test)

print("human-first Capture final transform complete")
