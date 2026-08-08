from pathlib import Path

shell_path = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
test_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/ES80CaptureRiderLanguageAcceptanceTests.swift")
invalid_workflow = Path(".github/workflows/es80-v14-rider-copy-second-pass.yml")
runner_workflow = Path(".github/workflows/es80-v14-rider-copy-second-pass-runner.yml")
self_path = Path("scripts/ci/tmp_es80_rider_copy_second_pass.py")

source = shell_path.read_text(encoding="utf-8")
tests = test_path.read_text(encoding="utf-8")

replacements = [
    ('Text("EXPERIMENT ONE")', 'Text("CAPTURE STEPS")', 1),
    ('eyebrow: "FIELD AUTHORITY"', 'eyebrow: "FIELD STATUS"', 1),
    ('title: "This build is not authorized"', 'title: "Field capture unavailable"', 1),
    ('eyebrow: "PREFLIGHT / DECLARATION"', 'eyebrow: "SETUP"', 1),
    ('Before OFF 1, unplug the scooter charger, keep Nembra foregrounded with the screen unlocked, and keep the stock scooter app closed. Confirm only when those are your declared setup conditions for this Experiment One run.', 'Before OFF 1, unplug the scooter charger, keep Nembra open with the screen unlocked, and keep the stock scooter app closed. Confirm only when those are the setup conditions for this capture.', 1),
    ('This records your operator declaration; it is not independent proof that the condition held continuously.', 'This records the setup you confirmed. Nembra cannot independently verify that every condition stayed true for the whole capture.', 1),
    ('eyebrow: "CORRELATION STOPPED"', 'eyebrow: "MATCHING STOPPED"', 1),
    ('"Restart Experiment One"', '"Restart capture"', 1),
    ('eyebrow: "AMBIGUOUS TARGET"', 'eyebrow: "MULTIPLE MATCHES"', 1),
    ('"Confirm correlated target"', '"Confirm scooter signal"', 1),
    ('eyebrow: "CORRELATED TARGET"', 'eyebrow: "SCOOTER SIGNAL"', 1),
    ('title: "Exact signal reacquired"', 'title: "Scooter signal reacquired"', 1),
    ('"Restart rediscovery"', '"Try signal again"', 1),
    ('eyebrow: "PASSIVE CONNECTION"', 'eyebrow: "READ-ONLY CONNECTION"', 1),
    ('title: "Opening the correlated target"', 'title: "Opening the scooter signal"', 1),
    ('eyebrow: "PASSIVE ACQUISITION"', 'eyebrow: "READ-ONLY DISCOVERY"', 1),
    ('eyebrow: "HORIZON READY"', 'eyebrow: "CAPTURE READY"', 1),
    ('title: "Freezing immutable evidence"', 'title: "Sealing Capture"', 1),
    ('"Start a fresh Experiment One"', '"Start fresh capture"', 1),
    ('begin this bounded observation window.', 'begin this capture window.', 1),
    ('Nembra is recording this bounded Bluetooth observation window.', 'Nembra is recording nearby Bluetooth signals for this window.', 1),
    ('healthItem("FINITE", value: observationReady ? "READY" : "WAIT")', 'healthItem("DISCOVERY", value: observationReady ? "READY" : "WAIT")', 1),
    ('healthItem("HORIZON", value: horizonReady ? "READY" : "HOLD")', 'healthItem("TIME", value: horizonReady ? "READY" : "HOLD")', 1),
    ('The exact \\(report.finalShareByteCount.formatted())-byte Share Capture file passed every required integrity check. No protocol field meaning is claimed yet.', 'Share Capture passed every required integrity check and is ready for analysis. No protocol field meaning is claimed yet.', 1),
    ('\\(artifact.captureJSON.count.formatted()) capture bytes are sealed. Ready for analysis appears only after Nembra verifies the exact final Share file and its nested evidence.', 'Capture is sealed. Nembra is verifying the final Share file before analysis is enabled.', 1),
    ('The artifact remains sealed, but post-seal Bluetooth cleanup did not complete. Preserve this capture and restart Nembra before another Experiment One run.', 'Capture remains sealed, but Bluetooth cleanup after sealing did not complete. Preserve this capture and restart Nembra before another capture.', 1),
    ('finalShareIntegrityReport == nil ? "Verify final artifact" : "Retry Share file"', 'finalShareIntegrityReport == nil ? "Verify Share file" : "Retry Share file"', 1),
    ('Nembra left the active foreground after Experiment One began. This evidence life cannot regain capture authority; start a fresh Experiment One.', 'Nembra left the foreground after capture began. This capture cannot safely resume; start a fresh capture.', 1),
    ('The passive target connection ended before an accepted observation could be sealed. Start a fresh Experiment One rather than replaying consumed authority.', 'The read-only connection ended before observation could be sealed. Start a fresh capture instead of resuming this run.', 1),
    ('The package-owned CoreBluetooth controller is unavailable for this coordinator.', 'Bluetooth capture became unavailable. Check Bluetooth and start a fresh capture.', 1),
    ('The four windows did not preserve one valid package-issued observation authority and required OFF 1, ON 1, OFF 2, ON 2 ordering.', 'The four windows did not preserve one valid OFF 1, ON 1, OFF 2, ON 2 sequence. Restart from OFF 1.', 1),
    ('The package-owned Experiment One workflow has no active correlation progress and no final result.', 'This capture has no active OFF / ON progress. Start a fresh capture.', 1),
    ('A known Bluetooth, scan-liveness, or foreground gap invalidated this four-window observation series.', 'A Bluetooth, scanning, or foreground interruption invalidated this four-window sequence. Restart from OFF 1.', 1),
    ('Nembra could not create a fresh package-owned Experiment One workflow: \\(String(describing: error))', 'Nembra could not start a fresh capture: \\(String(describing: error))', 1),
    ('The package-owned physical execution gate is closed for this build.', 'Field capture is locked for this build.', 1),
    ('Foreground integrity was lost after Experiment One began. Start a fresh experiment.', 'Nembra left the foreground after capture began. Start a fresh capture.', 1),
    ('The correlated-target admission is already prepared. Continue the current rediscovery.', 'The scooter signal is already confirmed. Continue reacquiring the same signal.', 1),
    ('No sealed correlated-target admission is ready for this step.', 'Confirm one scooter signal before continuing.', 1),
    ('The four-window evidence authority or ordering is invalid.', 'The four OFF / ON windows are incomplete or out of order. Restart from OFF 1.', 1),
    ('The exact correlated target has not reappeared in the fresh post-admission scan yet. Keep scanning and retry.', 'The matched scooter signal has not reappeared yet. Keep the scooter ON and try again.', 1),
    ('The exact correlated target is visible but CoreBluetooth reports it as non-connectable.', 'The matched scooter signal is visible but cannot be opened for read-only observation.', 1),
    ('The package-owned passive capture controller is unavailable.', 'Bluetooth capture is unavailable. Check Bluetooth and start again.', 1),
    ('The accepted Ready epoch and minimum monotonic observation interval are not complete yet.', 'Discovery or the required observation time is not complete yet.', 1),
    ('This Experiment One artifact is already immutable.', 'This capture is already sealed.', 1),
    ('The accepted correlation-window duration is invalid in this build.', 'This build has an invalid capture-window duration.', 1),
    ('All four correlation windows are already sealed.', 'All four OFF / ON windows are already complete.', 1),
    ('This correlation series was invalidated by a known evidence gap.', 'This OFF / ON sequence was interrupted. Restart from OFF 1.', 1),
    ('The current correlation window is already active.', 'This capture window is already active.', 1),
    ('No correlation window is currently active.', 'No capture window is currently active.', 1),
    ('Bluetooth became unavailable during the bounded window.', 'Bluetooth became unavailable during this window.', 1),
    ('Scanning was requested, but the authoritative receipt window has not opened yet.', 'Bluetooth scanning is still starting. Keep Nembra open.', 1),
    ('CoreBluetooth never confirmed scan readiness inside the bounded startup interval.', 'Bluetooth scanning did not become ready in time. Start the window again.', 1),
    ("The exact window's CoreBluetooth scan became inactive.", 'Bluetooth scanning stopped during this window. Restart from OFF 1.', 1),
    ("The producer's monotonic receipt window has not reached the required minimum yet.", 'Keep the scooter in this state a little longer.', 1),
    ('The producer could not establish a monotonic observation window.', 'Nembra could not verify capture timing. Restart from OFF 1.', 1),
    ('The local observation-window sequence was exhausted.', 'All capture windows have already been used.', 1),
    ('The package-owned Bluetooth controller has not been instantiated for this build.', 'Bluetooth is starting. Keep Nembra open.', 1),
    ('Waiting for CoreBluetooth to report its state.', 'Waiting for Bluetooth status.', 1),
    ('CoreBluetooth reported an unknown future state. Capture remains unavailable.', 'Bluetooth reported an unexpected state. Capture remains unavailable.', 1),
    ('return "H READY"', 'return "SEAL"', 1),
    ('return "ACQUIRE"', 'return "DISCOVER"', 1),
    ('return "Experiment One progress, capture sealed and ready for analysis"', 'return "Capture progress, sealed and ready for analysis"', 1),
    ('return "Experiment One progress, capture sealed; final artifact integrity not yet verified"', 'return "Capture progress, sealed; final Share integrity not yet verified"', 1),
    ('return "Experiment One progress, observation Horizon ready to seal"', 'return "Capture progress, required observation complete and ready to seal"', 1),
    ('return "Experiment One progress, four correlation windows complete and passive observation ready"', 'return "Capture progress, four OFF / ON windows complete and read-only observation ready"', 1),
    ('return "Experiment One progress, \\(min(completedWindows, 4)) of 4 correlation windows complete"', 'return "Capture progress, \\(min(completedWindows, 4)) of 4 OFF / ON windows complete"', 1),
    ('case .complete: return "Evidence, sealed."', 'case .complete: return "Capture sealed."', 1),
    ('case .readyToSeal, .observing: return "Hold the evidence line."', 'case .readyToSeal, .observing: return "Keep the scooter steady."', 1),
    ('case .acquiring, .connecting, .rediscoveringTarget, .targetReacquired: return "Bind the real signal."', 'case .acquiring, .connecting, .rediscoveringTarget, .targetReacquired: return "Confirm the scooter signal."', 1),
    ('default: return "Find the real scooter signal."', 'default: return "Find the scooter signal."', 1),
    ('case .physicalProcedureLocked: return "Field procedure locked"', 'case .physicalProcedureLocked: return "Field capture unavailable"', 1),
    ('case .bluetoothUnavailable: return "Preflight required"', 'case .bluetoothUnavailable: return "Bluetooth setup required"', 1),
    ('case .correlationFailed, .failed: return "Evidence stopped"', 'case .correlationFailed, .failed: return "Capture stopped"', 1),
    ('case .ambiguousTargets: return "Correlation ambiguous"', 'case .ambiguousTargets: return "More than one target"', 1),
    ('case .correlatedTarget: return "Correlated target found"', 'case .correlatedTarget: return "Scooter signal found"', 1),
    ('case .rediscoveringTarget: return "Fresh rediscovery"', 'case .rediscoveringTarget: return "Reacquiring signal"', 1),
    ('case .targetReacquired: return "Target reacquired"', 'case .targetReacquired: return "Scooter signal reacquired"', 1),
    ('case .connecting: return "Connecting passively"', 'case .connecting: return "Opening read-only connection"', 1),
    ('case .acquiring: return "Finite acquisition"', 'case .acquiring: return "Read-only discovery"', 1),
    ('case .readyToSeal: return "Horizon ready"', 'case .readyToSeal: return "Ready to seal"', 1),
    ('case .finalizing: return "Sealing artifact"', 'case .finalizing: return "Sealing capture"', 1),
]

