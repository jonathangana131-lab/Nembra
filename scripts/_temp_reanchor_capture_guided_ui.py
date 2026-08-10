from pathlib import Path
import subprocess

DONOR = "3090b08e4bc273548c8c3de604d255e098d49539"
PATH = "NembraApp/App/NembraCaptureEntrypoint.swift"
MARKER = "private struct SecureLinkView: View {"

current_path = Path(PATH)
current = current_path.read_text()
donor = subprocess.check_output(["git", "show", f"{DONOR}:{PATH}"], text=True)

if current.count(MARKER) != 1 or donor.count(MARKER) != 1:
    raise SystemExit("SecureLinkView boundary is not unique")

current_prefix, _ = current.split(MARKER, 1)
_, donor_tail = donor.split(MARKER, 1)

# The presentation transplant must not replace any controller/authority implementation.
for authority_token in [
    "private final class SecureLinkController",
    "func startBaseline()",
    "private func startWatchdog",
    "func prepareExport()",
    "private func makeExport",
]:
    if authority_token not in current_prefix:
        raise SystemExit(f"current truth prefix missing {authority_token}")
    if authority_token in donor_tail:
        raise SystemExit(f"donor presentation tail unexpectedly owns {authority_token}")

new_tail = MARKER + donor_tail

# The guided UI must expose the current procedure authority in Engineering Details.
old = '                LabeledContent("Source commit", value: test.fieldBuildSourceCommitSHA)\n'
new = old + '                LabeledContent("Procedure", value: test.fieldProcedureIdentifier)\n'
if new_tail.count(old) != 1:
    raise SystemExit(f"engineering source row count={new_tail.count(old)}")
new_tail = new_tail.replace(old, new, 1)

result = current_prefix + new_tail

# Product closure invariants for the visible surface.
required = [
    'Text("NEMBRA CAPTURE")',
    'private let stageLabels = ["Target", "Secure link", "Observe", "Seal"]',
    'private var primarySurface: some View',
    'Text("READY")',
    'Text("CAPTURE COMPLETE")',
    'Label("Engineering details", systemImage: "wrench.and.screwdriver")',
    'LabeledContent("Procedure", value: test.fieldProcedureIdentifier)',
    'ShareLink(item: SecureTransfer',
    'Text("Nothing was promoted after the blocker.',
    'if dynamicTypeSize.isAccessibilitySize',
    '.accessibilityLabel("Step \\(index + 1)',
]
for token in required:
    if token not in result:
        raise SystemExit(f"guided UI contract missing: {token}")

for forbidden in [
    'Text("Correlate. Authenticate. Seal.")',
    'private var statusCard: some View',
    'private var authorityCard: some View',
    'private var discoveryCard: some View',
    'private var acceptanceCard: some View',
    'private var exportCard: some View',
]:
    if forbidden in new_tail:
        raise SystemExit(f"obsolete debug-card UI survived: {forbidden}")

# Truth boundary: presentation still says no commands/raw transport and uses current controller methods only.
for token in [
    'No commands are sent.',
    'not raw FD50 bytes',
    'test.startBaseline()',
    'test.confirmCorrelatedTarget(',
    'test.authenticateSelected()',
    'test.prepareExport()',
]:
    if token not in new_tail:
        raise SystemExit(f"presentation truth contract missing: {token}")

current_path.write_text(result)
