from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
CORRELATION_TEST = Path(
    "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/"
    "TuyaCorrelationProgressPresentationTruthSourceTests.swift"
)
RECOVERY_TEST = Path(
    "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/"
    "TuyaFailedPrerequisiteRecoverySourceTests.swift"
)

text = APP.read_text(encoding="utf-8")


def replace_once(old: str, new: str, name: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{name}: expected exactly one match, found {count}")
    text = text.replace(old, new, 1)


replace_once(
    '    private let stageLabels = ["Target", "Secure link", "Observe", "Seal"]\n',
    '    private let stageLabels = ["Target", "Secure link", "Observe", "Seal"]\n\n'
    '    private var correlationDisplayedWindowOrdinal: Int {\n'
    '        test.phase == .correlated ? 4 : min(test.correlationCompletedWindowCount + 1, 4)\n'
    '    }\n',
    "correlation ordinal helper",
)

replace_once(
    '        case .failed:\n            failurePanel\n',
    '        case .failed:\n'
    '            if !test.fieldBuildIsAuthoritative || !test.privateConfig {\n'
    '                VStack(spacing: 16) {\n'
    '                    failureRecoveryContextPanel\n'
    '                    preflightPanel\n'
    '                }\n'
    '            } else if !sdkAccount.loggedIn || !test.sdkAccountLoggedIn {\n'
    '                VStack(spacing: 16) {\n'
    '                    failureRecoveryContextPanel\n'
    '                    sdkAuthorizationPanel\n'
    '                }\n'
    '            } else if !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {\n'
    '                VStack(spacing: 16) {\n'
    '                    failureRecoveryContextPanel\n'
    '                    preflightPanel\n'
    '                }\n'
    '            } else {\n'
    '                failurePanel\n'
    '            }\n',
    "failed prerequisite recovery routing",
)

replace_once(
    '                    Text("\\(min(test.correlationCompletedWindowCount + 1, 4))/4")\n',
    '                    Text("\\(correlationDisplayedWindowOrdinal)/4")\n',
    "visible correlation ordinal",
)

failure_marker = '    private var failurePanel: some View {\n'
if text.count(failure_marker) != 1:
    raise SystemExit("failure panel insertion marker must be unique")
recovery_panel = '''    private var failureRecoveryContextPanel: some View {
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

'''
text = text.replace(failure_marker, recovery_panel + failure_marker, 1)

failure_start = text.index('    private var failurePanel: some View {')
failure_end = text.index('    private var completionPanel: some View {', failure_start)
failure = text[failure_start:failure_end]
old_action = '''                    Button {
                        test.startBaseline()
                    } label {'''
if failure.count(old_action) != 1:
    raise SystemExit("failure restart action must match exactly once")
failure = failure.replace(
    old_action,
    '''                    Button {
                        test.retry()
                    } label {''',
    1,
)
control_size = '                    .controlSize(.large)\n'
if failure.count(control_size) < 1:
    raise SystemExit("failure restart control size marker missing")
failure = failure.replace(
    control_size,
    control_size + '                    .disabled(!authorityReady || test.membershipBusy)\n',
    1,
)
text = text[:failure_start] + failure + text[failure_end:]

controller_marker = '    func consumeCorrelationAsyncInvalidation() {\n'
if text.count(controller_marker) != 1:
    raise SystemExit("controller retry insertion marker must be unique")
retry_method = '''    func retry() {
        guard phase == .failed, canRestartFromFreshOFF1 else {
            message = "This failed attempt still retains session authority. Relaunch Capture before another OFF1 attempt."
            log("in_process_retry_rejected")
            return
        }
        startBaseline()
    }

'''
text = text.replace(controller_marker, retry_method + controller_marker, 1)

required = [
    'test.phase == .correlated ? 4 : min(test.correlationCompletedWindowCount + 1, 4)',
    'Text("\\(correlationDisplayedWindowOrdinal)/4")',
    'func retry()',
    'guard phase == .failed, canRestartFromFreshOFF1 else',
    'test.retry()',
    'failureRecoveryContextPanel',
    'sdkAuthorizationPanel',
    '.disabled(!authorityReady || test.membershipBusy)',
]
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit(f"missing repaired product contracts: {missing}")
if 'Text("\\(min(test.correlationCompletedWindowCount + 1, 4))/4")' in text:
    raise SystemExit("false completed correlation ordinal remains")

APP.write_text(text, encoding="utf-8")

CORRELATION_TEST.write_text(
    '''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture correlation progress presentation truth")
struct TuyaCorrelationProgressPresentationTruthSourceTests {
    @Test("completed OFF1 ON1 OFF2 ON2 correlation presents four of four")
    func completedCorrelationDoesNotFallBackToOneOfFour() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(
            in: app,
            from: "private struct SecureLinkView: View",
            to: "private struct SecureTransfer: Transferable"
        )
        let body = String(surface)

        #expect(!body.contains("Text(\\\"\\\\(min(test.correlationCompletedWindowCount + 1, 4))/4\\\")"))
        #expect(body.contains("correlationDisplayedWindowOrdinal"))
        #expect(body.contains("test.phase == .correlated ? 4"))
        #expect(body.contains("Text(\\\"\\\\(correlationDisplayedWindowOrdinal)/4\\\")"))
    }

    @Test("in-progress correlation still derives its ordinal from package-owned completed windows")
    func activeCorrelationProgressRemainsEvidenceBacked() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(
            in: app,
            from: "private struct SecureLinkView: View",
            to: "private struct SecureTransfer: Transferable"
        )
        let body = String(surface)

        #expect(body.contains("min(test.correlationCompletedWindowCount + 1, 4)"))
        #expect(!body.localizedCaseInsensitiveContains("rssi progress"))
        #expect(!body.localizedCaseInsensitiveContains("name progress"))
        #expect(!body.localizedCaseInsensitiveContains("tuya hint progress"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \\(start) ... \\(end)")
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
''',
    encoding="utf-8",
)

RECOVERY_TEST.write_text(
    '''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture failed-prerequisite recovery")
struct TuyaFailedPrerequisiteRecoverySourceTests {
    @Test("failed product state exposes the missing prerequisite recovery surface")
    func failedStateRoutesToRecovery() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(in: app, from: "private var primarySurface: some View", to: "private var preflightPanel: some View")
        let body = String(surface)
        #expect(body.contains("case .failed:"))
        #expect(body.contains("!test.fieldBuildIsAuthoritative || !test.privateConfig"))
        #expect(body.contains("!sdkAccount.loggedIn || !test.sdkAccountLoggedIn"))
        #expect(body.contains("sdkAuthorizationPanel"))
        #expect(body.contains("!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized"))
        #expect(body.contains("preflightPanel"))
        #expect(body.contains("failureRecoveryContextPanel"))
    }

    @Test("in-process retry is controller gated by retired package and driver ownership")
    func retryConsumesControllerAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("var canRestartFromFreshOFF1: Bool { failedAttemptCanRestartFromOFF1 }"))
        #expect(app.contains("currentConnectionToken == nil && localBLESettlementToken == nil && driver == nil"))
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