for old, new, expected in replacements:
    count = source.count(old)
    if count != expected:
        raise SystemExit(f"expected {expected} match(es), got {count}: {old}")
    source = source.replace(old, new, expected)

marker = '            "package-owned outer, SoftwareExport, and immutable Capture integrity checks"\n        ]'
expanded = '            "package-owned outer, SoftwareExport, and immutable Capture integrity checks",\n            "EXPERIMENT ONE",\n            "Experiment One",\n            "HORIZON READY",\n            "FINITE",\n            "bounded observation window",\n            "package producer",\n            "package accepts the required monotonic observation duration"\n        ]'
if tests.count(marker) != 1:
    raise SystemExit("acceptance phrase-list marker moved")
tests = tests.replace(marker, expanded, 1)

anchor = '    @Test("language cleanup cannot weaken physical lock, evidence authority, or stable UI actions")\n'
runtime_test = '''    @Test("runtime recovery copy stays rider-readable")
    func runtimeRecoveryCopyStaysHumanFirst() throws {
        let source = try Self.shellSource()
        let retiredRuntimeCopy = [
            "The package-owned CoreBluetooth controller is unavailable for this coordinator.",
            "The package-owned Experiment One workflow has no active correlation progress and no final result.",
            "The package-owned physical execution gate is closed for this build.",
            "Foreground integrity was lost after Experiment One began. Start a fresh experiment.",
            "The exact correlated target has not reappeared in the fresh post-admission scan yet. Keep scanning and retry.",
            "CoreBluetooth never confirmed scan readiness inside the bounded startup interval.",
            "The producer's monotonic receipt window has not reached the required minimum yet.",
            "Nembra could not create a fresh package-owned Experiment One workflow:"
        ]

        for phrase in retiredRuntimeCopy {
            #expect(!source.contains(phrase), "Runtime rider copy regressed to engineering vocabulary: \\(phrase)")
        }
    }

'''
if tests.count(anchor) != 1:
    raise SystemExit("runtime acceptance insertion anchor moved")
