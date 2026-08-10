from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSecureLinkViewMembershipAdmissionSourceTests.swift"

PROPERTY_OLD = "    private var membershipRequestID = UUID()\n\n    init(device: TuyaAccountBridge.LinkedDevice) {"
PROPERTY_NEW = "    private var membershipRequestID = UUID()\n    private var acceptsViewScopedMembershipRequests = false\n\n    init(device: TuyaAccountBridge.LinkedDevice) {"

EXIT_OLD = '''    func abandonCorrelationForViewExit() {
        // Revoke an in-flight membership request before checking scanner ownership. A late
        // authorized callback must never begin OFF1 after Secure Link has left the screen.
        membershipRequestID = UUID()
'''
EXIT_NEW = '''    func activateMembershipRequestsForView() {
        acceptsViewScopedMembershipRequests = true
    }

    func abandonCorrelationForViewExit() {
        // Close the view-lifetime admission boundary before revoking the current generation.
        // A later SwiftUI/account callback must not mint a replacement membership request after
        // Secure Link has left the screen.
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
    @Test("view exit closes membership admission before revoking the current request")
    func exitClosesAdmissionBeforeGenerationRevocation() throws {
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

        let closeAdmission = try requiredOffset(containing: "acceptsViewScopedMembershipRequests = false", in: cleanup)
        let revokeGeneration = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)
        let earlyReturn = try requiredOffset(
            containing: "guard processCorrelationLease != nil || correlationSession != nil else { return }",
            in: cleanup
        )
        #expect(closeAdmission < revokeGeneration)
        #expect(revokeGeneration < earlyReturn)
    }

    @Test("membership verification cannot mint a new request after the view boundary closes")
    func verificationRequiresOpenViewAdmissionBeforeAnyMembershipMutation() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let verification = String(try section(
            in: controller,
            from: "func verifySDKMembership(completion:",
            to: "func retry()"
        ))

        let admission = try requiredOffset(containing: "guard acceptsViewScopedMembershipRequests else", in: verification)
        let clearLease = try requiredOffset(containing: "membershipAccountUID = nil", in: verification)
        let newRequest = try requiredOffset(containing: "let requestID = UUID()", in: verification)
        #expect(admission < clearLease)
        #expect(admission < newRequest)
        #expect(verification.contains("completion?(false)"))
    }

    @Test("every appearance reopens admission before bootstrap can trigger membership work")
    func appearanceOpensAdmissionBeforeAccountBootstrap() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = String(try section(
            in: source,
            from: "private struct SecureLinkView: View",
            to: "private var hero: some View"
        ))
        let task = String(try section(in: view, from: ".task {", to: ".onDisappear {"))
        let disappear = String(try section(in: view, from: ".onDisappear {", to: ".onChange(of: sdkAccount.loggedIn)"))
        let loginChange = String(try section(
            in: view,
            from: ".onChange(of: sdkAccount.loggedIn)",
            to: "    }\n\n    private var hero"
        ))

        let activate = try requiredOffset(containing: "test.activateMembershipRequestsForView()", in: task)
        let bootstrap = try requiredOffset(containing: "sdkAccount.bootstrap()", in: task)
        #expect(activate < bootstrap)
        #expect(disappear.contains("test.abandonCorrelationForViewExit()"))
        #expect(loginChange.contains("test.verifySDKMembership()"))
    }

    @Test("view admission fence adds no protocol or physical authority")
    func fenceIsAppLifecycleOnly() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let activation = String(try section(
            in: controller,
            from: "func activateMembershipRequestsForView()",
            to: "func abandonCorrelationForViewExit()"
        ))
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
    require_count(app, PROPERTY_OLD, 1, "membership request property anchor")
    require_count(app, EXIT_OLD, 1, "view-exit hook anchor")
    require_count(app, VERIFY_OLD, 1, "membership verification anchor")
    require_count(app, TASK_OLD, 1, "Secure Link task anchor")
    require_count(app, "private static var activePackageCorrelationOwner: UUID?", 1, "process ownership anchor")
    require_count(app, "if dynamicTypeSize.isAccessibilitySize", 3, "current Accessibility reflow anchor")

    app = app.replace(PROPERTY_OLD, PROPERTY_NEW, 1)
    app = app.replace(EXIT_OLD, EXIT_NEW, 1)
    app = app.replace(VERIFY_OLD, VERIFY_NEW, 1)
    app = app.replace(TASK_OLD, TASK_NEW, 1)
    APP.write_text(app, encoding="utf-8")

    if TEST.exists():
        raise SystemExit("view-lifetime membership admission regression already exists")
    TEST.write_text(TEST_CONTENT, encoding="utf-8")


def verify() -> None:
    app = APP.read_text(encoding="utf-8")
    required = (
        "private var acceptsViewScopedMembershipRequests = false",
        "func activateMembershipRequestsForView()",
        "acceptsViewScopedMembershipRequests = true",
        "acceptsViewScopedMembershipRequests = false",
        "guard acceptsViewScopedMembershipRequests else",
        "test.activateMembershipRequestsForView()",
        "private static var activePackageCorrelationOwner: UUID?",
    )
    for token in required:
        if token not in app:
            raise SystemExit(f"required current lifecycle token missing: {token}")

    cleanup = app[app.index("func abandonCorrelationForViewExit()"):app.index("var privateConfig: Bool")]
    if cleanup.index("acceptsViewScopedMembershipRequests = false") > cleanup.index("membershipRequestID = UUID()"):
        raise SystemExit("view admission must close before request-generation revocation")

    verification = app[app.index("func verifySDKMembership(completion:"):app.index("func retry()")]
    admission = verification.index("guard acceptsViewScopedMembershipRequests else")
    if admission > verification.index("membershipAccountUID = nil") or admission > verification.index("let requestID = UUID()"):
        raise SystemExit("membership verification mutates/mints authority before view admission")

    task = app[app.index(".task {"):app.index(".onDisappear {")]
    if task.index("test.activateMembershipRequestsForView()") > task.index("sdkAccount.bootstrap()"):
        raise SystemExit("view admission must open before account bootstrap")

    if not TEST.exists():
        raise SystemExit("view-lifetime membership admission regression missing")
    test = TEST.read_text(encoding="utf-8")
    for token in (
        "exitClosesAdmissionBeforeGenerationRevocation",
        "verificationRequiresOpenViewAdmissionBeforeAnyMembershipMutation",
        "appearanceOpensAdmissionBeforeAccountBootstrap",
        "fenceIsAppLifecycleOnly",
    ):
        if token not in test:
            raise SystemExit(f"view-lifetime membership regression missing: {token}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
