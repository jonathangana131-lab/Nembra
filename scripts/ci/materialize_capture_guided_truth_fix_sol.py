#!/usr/bin/env python3
from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
CORRELATION_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCorrelationProgressPresentationTruthSourceTests.swift")
RECOVERY_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFailedPrerequisiteRecoveryTruthSourceTests.swift")

text = APP.read_text()


def replace_once(old: str, new: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected one match, found {count}: {old[:120]!r}")
    text = text.replace(old, new, 1)


replace_once(
    "    private var correlationPanel: some View {\n",
    "    private var correlationDisplayedWindowOrdinal: Int {\n"
    "        test.phase == .correlated ? 4 : min(test.correlationCompletedWindowCount + 1, 4)\n"
    "    }\n\n"
    "    private var correlationPanel: some View {\n",
)
replace_once(
    '                    Text("\\(min(test.correlationCompletedWindowCount + 1, 4))/4")\n',
    '                    Text("\\(correlationDisplayedWindowOrdinal)/4")\n',
)
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

APP.write_text(text)

correlation_test = r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture correlation progress presentation truth")
struct TuyaCorrelationProgressPresentationTruthSourceTests {
    @Test("completed OFF1 ON1 OFF2 ON2 correlation presents four of four")
    func completedCorrelationDoesNotFallBackToOneOfFour() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(in: app, from: "private struct SecureLinkView: View", to: "private struct SecureTransfer: Transferable")
        let body = String(surface)
        #expect(!body.contains("Text(\"\\(min(test.correlationCompletedWindowCount + 1, 4))/4\")"))
        #expect(body.contains("correlationDisplayedWindowOrdinal"))
        #expect(body.contains("test.phase == .correlated ? 4"))
        #expect(body.contains("Text(\"\\(correlationDisplayedWindowOrdinal)/4\")"))
    }

    @Test("active correlation ordinal remains package-progress-derived")
    func activeCorrelationProgressRemainsEvidenceBacked() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(in: app, from: "private struct SecureLinkView: View", to: "private struct SecureTransfer: Transferable")
        let body = String(surface)
        #expect(body.contains("min(test.correlationCompletedWindowCount + 1, 4)"))
        #expect(!body.localizedCaseInsensitiveContains("rssi progress"))
        #expect(!body.localizedCaseInsensitiveContains("name progress"))
        #expect(!body.localizedCaseInsensitiveContains("tuya hint progress"))
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
'''
CORRELATION_TEST.write_text(correlation_test)

recovery_test = r'''import Foundation
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

    @Test("every failed-state OFF1 entry remains controller guarded")
    func failedRestartCannotBypassRetirementAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(in: app, from: "private final class SecureLinkController", to: "private final class OfficialTuyaDriver")
        let body = String(controller)
        #expect(body.contains("var canRestartFromFreshOFF1: Bool { failedAttemptCanRestartFromOFF1 }"))
        #expect(body.contains("currentConnectionToken == nil && localBLESettlementToken == nil && driver == nil"))
        #expect(body.contains("if phase == .failed && !canRestartFromFreshOFF1"))
        #expect(body.contains("in_process_restart_rejected"))
    }

    @Test("recovery keeps the original failure reason visible and never reuses failed evidence")
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
'''
RECOVERY_TEST.write_text(recovery_test)

required = [
    "test.phase == .correlated ? 4 : min(test.correlationCompletedWindowCount + 1, 4)",
    'Text("\\(correlationDisplayedWindowOrdinal)/4")',
    "failureRecoveryContextPanel",
    "!sdkAccount.loggedIn || !test.sdkAccountLoggedIn",
    "!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized",
    "if phase == .failed && !canRestartFromFreshOFF1",
    "in_process_restart_rejected",
]
missing = [needle for needle in required if needle not in text]
if missing:
    raise SystemExit(f"missing repair contracts: {missing}")
if 'Text("\\(min(test.correlationCompletedWindowCount + 1, 4))/4")' in text:
    raise SystemExit("false completed correlation ordinal remains visible")
