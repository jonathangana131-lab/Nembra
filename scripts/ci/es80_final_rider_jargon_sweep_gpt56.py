from pathlib import Path

shell_path = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
test_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/ES80CapturePrimaryProgressRiderLanguageAcceptanceTests.swift")
source = shell_path.read_text()

replacements = [
    (
        "Field capture is locked for this build. OFF / ON windows, connection, capture, and sealing stay unavailable until this exact build is authorized.",
        "Field capture is locked for this build. OFF / ON checks, connection, capture, and sealing stay unavailable until this exact build is authorized."
    ),
    (
        "Set the scooter to ON, keep the stock app closed, then begin this bounded observation window.",
        "Set the scooter to ON, keep the stock app closed, then begin this Bluetooth check."
    ),
    (
        "Set the scooter fully OFF, keep the stock app closed, then begin this bounded observation window.",
        "Set the scooter fully OFF, keep the stock app closed, then begin this Bluetooth check."
    ),
    (
        "Nembra keeps target matching and passive capture in one continuous run. It never sends scooter commands and never chooses a target from its name, signal strength, or service hints.",
        "Nembra keeps signal matching and read-only capture in one continuous run. It never sends scooter commands and never chooses a signal from its name, signal strength, or service hints."
    ),
    ('"Begin passive observation"', '"Begin read-only observation"'),
    ('finalShareIntegrityReport == nil ? "Verify final artifact" : "Retry Share file"', 'finalShareIntegrityReport == nil ? "Verify Capture file" : "Retry Share file"'),
    ('case .physicalProcedureLocked: return "Field procedure locked"', 'case .physicalProcedureLocked: return "Capture locked"'),
    (
        'return "This OFF / ON series has an evidence gap. Start a fresh capture."',
        'return "These OFF / ON checks were interrupted. Start a fresh capture."'
    )
]

for old, new in replacements:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one current rider literal, found {count}: {old!r}")
    source = source.replace(old, new, 1)

for banned in (
    "OFF / ON windows, connection, capture, and sealing",
    "bounded observation window",
    "target matching and passive capture",
    '"Begin passive observation"',
    '"Verify final artifact"',
    'return "Field procedure locked"',
    "This OFF / ON series has an evidence gap."
):
    if banned in source:
        raise SystemExit(f"rider-facing jargon remains: {banned!r}")

for required in (
    "OFF / ON checks, connection, capture, and sealing",
    "then begin this Bluetooth check.",
    "signal matching and read-only capture",
    '"Begin read-only observation"',
    '"Verify Capture file"',
    'case .physicalProcedureLocked: return "Capture locked"',
    "These OFF / ON checks were interrupted. Start a fresh capture.",
    "guard status.physicalProcedurePermitted else",
    "PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(artifact.json)",
    "finalShareIntegrityReport != nil",
    "CoreBluetooth correlation uses full peripheral identity",
    "does not authenticate the physical ES80",
    "dynamicTypeSize.isAccessibilitySize",
    "LazyVGrid("
):
    if required not in source:
        raise SystemExit(f"required product/truth/accessibility invariant missing: {required!r}")

shell_path.write_text(source)

test = test_path.read_text()
marker = '\n    @Test("progress, hero, and status language stays rider-first")'
if marker not in test:
    raise SystemExit("primary rider-language insertion marker changed")

addition = r'''

    @Test("remaining field, ready, completion, and error copy avoids research jargon")
    func remainingRiderCopyStaysHumanFirst() throws {
        let source = try Self.shellSource()
        let primary = try Self.slice(
            source,
            from: "private func hero(for phase: Phase)",
            to: "private var captureDetailsSheet"
        )

        for leak in [
            "OFF / ON windows, connection, capture, and sealing",
            "bounded observation window",
            "target matching and passive capture",
            "Begin passive observation",
            "Verify final artifact",
            "Field procedure locked"
        ] {
            #expect(!primary.contains(leak), "Primary Capture copy still exposes research vocabulary: \(leak)")
        }

        #expect(primary.contains("OFF / ON checks, connection, capture, and sealing"))
        #expect(primary.contains("then begin this Bluetooth check."))
        #expect(primary.contains("signal matching and read-only capture"))
        #expect(primary.contains("Begin read-only observation"))
        #expect(primary.contains("Verify Capture file"))
        #expect(primary.contains("Capture locked"))

        #expect(!source.contains("This OFF / ON series has an evidence gap."))
        #expect(source.contains("These OFF / ON checks were interrupted. Start a fresh capture."))
    }
'''
test = test.replace(marker, addition + marker, 1)
test_path.write_text(test)

print("final rider-jargon sweep complete")
