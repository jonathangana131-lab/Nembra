from pathlib import Path

root = Path(__file__).resolve().parents[2]
path = root / "NembraApp/App/NembraCaptureEntrypoint.swift"
source = path.read_text(encoding="utf-8")

old = """    func activateMembershipRequestsForView() {\n        foregroundIntegrityLossHandled = false\n        acceptsViewScopedMembershipRequests = true\n    }\n"""
new = """    func activateMembershipRequestsForView() {\n        // A fast inactive -> active transition must not reset the duplicate-retirement fence\n        // while the exact authenticated generation from foreground loss is still terminalizing.\n        guard currentConnectionToken == nil else { return }\n        foregroundIntegrityLossHandled = false\n        acceptsViewScopedMembershipRequests = true\n    }\n"""

if source.count(old) != 1:
    raise SystemExit(f"expected exactly one foreground activation target, found {source.count(old)}")
source = source.replace(old, new, 1)
path.write_text(source, encoding="utf-8")

activation_start = source.index("    func activateMembershipRequestsForView() {")
activation_end = source.index("    func abandonCorrelationForViewExit()", activation_start)
activation = source[activation_start:activation_end]
required = [
    "guard currentConnectionToken == nil else { return }",
    "foregroundIntegrityLossHandled = false",
    "acceptsViewScopedMembershipRequests = true",
]
offsets = [activation.index(token) for token in required]
if offsets != sorted(offsets):
    raise SystemExit("foreground reactivation gate ordering is invalid")
