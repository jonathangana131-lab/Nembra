from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSecureLinkViewMembershipAdmissionSourceTests.swift"

PROPERTY_OLD = "    private var membershipRequestID = UUID()\n    private var officialConnectionRequestID = UUID()"
PROPERTY_NEW = "    private var membershipRequestID = UUID()\n    private var acceptsViewScopedMembershipRequests = false\n    private var officialConnectionRequestID = UUID()"

HOOK_OLD = '''    func abandonCorrelationForViewExit() {
        // Revoke every pre-radio asynchronous grant before inspecting current transport state.
        // Late membership or ledger-generation work must not start OFF1/authentication off-screen.
        membershipRequestID = UUID()
'''
HOOK_NEW = '''    func activateMembershipRequestsForView() {
        acceptsViewScopedMembershipRequests = true
    }

    func abandonCorrelationForViewExit() {
        // Close the screen-lifetime admission boundary before revoking every already-issued grant.
        // A later SwiftUI/account callback must not mint a replacement membership probe off-screen.
        acceptsViewScopedMembershipRequests = false
        membershipRequestID = UUID()
'''

VERIFY_OLD = '''    func verifySDKMembership(completion: ((Bool) -> Void)? = nil) {
        membershipAccountUID = nil
'''
VERIFY_NEW = '''    func verifySDKMembership(completion: ((Bool) -> Void)? = nil) {
        guard acceptsViewScopedMembershipRequests else {
            completion?(false)
            return
        }
        membershipAccountUID = nil
'''

TASK_OLD = '''        .task {
            sdkAccount.bootstrap()
'''
TASK_NEW = '''        .task {
            test.activateMembershipRequestsForView()
            sdkAccount.bootstrap()
'''

TEST_CONTENT = r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Secure Link view-lifetime membership admission")
struct TuyaSecureLinkViewMembershipAdmissionSourceTests {
    @Test("view exit closes admission before revoking current async grants")
    func exitClosesAdmissionBeforeGenerationRevocation() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let cleanup = String(try section(in: controller, from: "func abandonCorrelationForViewExit()", to: "var privateConfig: Bool"))

