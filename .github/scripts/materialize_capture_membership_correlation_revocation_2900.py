from pathlib import Path
import sys

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureMembershipCorrelationAuthorityRevocationSourceTests.swift")


def apply() -> None:
    source = APP.read_text(encoding="utf-8")
    old = '''        pendingCorrelatedTargetID = nil
        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {
            abandonPackageCorrelation()
        }
        membershipStatus = "Official SDK login changed. Exact scooter membership must be verified again."
'''
    new = '''        pendingCorrelatedTargetID = nil
        if phase == .correlated || phase == .selected {
            // Final-window sealing already retired package scanning. Account authority loss must
            // revoke target reuse without deleting the completed physical-correlation receipts.
            pendingCorrelatedTargetID = nil
            selectedID = nil
            targetCorrelationOperatorConfirmed = false
            phase = .failed
            message = "SDK account authority changed after Bluetooth target correlation. Restart from OFF1 after re-verifying exact scooter membership; completed correlation evidence remains available for diagnostics."
            log("sdk_membership_invalidated_after_target_correlation")
        }
        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {
            abandonPackageCorrelation()
        }
        membershipStatus = "Official SDK login changed. Exact scooter membership must be verified again."
'''
    if source.count(old) != 1:
        raise SystemExit(f"membership seam count={source.count(old)}")
    APP.write_text(source.replace(old, new, 1), encoding="utf-8")

    TEST.write_text('''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture membership-loss correlation authority revocation")
struct TuyaCaptureMembershipCorrelationAuthorityRevocationSourceTests {
    @Test("membership loss revokes completed target reuse without erasing sealed evidence")
    func membershipLossRevokesTargetGrantAndPreservesEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\\nprivate protocol OfficialTuyaDriver"))
        let invalidation = String(try section(in: controller, from: "func invalidateSDKMembership()", to: "func verifySDKMembership"))
        let completed = String(try section(in: invalidation, from: "if phase == .correlated || phase == .selected", to: "membershipStatus ="))
        for required in ["pendingCorrelatedTargetID = nil", "selectedID = nil", "targetCorrelationOperatorConfirmed = false", "phase = .failed", "sdk_membership_invalidated_after_target_correlation", "Restart from OFF1"] {
            #expect(completed.contains(required))
        }
        for forbidden in ["resetDiscoverySessionOnly()", "correlationProvenance = nil", "targetCorrelationMethod = nil", "targetCorrelationWindowCount = nil", "candidates.removeAll()"] {
            #expect(!completed.contains(forbidden))
        }
        #expect(invalidation.contains("abandonPackageCorrelation()"))
    }

    @Test("fresh OFF1 remains the completed-evidence reset boundary")
    func freshOFF1OwnsReset() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\\nprivate protocol OfficialTuyaDriver"))
        let begin = String(try section(in: controller, from: "private func beginCorrelationSeries()", to: "func startNextCorrelationWindow()"))
        #expect(begin.contains("resetDiscoverySessionOnly()"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { throw SourceContractError.sectionMissing }
        return source[a.lowerBound..<b.lowerBound]
    }
    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
''', encoding="utf-8")


def verify() -> None:
    source = APP.read_text(encoding="utf-8")
    a = source.index("func invalidateSDKMembership()")
    b = source.index("func verifySDKMembership", a)
    block = source[a:b]
    c = block.index("if phase == .correlated || phase == .selected")
    d = block.index("membershipStatus =", c)
    completed = block[c:d]
    for required in (
        "pendingCorrelatedTargetID = nil",
        "selectedID = nil",
        "targetCorrelationOperatorConfirmed = false",
        "phase = .failed",
        "sdk_membership_invalidated_after_target_correlation",
        "Restart from OFF1",
    ):
        if required not in completed:
            raise SystemExit(f"missing invariant: {required}")
    for forbidden in (
        "resetDiscoverySessionOnly()",
        "correlationProvenance = nil",
        "targetCorrelationMethod = nil",
        "targetCorrelationWindowCount = nil",
        "candidates.removeAll()",
    ):
        if forbidden in completed:
            raise SystemExit(f"sealed evidence erased: {forbidden}")
    if "abandonPackageCorrelation()" not in block:
        raise SystemExit("live package correlation no longer retires")
    if not TEST.exists():
        raise SystemExit("regression missing")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "verify"
    if mode == "apply":
        apply()
    elif mode == "verify":
        verify()
    else:
        raise SystemExit(mode)
