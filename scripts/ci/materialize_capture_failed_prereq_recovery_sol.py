#!/usr/bin/env python3
from pathlib import Path

app_path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
test_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFailedPrerequisiteRecoveryTruthSourceTests.swift")
text = app_path.read_text()


def replace_once(old: str, new: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected one source match, found {count}: {old[:100]!r}")
    text = text.replace(old, new, 1)


replace_once(
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
)

recovery = '''    private var failureRecoveryContextPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: 10) {
                Label("Capture paused", systemImage: "exclamationmark.circle")
                    .font(.title2.bold())
                    .foregroundStyle(.orange)
                Text(test.message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Restore the missing prerequisite below. A new OFF1 attempt can begin only after the prior attempt is safely restartable; failed evidence is never reused.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

'''
replace_once("    private var failurePanel: some View {\n", recovery + "    private var failurePanel: some View {\n")

replace_once(
    "    func startBaseline() {\n        guard buildIdentity.isAuthoritativeFieldBuild else {",
    "    func startBaseline() {\n"
    "        if phase == .failed && !canRestartFromFreshOFF1 {\n"
    "            message = \"This failed attempt still retains session authority. Relaunch Capture before another OFF1 attempt.\"\n"
    "            log(\"in_process_restart_rejected\")\n"
    "            return\n"
    "        }\n"
    "        guard buildIdentity.isAuthoritativeFieldBuild else {",
)

app_path.write_text(text)

test_path.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture failed prerequisite recovery truth")
struct TuyaFailedPrerequisiteRecoveryTruthSourceTests {
    @Test("failed account and membership prerequisites remain recoverable")
    func failedPrerequisitesExposeRequiredControls() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let primary = try section(in: app, from: "private var primarySurface: some View", to: "private var preflightPanel: some View")
        let body = String(primary)
        #expect(body.contains("case .failed:"))
        #expect(body.contains("!sdkAccount.loggedIn || !test.sdkAccountLoggedIn"))
        #expect(body.contains("sdkAuthorizationPanel"))
        #expect(body.contains("!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized"))
        #expect(body.contains("preflightPanel"))
        #expect(body.contains("failureRecoveryContextPanel"))
    }

    @Test("failed-state OFF1 cannot bypass lifecycle retirement")
    func failedRestartIsControllerGuarded() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(in: app, from: "private final class SecureLinkController", to: "private final class OfficialTuyaDriver")
        let body = String(controller)
        #expect(body.contains("currentConnectionToken == nil && localBLESettlementToken == nil && driver == nil"))
        #expect(body.contains("if phase == .failed && !canRestartFromFreshOFF1"))
        #expect(body.contains("in_process_restart_rejected"))
    }

    @Test("recovery preserves the exact failure reason")
    func recoveryContextPreservesFailureTruth() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let context = try section(in: app, from: "private var failureRecoveryContextPanel: some View", to: "private var failurePanel: some View")
        #expect(context.contains("Text(test.message)"))
        #expect(context.contains("failed evidence is never reused"))
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
''')

required = [
    "failureRecoveryContextPanel",
    "!sdkAccount.loggedIn || !test.sdkAccountLoggedIn",
    "!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized",
    "if phase == .failed && !canRestartFromFreshOFF1",
    "in_process_restart_rejected",
]
missing = [needle for needle in required if needle not in text]
if missing:
    raise SystemExit(f"missing recovery contracts: {missing}")
