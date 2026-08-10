import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Secure Link restart authority")
struct TuyaSecureLinkRestartAuthoritySourceTests {
    @Test("failed Capture restart is owned by controller lifecycle truth")
    func failedCaptureRestartRequiresRetiredGeneration() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(
            in: app,
            from: "private final class SecureLinkController: NSObject, ObservableObject",
            to: "private final class OfficialTuyaAccountAuthorizer: ObservableObject"
        )
        let failurePanel = try section(
            in: app,
            from: "private var failurePanel: some View",
            to: "private var completionPanel: some View"
        )

        // Generic build/account/device readiness is never enough to authorize an
        // in-process restart. The controller owns lifecycle authority; the UI may
        // add stricter temporary availability gates without minting restart authority.
        #expect(controller.contains("var canRestartFromFreshOFF1"))
        #expect(controller.contains("currentConnectionToken == nil"))
        #expect(controller.contains("guard phase == .failed, canRestartFromFreshOFF1 else"))

        guard let lifecycleGate = failurePanel.range(of: "if test.canRestartFromFreshOFF1"),
              let retryCall = failurePanel.range(of: "test.retry()"),
              let relaunchOnly = failurePanel.range(of: "Relaunch Capture before another attempt") else {
            Issue.record("Expected lifecycle-gated retry and relaunch-only branches are missing.")
            throw SourceContractError.sectionMissing
        }
        #expect(lifecycleGate.lowerBound < retryCall.lowerBound)
        #expect(retryCall.lowerBound < relaunchOnly.lowerBound)
    }

    @Test("relaunch-only terminal recovery remains visible and cannot be replaced by generic restart copy")
    func relaunchOnlyRecoveryRemainsVisible() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(
            in: app,
            from: "private final class SecureLinkController: NSObject, ObservableObject",
            to: "private final class OfficialTuyaAccountAuthorizer: ObservableObject"
        )
        let failurePanel = try section(
            in: app,
            from: "private var failurePanel: some View",
            to: "private var completionPanel: some View"
        )

        #expect(controller.contains("Relaunch Capture before another attempt"))
        #expect(failurePanel.contains("Text(test.message)"))
        #expect(failurePanel.contains("canRestartFromFreshOFF1"))
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
