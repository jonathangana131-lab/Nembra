from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaNavigationBLELeaseRetirementSourceTests.swift"

OLD_HOOK = '''    func abandonCorrelationForViewExit() {
        guard processCorrelationLease != nil || correlationSession != nil else { return }
        abandonPackageCorrelation()
        phase = .failed
        message = "Bluetooth correlation was interrupted when Capture left Secure Link. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series."
        log("target_correlation_abandoned_on_view_exit")
    }
'''

NEW_HOOK = '''    func abandonCorrelationForViewExit() {
        // Leaving Secure Link revokes this controller's user-intent boundary before checking
        // whether package correlation has reached scanner ownership. Both the initial OFF1
        // membership proof and the final selected-phase membership recheck use this generation.
        membershipRequestID = UUID()
        membershipBusy = false
#if canImport(ThingSmartHomeKit)
        membershipProbe = nil
#endif

        guard processCorrelationLease != nil || correlationSession != nil else { return }
        abandonPackageCorrelation()
        phase = .failed
        message = "Bluetooth correlation was interrupted when Capture left Secure Link. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series."
        log("target_correlation_abandoned_on_view_exit")
    }
'''

TEST_CONTENT = r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture navigation BLE lease retirement source contract")
struct TuyaNavigationBLELeaseRetirementSourceTests {
    @Test("leaving Secure Link revokes pending membership callbacks before any early return")
    func secureLinkNavigationExitRevokesPendingStartsAndRetiresCorrelationLease() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "func abandonCorrelationForViewExit()",
            to: "var privateConfig: Bool"
        ))
        let view = String(try section(
            in: source,
            from: "private struct SecureLinkView: View",
            to: "private extension SecureLinkView"
        ))

        let revokeRequest = try requiredLine(containing: "membershipRequestID = UUID()", in: cleanup)
        let clearBusy = try requiredLine(containing: "membershipBusy = false", in: cleanup)
        let retireProbe = try requiredLine(containing: "membershipProbe = nil", in: cleanup)
        let earlyReturn = try requiredLine(
            containing: "guard processCorrelationLease != nil || correlationSession != nil else { return }",
            in: cleanup
        )
        let abandon = try requiredLine(containing: "abandonPackageCorrelation()", in: cleanup)
        let failedState = try requiredLine(containing: "phase = .failed", in: cleanup)

        #expect(revokeRequest < earlyReturn)
        #expect(clearBusy < earlyReturn)
        #expect(retireProbe < earlyReturn)
        #expect(earlyReturn < abandon)
        #expect(abandon < failedState)
        #expect(cleanup.contains("target_correlation_abandoned_on_view_exit"))
        #expect(!cleanup.contains("releasePackageCorrelationLease()"))
        #expect(view.contains(".onDisappear"))
        #expect(view.contains("test.abandonCorrelationForViewExit()"))
    }

    @Test("membership request generation fences both OFF1 and final Tuya connection starts")
    func oneGenerationFenceCoversBothMembershipCompletionStarts() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let membership = String(try section(
            in: controller,
            from: "func verifySDKMembership(completion:",
            to: "func retry()"
        ))
        let authenticate = String(try section(
            in: controller,
            from: "func authenticate()",
            to: "private func beginOfficialConnection"
        ))
        let baseline = String(try section(
            in: controller,
            from: "func startBaseline()",
            to: "private func beginCorrelationSeries()"
        ))

        #expect(membership.contains("let requestID = UUID()"))
        #expect(membership.contains("membershipRequestID = requestID"))
        #expect(membership.contains("guard let self, self.membershipRequestID == requestID else { return }"))
        #expect(baseline.contains("verifySDKMembership"))
        #expect(baseline.contains("beginCorrelationSeries()"))
        #expect(authenticate.contains("verifySDKMembership"))
        #expect(authenticate.contains("self.beginOfficialConnection(candidate: candidate)"))
    }

    @Test("cleanup reuses transport-first package abandonment path")
    func packageTransportRetirementPrecedesLeaseRelease() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let abandon = String(try section(
            in: source,
            from: "private func abandonPackageCorrelation()",
            to: "private func releasePackageCorrelationLease()"
        ))
        let abandonLine = try requiredLine(containing: "correlationSession?.abandonCurrentWindow()", in: abandon)
        let releaseLine = try requiredLine(containing: "releasePackageCorrelationLease()", in: abandon)
        #expect(abandonLine < releaseLine)
    }

    private func requiredLine(containing token: String, in source: String) throws -> Int {
        guard let index = source.components(separatedBy: "\n").firstIndex(where: { $0.contains(token) }) else {
            Issue.record("Expected source token missing: \(token)")
            throw SourceContractError.sectionMissing
        }
        return index
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
'''


def require_count(source: str, token: str, expected: int, label: str) -> None:
    actual = source.count(token)
    if actual != expected:
        raise SystemExit(f"{label}: expected {expected} match(es), found {actual}")


def apply() -> None:
    app = APP.read_text(encoding="utf-8")
    require_count(app, OLD_HOOK, 1, "exact current view-exit hook")
    require_count(app, "private static var activePackageCorrelationOwner: UUID?", 1, "process-global ownership anchor")
    require_count(app, "if dynamicTypeSize.isAccessibilitySize", 3, "current Accessibility reflow anchor")
    app = app.replace(OLD_HOOK, NEW_HOOK, 1)
    APP.write_text(app, encoding="utf-8")

    old_test = TEST.read_text(encoding="utf-8")
    require_count(old_test, "func secureLinkNavigationExitRetiresCorrelationLease()", 1, "current navigation regression")
    require_count(old_test, "func packageTransportRetirementPrecedesLeaseRelease()", 1, "transport-order regression")
    TEST.write_text(TEST_CONTENT, encoding="utf-8")


def verify() -> None:
    app = APP.read_text(encoding="utf-8")
    cleanup = app[app.index("func abandonCorrelationForViewExit()"):app.index("var privateConfig: Bool")]
    order = [
        cleanup.index("membershipRequestID = UUID()"),
        cleanup.index("membershipBusy = false"),
        cleanup.index("membershipProbe = nil"),
        cleanup.index("guard processCorrelationLease != nil || correlationSession != nil else { return }"),
        cleanup.index("abandonPackageCorrelation()"),
        cleanup.index("phase = .failed"),
    ]
    if order != sorted(order):
        raise SystemExit("view-exit callback revocation / scanner retirement ordering regressed")
    if "releasePackageCorrelationLease()" in cleanup:
        raise SystemExit("view-exit hook must not bypass scanner-first abandonment with direct lease release")

    membership = app[app.index("func verifySDKMembership(completion:"):app.index("func retry()")]
    for token in (
        "let requestID = UUID()",
        "membershipRequestID = requestID",
        "guard let self, self.membershipRequestID == requestID else { return }",
    ):
        if token not in membership:
            raise SystemExit(f"membership callback generation fence missing: {token}")

    authenticate = app[app.index("func authenticate()"):app.index("private func beginOfficialConnection")]
    if "verifySDKMembership" not in authenticate or "self.beginOfficialConnection(candidate: candidate)" not in authenticate:
        raise SystemExit("final membership recheck no longer maps to the guarded Tuya connection start")

    test = TEST.read_text(encoding="utf-8")
    for token in (
        "secureLinkNavigationExitRevokesPendingStartsAndRetiresCorrelationLease",
        "oneGenerationFenceCoversBothMembershipCompletionStarts",
        "packageTransportRetirementPrecedesLeaseRelease",
        "#expect(revokeRequest < earlyReturn)",
        "#expect(earlyReturn < abandon)",
    ):
        if token not in test:
            raise SystemExit(f"strengthened lifecycle regression missing: {token}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
