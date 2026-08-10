from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"

OLD = """        acceptsViewScopedMembershipRequests = false
        membershipRequestID = UUID()
"""

NEW = """        acceptsViewScopedMembershipRequests = false
        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipRequestID = UUID()
"""


def cleanup_section(source: str) -> str:
    start = source.index("    func abandonCorrelationForViewExit() {")
    end = source.index("    var privateConfig: Bool", start)
    return source[start:end]


def apply() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    if source.count(OLD) != 1:
        raise SystemExit(f"view-exit admission boundary changed: expected one exact target, found {source.count(OLD)}")
    section = cleanup_section(source)
    for token in ("sdkDeviceMembershipVerified = false", "membershipAccountUID = nil", "membershipDeviceID = nil"):
        if token in section:
            raise SystemExit(f"membership proof revocation already present in view-exit cleanup: {token}")
    ENTRYPOINT.write_text(source.replace(OLD, NEW, 1), encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    section = cleanup_section(source)
    ordered = [
        "acceptsViewScopedMembershipRequests = false",
        "sdkDeviceMembershipVerified = false",
        "membershipAccountUID = nil",
        "membershipDeviceID = nil",
        "membershipRequestID = UUID()",
        "officialConnectionRequestID = UUID()",
        "if let token = currentConnectionToken",
    ]
    offsets = []
    for token in ordered:
        if token not in section:
            raise SystemExit(f"view-exit membership revocation token missing: {token}")
        offsets.append(section.index(token))
    if offsets != sorted(offsets) or len(set(offsets)) != len(offsets):
        raise SystemExit("view-exit membership revocation ordering is not fail-closed")
    forbidden = ("disconnectBLE", "endConnection(", "publishDps", "queryDps", "writeValue")
    for token in forbidden:
        if token in section:
            raise SystemExit(f"forbidden physical/protocol authority added to view-exit cleanup: {token}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