        let close = try requiredOffset(containing: "acceptsViewScopedMembershipRequests = false", in: cleanup)
        let membershipRevoke = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)
        let officialRevoke = try requiredOffset(containing: "officialConnectionRequestID = UUID()", in: cleanup)
        let activeTokenBranch = try requiredOffset(containing: "if let token = currentConnectionToken", in: cleanup)
        #expect(close < membershipRevoke)
        #expect(membershipRevoke < officialRevoke)
        #expect(officialRevoke < activeTokenBranch)
    }

    @Test("membership verification cannot mint a new probe after view exit")
    func verificationRequiresOpenViewAdmissionBeforeAnyMembershipMutation() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let verification = String(try section(in: controller, from: "func verifySDKMembership(completion:", to: "func retry()"))

        let admission = try requiredOffset(containing: "guard acceptsViewScopedMembershipRequests else", in: verification)
        let clearLease = try requiredOffset(containing: "membershipAccountUID = nil", in: verification)
        let newRequest = try requiredOffset(containing: "let requestID = UUID()", in: verification)
        #expect(admission < clearLease)
        #expect(admission < newRequest)
        #expect(verification.contains("completion?(false)"))
    }

    @Test("appearance reopens admission before account bootstrap")
    func appearanceOpensAdmissionBeforeAccountBootstrap() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = String(try section(in: source, from: "private struct SecureLinkView: View", to: "private var hero: some View"))
        let task = String(try section(in: view, from: ".task {", to: ".onDisappear {"))
        let disappear = String(try section(in: view, from: ".onDisappear {", to: ".onChange(of: sdkAccount.loggedIn)"))
        let accountChange = String(try section(in: view, from: ".onChange(of: sdkAccount.loggedIn)", to: "    }\n\n    private var hero"))

        let open = try requiredOffset(containing: "test.activateMembershipRequestsForView()", in: task)
        let bootstrap = try requiredOffset(containing: "sdkAccount.bootstrap()", in: task)
        #expect(open < bootstrap)
        #expect(disappear.contains("test.abandonCorrelationForViewExit()"))
        #expect(accountChange.contains("test.verifySDKMembership()"))
    }

    @Test("screen-lifetime fence adds no transport or physical authority")
    func lifecycleFenceIsAuthorityNeutral() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let activation = String(try section(in: controller, from: "func activateMembershipRequestsForView()", to: "func abandonCorrelationForViewExit()"))
        #expect(activation.contains("acceptsViewScopedMembershipRequests = true"))
        for forbidden in ["connectBLE", "disconnectBLE", "publishDps", "queryDps", "writeValue", "SIMCTL_CHILD_", "NEMBRA_SIMULATION_"] {
            #expect(!activation.contains(forbidden))
        }
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw SourceContractError.sectionMissing
        }
        return range.lowerBound
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

    private enum SourceContractError: Error { case sectionMissing }
}
'''


def require_count(source: str, token: str, count: int, label: str) -> None:
    actual = source.count(token)
    if actual != count:
        raise SystemExit(f"{label}: expected {count} match(es), found {actual}")


def apply() -> None:
    app = APP.read_text(encoding="utf-8")
    require_count(app, PROPERTY_OLD, 1, "membership/official request properties")
    require_count(app, HOOK_OLD, 1, "current view-exit hook")
    require_count(app, VERIFY_OLD, 1, "membership verification entry")
    require_count(app, TASK_OLD, 1, "Secure Link task")
    require_count(app, "private static var activePackageCorrelationOwner: UUID?", 1, "process package lease")
    require_count(app, "if dynamicTypeSize.isAccessibilitySize", 3, "Accessibility reflow")

    app = app.replace(PROPERTY_OLD, PROPERTY_NEW, 1)
    app = app.replace(HOOK_OLD, HOOK_NEW, 1)
    app = app.replace(VERIFY_OLD, VERIFY_NEW, 1)
    app = app.replace(TASK_OLD, TASK_NEW, 1)
    APP.write_text(app, encoding="utf-8")

    if TEST.exists():
        raise SystemExit("view-lifetime membership admission regression already exists")
    TEST.write_text(TEST_CONTENT, encoding="utf-8")


def verify() -> None:
    app = APP.read_text(encoding="utf-8")
    for token in (
        "private var acceptsViewScopedMembershipRequests = false",
        "func activateMembershipRequestsForView()",
        "guard acceptsViewScopedMembershipRequests else",
        "test.activateMembershipRequestsForView()",
        "officialConnectionRequestID = UUID()",
        "private static var activePackageCorrelationOwner: UUID?",
    ):
        if token not in app:
            raise SystemExit(f"required current lifecycle token missing: {token}")

    cleanup = app[app.index("func abandonCorrelationForViewExit()"):app.index("var privateConfig: Bool")]
    order = [
        cleanup.index("acceptsViewScopedMembershipRequests = false"),
        cleanup.index("membershipRequestID = UUID()"),
        cleanup.index("officialConnectionRequestID = UUID()"),
    ]
    if order != sorted(order):
        raise SystemExit("screen-lifetime admission must close before async request generations are revoked")

    verification = app[app.index("func verifySDKMembership(completion:"):app.index("func retry()")]
    admission = verification.index("guard acceptsViewScopedMembershipRequests else")
    if admission > verification.index("membershipAccountUID = nil") or admission > verification.index("let requestID = UUID()"):
        raise SystemExit("membership verification can mutate/mint authority before view admission")

    view_start = app.index("private struct SecureLinkView: View")
    hero = app.index("private var hero: some View", view_start)
    view = app[view_start:hero]
    task = view[view.index(".task {"):view.index(".onDisappear {")]
    if task.index("test.activateMembershipRequestsForView()") > task.index("sdkAccount.bootstrap()"):
        raise SystemExit("view admission must open before account bootstrap")

    if not TEST.exists():
        raise SystemExit("view-lifetime membership regression missing")
    test = TEST.read_text(encoding="utf-8")
    for token in (
        "exitClosesAdmissionBeforeGenerationRevocation",
        "verificationRequiresOpenViewAdmissionBeforeAnyMembershipMutation",
        "appearanceOpensAdmissionBeforeAccountBootstrap",
        "lifecycleFenceIsAuthorityNeutral",
    ):
        if token not in test:
            raise SystemExit(f"source regression missing: {token}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
