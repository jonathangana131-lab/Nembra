from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"

STATUS_RESET = 'membershipStatus = "Exact scooter membership must be verified again for this Secure Link session."'


def replace_once_in_section(source: str, start: str, end: str, old: str, new: str) -> str:
    start_i = source.index(start)
    end_i = source.index(end, start_i + len(start))
    section = source[start_i:end_i]
    count = section.count(old)
    if count != 1:
        raise SystemExit(f"expected one target in section {start!r}, found {count}: {old[:100]!r}")
    section = section.replace(old, new, 1)
    return source[:start_i] + section + source[end_i:]


def apply() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    if "private func revokeTargetCorrelationAuthorityForForegroundLoss()" in source:
        raise SystemExit("target-correlation foreground revocation already present")

    membership_old = """        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipRequestID = UUID()
"""
    membership_new = """        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = \"Exact scooter membership must be verified again for this Secure Link session.\"
        membershipRequestID = UUID()
"""
    source = replace_once_in_section(
        source,
        "    func abandonCorrelationForViewExit() {",
        "    func appDidLoseForeground() {",
        membership_old,
        membership_new,
    )
    source = replace_once_in_section(
        source,
        "    func appDidLoseForeground() {",
        "    var privateConfig: Bool",
        membership_old,
        membership_new,
    )

    inflight_old = """        if processCorrelationLease != nil || correlationSession != nil {
            // Existing helper stops package transport before releasing this controller's lease.
            abandonPackageCorrelation()
            phase = .failed
            message = \"Capture left the foreground during Bluetooth target correlation. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series; interrupted windows are never reusable evidence.\"
            log(\"foreground_integrity_lost_during_target_correlation\")
            return
        }

        guard let token = currentConnectionToken else {
"""
    inflight_new = """        if processCorrelationLease != nil || correlationSession != nil {
            revokeTargetCorrelationAuthorityForForegroundLoss()
            phase = .failed
            message = \"Capture left the foreground during Bluetooth target correlation. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series; interrupted windows are never reusable evidence.\"
            log(\"foreground_integrity_lost_during_target_correlation\")
            return
        }

        // A completed correlation result and operator selection are current-foreground authority,
        // not durable scooter identity. Neither may bridge a background/inactive interruption.
        if phase == .correlated || phase == .selected || correlationProvenance != nil || selectedID != nil || pendingCorrelatedTargetID != nil {
            revokeTargetCorrelationAuthorityForForegroundLoss()
            phase = .failed
            message = \"Capture left the foreground after Bluetooth target correlation. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series; the prior correlated/selected target is no longer current-attempt authority.\"
            log(\"foreground_integrity_lost_after_target_correlation\")
            return
        }

        guard let token = currentConnectionToken else {
"""
    source = replace_once_in_section(
        source,
        "    func appDidLoseForeground() {",
        "    var privateConfig: Bool",
        inflight_old,
        inflight_new,
    )

    release_marker = "    private func releasePackageCorrelationLease() {\n"
    if source.count(release_marker) != 1:
        raise SystemExit(f"release helper marker count changed: {source.count(release_marker)}")
    revocation_helper = """    private func revokeTargetCorrelationAuthorityForForegroundLoss() {
        // Scanner/session transport is always retired before its process-global package lease.
        abandonPackageCorrelation()
        correlationProvenance = nil
        targetCorrelationMethod = nil
        targetCorrelationWindowCount = nil
        targetCorrelationOperatorConfirmed = false
        byID.removeAll()
        candidates.removeAll()
        selectedID = nil
        pendingCorrelatedTargetID = nil
    }

"""
    source = source.replace(release_marker, revocation_helper + release_marker, 1)

    provenance_old = "]) { current, _ in current })"
    provenance_new = "]) { _, trusted in trusted })"
    if source.count(provenance_old) != 1:
        raise SystemExit(f"trusted provenance collision target count changed: {source.count(provenance_old)}")
    source = source.replace(provenance_old, provenance_new, 1)

    ENTRYPOINT.write_text(source, encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    view_start = source.index("    func abandonCorrelationForViewExit() {")
    fg_start = source.index("    func appDidLoseForeground() {", view_start)
    private_config = source.index("    var privateConfig: Bool", fg_start)
    view_exit = source[view_start:fg_start]
    cleanup = source[fg_start:private_config]

    for section_name, section in (("view exit", view_exit), ("foreground", cleanup)):
        for token in (
            "sdkDeviceMembershipVerified = false",
            "membershipAccountUID = nil",
            "membershipDeviceID = nil",
            STATUS_RESET,
            "membershipRequestID = UUID()",
        ):
            if token not in section:
                raise SystemExit(f"{section_name} membership revocation missing {token}")
        if not (
            section.index("sdkDeviceMembershipVerified = false")
            < section.index(STATUS_RESET)
            < section.index("membershipRequestID = UUID()")
        ):
            raise SystemExit(f"{section_name} membership status ordering is not fail-closed")

    required_cleanup = (
        "if processCorrelationLease != nil || correlationSession != nil",
        "if phase == .correlated || phase == .selected || correlationProvenance != nil || selectedID != nil || pendingCorrelatedTargetID != nil",
        "foreground_integrity_lost_during_target_correlation",
        "foreground_integrity_lost_after_target_correlation",
        "guard let token = currentConnectionToken else",
    )
    for token in required_cleanup:
        if token not in cleanup:
            raise SystemExit(f"foreground cleanup missing {token}")
    if not (
        cleanup.index(required_cleanup[0])
        < cleanup.index(required_cleanup[1])
        < cleanup.index(required_cleanup[4])
    ):
        raise SystemExit("foreground target-authority checks are misordered")

    helper_start = source.index("    private func revokeTargetCorrelationAuthorityForForegroundLoss() {")
    helper_end = source.index("    private func releasePackageCorrelationLease() {", helper_start)
    helper = source[helper_start:helper_end]
    ordered = (
        "abandonPackageCorrelation()",
        "correlationProvenance = nil",
        "targetCorrelationMethod = nil",
        "targetCorrelationWindowCount = nil",
        "targetCorrelationOperatorConfirmed = false",
        "byID.removeAll()",
        "candidates.removeAll()",
        "selectedID = nil",
        "pendingCorrelatedTargetID = nil",
    )
    offsets = []
    for token in ordered:
        if token not in helper:
            raise SystemExit(f"target-authority revocation missing {token}")
        offsets.append(helper.index(token))
    if offsets != sorted(offsets):
        raise SystemExit("target-authority revocation ordering changed")

    receiver_start = source.index("    private func receivedApplicationUpdate(")
    receiver_end = source.index("    private func startWatchdog", receiver_start)
    receiver = source[receiver_start:receiver_end]
    if "]) { current, _ in current })" in receiver:
        raise SystemExit("untrusted SDK generation still wins reserved provenance collision")
    if "]) { _, trusted in trusted })" not in receiver:
        raise SystemExit("trusted Nembra generation precedence is missing")

    forbidden = ("recordObservedTransportLoss", "endConnection(", "disconnectBLE", "writeValue", "publishDps", "queryDps")
    for token in forbidden:
        if token in cleanup:
            raise SystemExit(f"foreground loss gained forbidden transport/protocol authority: {token}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
