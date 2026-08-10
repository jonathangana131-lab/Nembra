from __future__ import annotations

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFailedPrerequisiteRecoverySourceTests.swift"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one source match, found {count}")
    return text.replace(old, new, 1)


def apply() -> None:
    text = APP.read_text(encoding="utf-8")

    text = replace_once(
        text,
        "        case .failed:\n            failurePanel\n",
        "        case .failed:\n"
        "            if !test.fieldBuildIsAuthoritative || !test.privateConfig {\n"
        "                VStack(spacing: 16) {\n"
        "                    failureRecoveryContextPanel\n"
        "                    preflightPanel\n"
        "                }\n"
        "            } else if !sdkAccount.loggedIn || !test.sdkAccountLoggedIn {\n"
        "                VStack(spacing: 16) {\n"
        "                    failureRecoveryContextPanel\n"
        "                    sdkAuthorizationPanel\n"
        "                }\n"
        "            } else if !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {\n"
        "                VStack(spacing: 16) {\n"
        "                    failureRecoveryContextPanel\n"
        "                    preflightPanel\n"
        "                }\n"
        "            } else {\n"
        "                failurePanel\n"
        "            }\n",
        "failed-state routing",
    )

    marker = "    private var failurePanel: some View {\n"
    recovery = """    private var failureRecoveryContextPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 10) {
                Label("Capture paused", systemImage: "exclamationmark.circle")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)
                Text(test.message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Restore the missing prerequisite below. The failed attempt is not reused as evidence.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

"""
    text = replace_once(text, marker, recovery + marker, "failure recovery panel")

    start = text.index("    private var failurePanel: some View {")
    end = text.index("    private var completionPanel: some View {", start)
    failure = text[start:end]
    failure = replace_once(
        failure,
        "                    Button {\n                        test.startBaseline()\n                    } label: {",
        "                    Button {\n                        test.retry()\n                    } label: {",
        "failure retry action",
    )
    failure = replace_once(
        failure,
        "                    .controlSize(.large)\n",
        "                    .controlSize(.large)\n"
        "                    .disabled(!authorityReady || test.membershipBusy)\n",
        "failure retry enablement",
    )
    text = text[:start] + failure + text[end:]

    controller_anchor = "    func consumeCorrelationAsyncInvalidation() {\n"
    retry = """    func retry() {
        guard phase == .failed, canRestartFromFreshOFF1 else {
            message = "This failed attempt still retains session authority. Relaunch Capture before another OFF1 attempt."
            log("in_process_retry_rejected")
            return
        }
        startBaseline()
    }

"""
    text = replace_once(text, controller_anchor, retry + controller_anchor, "controller retry")
    APP.write_text(text, encoding="utf-8")

    TEST.write_text(
        '''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture failed-prerequisite recovery")
struct TuyaFailedPrerequisiteRecoverySourceTests {
    @Test("failed product state routes to the missing prerequisite surface")
    func failedStateRoutesToRecovery() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(in: app, from: "private var primarySurface: some View", to: "private var preflightPanel: some View")
        #expect(surface.contains("!test.fieldBuildIsAuthoritative || !test.privateConfig"))
        #expect(surface.contains("!sdkAccount.loggedIn || !test.sdkAccountLoggedIn"))
        #expect(surface.contains("sdkAuthorizationPanel"))
        #expect(surface.contains("!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized"))
        #expect(surface.contains("failureRecoveryContextPanel"))
    }

    @Test("in-process retry consumes controller-owned restart authority")
    func retryUsesControllerAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("func retry()"))
        #expect(app.contains("guard phase == .failed, canRestartFromFreshOFF1 else"))
        let failure = try section(in: app, from: "private var failurePanel: some View", to: "private var completionPanel: some View")
        #expect(failure.contains("test.retry()"))
        #expect(failure.contains(".disabled(!authorityReady || test.membershipBusy)"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
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
''',
        encoding="utf-8",
    )


def verify() -> None:
    app = APP.read_text(encoding="utf-8")
    required = [
        "private var failureRecoveryContextPanel: some View",
        "!test.fieldBuildIsAuthoritative || !test.privateConfig",
        "!sdkAccount.loggedIn || !test.sdkAccountLoggedIn",
        "!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized",
        "func retry()",
        "guard phase == .failed, canRestartFromFreshOFF1 else",
        "test.retry()",
        ".disabled(!authorityReady || test.membershipBusy)",
        "private var correlationDisplayedWindowOrdinal: Int",
    ]
    missing = [needle for needle in required if needle not in app]
    if missing:
        raise SystemExit(f"missing recovery contracts: {missing}")
    if app.count("private var failureRecoveryContextPanel: some View") != 1:
        raise SystemExit("failure recovery panel must exist exactly once")
    if app.count("func retry()") != 1:
        raise SystemExit("controller retry must exist exactly once")
    if not TEST.is_file():
        raise SystemExit("focused failed-prerequisite recovery source regression is missing")
    print("Capture failed-prerequisite recovery source contract: PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    if args.mode == "apply":
        apply()
    verify()


if __name__ == "__main__":
    main()
