from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureRedTeamConvergenceSourceTests.swift"


def one(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return source.replace(old, new, 1)


def replace_in_section(source: str, start_token: str, end_token: str, old: str, new: str, label: str) -> str:
    start = source.index(start_token)
    end = source.index(end_token, start)
    prefix, section, suffix = source[:start], source[start:end], source[end:]
    section = one(section, old, new, label)
    return prefix + section + suffix


def apply() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")

    source = replace_in_section(
        source,
        "func abandonCorrelationForViewExit()",
        "func appDidLoseForeground()",
        """        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipRequestID = UUID()
""",
        """        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = "Exact scooter membership must be verified again for this Secure Link session."
        membershipRequestID = UUID()
""",
        "view-exit membership status revocation",
    )

    source = replace_in_section(
        source,
        "func appDidLoseForeground()",
        "var privateConfig: Bool",
        """func appDidLoseForeground() {
        guard !foregroundIntegrityLossHandled else { return }
""",
        """func appDidLoseForeground() {
        // Sealed accepted artifacts are immutable/shareable and no longer admit observation evidence.
        guard phase != .accepted else { return }
        guard !foregroundIntegrityLossHandled else { return }
""",
        "accepted artifact foreground guard",
    )

    source = replace_in_section(
        source,
        "func appDidLoseForeground()",
        "var privateConfig: Bool",
        """        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipRequestID = UUID()
""",
        """        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = "Exact scooter membership authority was revoked when Capture left the foreground; verify it again after returning to Capture."
        membershipRequestID = UUID()
""",
        "foreground membership status revocation",
    )

    source = replace_in_section(
        source,
        "func appDidLoseForeground()",
        "var privateConfig: Bool",
        """        guard let token = currentConnectionToken else {
""",
        """        if phase == .correlated || phase == .selected {
            // Correlation authority belongs to one uninterrupted foreground attempt. Once package
            // scanning has sealed/released, explicitly discard the correlated/selected target too.
            resetDiscoverySessionOnly()
            phase = .failed
            message = "Capture left the foreground after Bluetooth target correlation. The correlated target was invalidated; re-verify membership and restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series."
            log("foreground_integrity_lost_after_target_correlation")
            return
        }

        guard let token = currentConnectionToken else {
""",
        "post-correlation foreground invalidation",
    )

    source = one(
        source,
        """            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })
""",
        """            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { _, trusted in trusted })
""",
        "trusted event generation precedence",
    )

    ENTRYPOINT.write_text(source, encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    if not TEST.exists():
        raise SystemExit("convergence regression missing")

    required = (
        'membershipStatus = "Exact scooter membership must be verified again for this Secure Link session."',
        "guard phase != .accepted else { return }",
        'membershipStatus = "Exact scooter membership authority was revoked when Capture left the foreground; verify it again after returning to Capture."',
        "if phase == .correlated || phase == .selected",
        "resetDiscoverySessionOnly()",
        "foreground_integrity_lost_after_target_correlation",
        '"generation": String(token.diagnosticGeneration)',
        "]) { _, trusted in trusted })",
    )
    for token in required:
        if token not in source:
            raise SystemExit(f"required convergence token missing: {token}")

    if "{ current, _ in current }" in source:
        raise SystemExit("untrusted application metadata can still override Nembra generation")

    start = source.index("func appDidLoseForeground()")
    end = source.index("var privateConfig: Bool", start)
    cleanup = source[start:end]
    for forbidden in (
        "recordObservedTransportLoss",
        "endConnection(",
        "disconnectBLE",
        "writeValue",
        "publishDps",
        "queryDps",
        "releasePackageCorrelationLease(",
    ):
        if forbidden in cleanup:
            raise SystemExit(f"foreground cleanup gained forbidden authority: {forbidden}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
