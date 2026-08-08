from pathlib import Path

shell_path = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
test_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/ES80CaptureRiderLanguageAcceptanceTests.swift")
workflow_path = Path(".github/workflows/es80-v14-current-primary-language.yml")
self_path = Path("scripts/ci/tmp_es80_primary_language_polish.py")

source = shell_path.read_text(encoding="utf-8")
tests = test_path.read_text(encoding="utf-8")

replacements = [
    ('Text("EXPERIMENT ONE")', 'Text("CAPTURE STEPS")'),
    ('eyebrow: "FIELD AUTHORITY"', 'eyebrow: "FIELD STATUS"'),
    ('title: "This build is not authorized"', 'title: "Field capture unavailable"'),
    ('eyebrow: "PREFLIGHT / DECLARATION"', 'eyebrow: "SETUP"'),
    ('Before OFF 1, unplug the scooter charger, keep Nembra foregrounded with the screen unlocked, and keep the stock scooter app closed. Confirm only when those are your declared setup conditions for this Experiment One run.', 'Before OFF 1, unplug the scooter charger, keep Nembra open with the screen unlocked, and keep the stock scooter app closed. Confirm only when those are the setup conditions for this capture.'),
    ('This records your operator declaration; it is not independent proof that the condition held continuously.', 'This records the setup you confirmed. Nembra cannot independently verify that every condition stayed true for the whole capture.'),
    ('eyebrow: "CORRELATION STOPPED"', 'eyebrow: "MATCHING STOPPED"'),
    ('"Restart Experiment One"', '"Restart capture"'),
    ('eyebrow: "AMBIGUOUS TARGET"', 'eyebrow: "MULTIPLE MATCHES"'),
    ('"Confirm correlated target"', '"Confirm scooter signal"'),
    ('eyebrow: "CORRELATED TARGET"', 'eyebrow: "SCOOTER SIGNAL"'),
    ('title: "Exact signal reacquired"', 'title: "Scooter signal reacquired"'),
    ('"Restart rediscovery"', '"Try signal again"'),
    ('eyebrow: "PASSIVE CONNECTION"', 'eyebrow: "READ-ONLY CONNECTION"'),
    ('title: "Opening the correlated target"', 'title: "Opening the scooter signal"'),
    ('eyebrow: "PASSIVE DISCOVERY"', 'eyebrow: "READ-ONLY DISCOVERY"'),
    ('"Start a fresh Experiment One"', '"Start fresh capture"'),
    ('begin this bounded observation window.', 'begin this capture window.'),
    ('finalShareIntegrityReport == nil ? "Verify final artifact" : "Retry Share file"', 'finalShareIntegrityReport == nil ? "Verify Share file" : "Retry Share file"'),
    ('The artifact remains sealed, but post-seal Bluetooth cleanup did not complete. Preserve this capture and restart Nembra before another Experiment One run.', 'Capture remains sealed, but Bluetooth cleanup after sealing did not complete. Preserve this capture and restart Nembra before another capture.'),
    ('? "Experiment One progress, capture sealed and ready for analysis"', '? "Capture progress, sealed and ready for analysis"'),
    (': "Experiment One progress, capture sealed; final artifact integrity not yet verified"', ': "Capture progress, sealed; final Share integrity not yet verified"'),
    ('return "Experiment One progress, observation ready to seal"', 'return "Capture progress, observation ready to seal"'),
    ('return "Experiment One progress, four correlation windows complete and passive observation ready"', 'return "Capture progress, four OFF / ON windows complete and read-only observation ready"'),
    ('return "Experiment One progress, \\(min(completedWindows, 4)) of 4 correlation windows complete"', 'return "Capture progress, \\(min(completedWindows, 4)) of 4 OFF / ON windows complete"'),
    ('case .complete: return "Evidence, sealed."', 'case .complete: return "Capture sealed."'),
    ('case .readyToSeal, .observing: return "Hold the evidence line."', 'case .readyToSeal, .observing: return "Keep the scooter steady."'),
    ('case .acquiring, .connecting, .rediscoveringTarget, .targetReacquired: return "Bind the real signal."', 'case .acquiring, .connecting, .rediscoveringTarget, .targetReacquired: return "Confirm the scooter signal."'),
    ('default: return "Find the real scooter signal."', 'default: return "Find the scooter signal."'),
    ('case .physicalProcedureLocked: return "Field procedure locked"', 'case .physicalProcedureLocked: return "Field capture unavailable"'),
    ('case .bluetoothUnavailable: return "Preflight required"', 'case .bluetoothUnavailable: return "Bluetooth setup required"'),
    ('case .ambiguousTargets: return "Correlation ambiguous"', 'case .ambiguousTargets: return "More than one target"'),
    ('case .correlatedTarget: return "Correlated target found"', 'case .correlatedTarget: return "Scooter signal found"'),
    ('case .rediscoveringTarget: return "Fresh rediscovery"', 'case .rediscoveringTarget: return "Reacquiring signal"'),
    ('case .targetReacquired: return "Target reacquired"', 'case .targetReacquired: return "Scooter signal reacquired"'),
    ('case .connecting: return "Connecting passively"', 'case .connecting: return "Opening read-only connection"'),
    ('case .acquiring: return "Passive discovery"', 'case .acquiring: return "Read-only discovery"'),
]

