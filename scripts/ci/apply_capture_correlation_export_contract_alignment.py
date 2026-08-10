#!/usr/bin/env python3
from pathlib import Path

SOURCE = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCorrelationProvenanceExportSourceTests.swift")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


source = SOURCE.read_text()
source = replace_once(
    source,
    """        let selectedPeripheralID: String?\n        let targetCorrelationProvenance: CorrelationProvenance?\n        let phase: Phase\n""",
    """        let selectedPeripheralID: String?\n        let targetCorrelationMethod: String?\n        let targetCorrelationWindowCount: Int?\n        let targetCorrelationOperatorConfirmed: Bool\n        let targetCorrelationProvenance: CorrelationProvenance?\n        let phase: Phase\n""",
    "Export coarse correlation fields",
)
source = replace_once(
    source,
    """    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?\n    private var correlationProvenance: CorrelationProvenance?\n    private var driver: OfficialTuyaDriver?\n""",
    """    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?\n    private var correlationProvenance: CorrelationProvenance?\n    private var targetCorrelationMethod: String?\n    private var targetCorrelationWindowCount: Int?\n    private var targetCorrelationOperatorConfirmed = false\n    private var driver: OfficialTuyaDriver?\n""",
    "Controller coarse correlation state",
)
source = replace_once(
    source,
    """        correlationProvenance = CorrelationProvenance(result: result)\n        switch result.correlation.disposition {\n""",
    """        correlationProvenance = CorrelationProvenance(result: result)\n        targetCorrelationMethod = correlationProvenance?.method\n        targetCorrelationWindowCount = result.windows.count\n        targetCorrelationOperatorConfirmed = false\n        switch result.correlation.disposition {\n""",
    "Correlation result coarse projection",
)
source = replace_once(
    source,
    """            selectedPeripheralID: selectedID?.uuidString,\n            targetCorrelationProvenance: correlationProvenance,\n            phase: phase,\n""",
    """            selectedPeripheralID: selectedID?.uuidString,\n            targetCorrelationMethod: targetCorrelationMethod,\n            targetCorrelationWindowCount: targetCorrelationWindowCount,\n            targetCorrelationOperatorConfirmed: targetCorrelationOperatorConfirmed,\n            targetCorrelationProvenance: correlationProvenance,\n            phase: phase,\n""",
    "Export coarse correlation projection",
)
source = replace_once(
    source,
    """        correlationSession?.abandonCurrentWindow()\n        correlationSession = nil\n        correlationProvenance = nil\n        central.stopScan()\n""",
    """        correlationSession?.abandonCurrentWindow()\n        correlationSession = nil\n        correlationProvenance = nil\n        targetCorrelationMethod = nil\n        targetCorrelationWindowCount = nil\n        targetCorrelationOperatorConfirmed = false\n        central.stopScan()\n""",
    "Reset coarse correlation projection",
)
SOURCE.write_text(source)

test = TEST.read_text()
test = replace_once(
    test,
    """        #expect(source.contains(\"let targetCorrelationProvenance: CorrelationProvenance?\"))\n        #expect(source.contains(\"private var correlationProvenance: CorrelationProvenance?\"))\n""",
    """        #expect(source.contains(\"let targetCorrelationMethod: String?\"))\n        #expect(source.contains(\"let targetCorrelationWindowCount: Int?\"))\n        #expect(source.contains(\"let targetCorrelationOperatorConfirmed: Bool\"))\n        #expect(source.contains(\"let targetCorrelationProvenance: CorrelationProvenance?\"))\n        #expect(source.contains(\"private var correlationProvenance: CorrelationProvenance?\"))\n""",
    "Test coarse correlation fields",
)
test = replace_once(
    test,
    """        #expect(source.contains(\"targetCorrelationProvenance: correlationProvenance\"))\n        #expect(source.contains(\"schemaVersion: 8\"))\n""",
    """        #expect(source.contains(\"targetCorrelationMethod: targetCorrelationMethod\"))\n        #expect(source.contains(\"targetCorrelationWindowCount: targetCorrelationWindowCount\"))\n        #expect(source.contains(\"targetCorrelationOperatorConfirmed: targetCorrelationOperatorConfirmed\"))\n        #expect(source.contains(\"targetCorrelationProvenance: correlationProvenance\"))\n        #expect(source.contains(\"schemaVersion: 8\"))\n""",
    "Test coarse export projection",
)
test = replace_once(
    test,
    """        #expect(body.contains(\"correlationProvenance = nil\"))\n""",
    """        #expect(body.contains(\"correlationProvenance = nil\"))\n        #expect(body.contains(\"targetCorrelationMethod = nil\"))\n        #expect(body.contains(\"targetCorrelationWindowCount = nil\"))\n        #expect(body.contains(\"targetCorrelationOperatorConfirmed = false\"))\n""",
    "Test coarse reset",
)
TEST.write_text(test)
print("capture correlation export contract alignment staged")