tests = tests.replace(anchor, runtime_test + anchor, 1)

rider_marker = "    private var captureDetailsSheet: some View {"
if source.count(rider_marker) != 1:
    raise SystemExit("details boundary moved")
rider = source.split(rider_marker, 1)[0]
for phrase in [
    "EXPERIMENT ONE", "Experiment One", "HORIZON READY", "FINITE",
    "bounded observation window", "package producer",
    "package accepts the required monotonic observation duration",
    "full CoreBluetooth identifier", "accepted Horizon authority",
    "immutable JSON artifact"
]:
    if phrase in rider:
        raise SystemExit(f"engineering phrase remains in primary surface: {phrase}")

for required in [
    "CAPTURE STEPS", "DISCOVERY", "TIME", "CAPTURE READY", "Sealing Capture",
    "PASSIVE / READ ONLY", "Share Capture", "View Details",
    "es80.capture.begin-window", "es80.capture.finish", "es80.capture.share"
]:
    if required not in rider:
        raise SystemExit(f"required product contract missing: {required}")

details = rider_marker + source.split(rider_marker, 1)[1]
for required in [
    "Truth boundary", "CoreBluetooth", "Software Export SHA-256",
    "Runtime executable SHA-256", "does not authenticate the physical ES80"
]:
    if required not in details:
        raise SystemExit(f"engineering detail missing: {required}")

shell_path.write_text(source, encoding="utf-8")
test_path.write_text(tests, encoding="utf-8")
for path in [invalid_workflow, runner_workflow, self_path]:
    if path.exists():
        path.unlink()