for old, new in replacements:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one match, got {count}: {old}")
    source = source.replace(old, new, 1)

# Keep engineering vocabulary available in Details; only reject exact retired rider/UI literals.
anchor = '    @Test("primary failure copy stays rider-readable and never dumps implementation errors")\n'
new_test = '''    @Test("primary labels stay product-readable outside Engineering Details")
    func primaryLabelsStayProductReadable() throws {
        let source = try Self.shellSource()
        let riderSurface = try Self.riderSurface(in: source)

        let retiredPrimaryLabels = [
            "EXPERIMENT ONE",
            "FIELD AUTHORITY",
            "This build is not authorized",
            "PREFLIGHT / DECLARATION",
            "CORRELATION STOPPED",
            "AMBIGUOUS TARGET",
            "Confirm correlated target",
            "CORRELATED TARGET",
            "Exact signal reacquired",
            "Restart rediscovery",
            "PASSIVE CONNECTION",
            "PASSIVE DISCOVERY",
            "Start a fresh Experiment One"
        ]

        for phrase in retiredPrimaryLabels {
            #expect(!riderSurface.contains(phrase), "Primary Capture label regressed: \\(phrase)")
        }

        let retiredWholeShellLiterals = [
            "Experiment One progress,",
            "Evidence, sealed.",
            "Hold the evidence line.",
            "Bind the real signal.",
            "Find the real scooter signal.",
            "Field procedure locked",
            "Correlation ambiguous",
            "Fresh rediscovery",
            "Connecting passively"
        ]
        for phrase in retiredWholeShellLiterals {
            #expect(!source.contains(phrase), "Rider-facing helper copy regressed: \\(phrase)")
        }

        #expect(riderSurface.contains("CAPTURE STEPS"))
        #expect(riderSurface.contains("FIELD STATUS"))
        #expect(riderSurface.contains("SETUP"))
        #expect(riderSurface.contains("READ-ONLY CONNECTION"))
        #expect(riderSurface.contains("READ-ONLY DISCOVERY"))
        #expect(source.contains("Capture progress,"))
    }

'''
if tests.count(anchor) != 1:
    raise SystemExit("acceptance insertion anchor moved")
tests = tests.replace(anchor, new_test + anchor, 1)

# Product guard: preserve stable truth mechanics/actions and the technical Details boundary.
rider_marker = "    private var captureDetailsSheet: some View {"
if source.count(rider_marker) != 1:
    raise SystemExit("captureDetailsSheet boundary moved")
rider, details_tail = source.split(rider_marker, 1)
for retired in [
    'Text("EXPERIMENT ONE")', 'eyebrow: "FIELD AUTHORITY"',
    'eyebrow: "PREFLIGHT / DECLARATION"', 'eyebrow: "CORRELATION STOPPED"',
    'eyebrow: "AMBIGUOUS TARGET"', '"Confirm correlated target"',
    'eyebrow: "CORRELATED TARGET"', '"Restart rediscovery"',
    'eyebrow: "PASSIVE CONNECTION"', 'eyebrow: "PASSIVE DISCOVERY"',
    '"Start a fresh Experiment One"'
]:
    if retired in rider:
        raise SystemExit(f"retired rider label remains: {retired}")

for required in [
    "PASSIVE / READ ONLY", "CAPTURE STEPS", "FIELD STATUS", "SETUP",
    "Scooter OFF", "Scooter ON", "READ-ONLY CONNECTION", "READ-ONLY DISCOVERY",
    "Share Capture", "View Details", "es80.capture.confirm-correlated-target",
    "es80.capture.finish", "es80.capture.share", "es80.capture.view-details"
]:
    if required not in rider:
        raise SystemExit(f"required rider truth/action missing: {required}")

details = rider_marker + details_tail
for required in [
    "Experiment One", "Truth boundary", "CoreBluetooth", "Software Export SHA-256",
    "Runtime executable SHA-256", "does not authenticate the physical ES80"
]:
    if required not in details:
        raise SystemExit(f"engineering detail unexpectedly removed: {required}")

shell_path.write_text(source, encoding="utf-8")
test_path.write_text(tests, encoding="utf-8")
for p in (workflow_path, self_path):
    if p.exists():
        p.unlink()
