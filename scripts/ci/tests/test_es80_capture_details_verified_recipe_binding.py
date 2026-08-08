#!/usr/bin/env python3
from pathlib import Path

SOURCE = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
text = SOURCE.read_text(encoding="utf-8")

# The details surface describes the exact verified final Share artifact once analysis readiness
# exists. Its recipe value must therefore come from the integrity report that verified those bytes,
# not from an independently consulted current field-gate constant.
assert 'detailRow("Recipe", value: PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue)' not in text, (
    "Capture Details still reports Recipe from the current field-gate constant instead of the verified artifact"
)
assert "report.experimentRecipeID.rawValue" in text, (
    "Capture Details must render the verified final-share recipe from finalShareIntegrityReport"
)

# Preserve the exact verified provenance rows already exposed to the operator.
for required in (
    'digestDetailRow("Final Share SHA-256", value: report.finalShareSHA256)',
    'detailRow("Procedure", value: report.procedureVersion)',
    'detailRow("Build instance", value: report.buildInstanceID)',
    'detailRow("Source commit", value: report.softwareExport.sourceCommitSHA)',
):
    assert required in text, f"missing exact verified Details provenance row: {required}"

print("PASS: Capture Details recipe is bound to the exact verified final-share report")
