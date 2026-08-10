import Foundation
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
