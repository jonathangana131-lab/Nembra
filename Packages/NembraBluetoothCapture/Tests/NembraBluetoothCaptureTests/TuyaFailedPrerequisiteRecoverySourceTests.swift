import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture failed-prerequisite recovery")
struct TuyaFailedPrerequisiteRecoverySourceTests {
    @Test("failed product state exposes the missing prerequisite recovery surface")
    func failedStateRoutesToRecovery() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = String(try section(in: app, from: "private var primarySurface: some View", to: "private var preflightPanel: some View"))

        #expect(surface.contains("case .failed:"))
        #expect(surface.contains("!test.fieldBuildIsAuthoritative || !test.privateConfig"))
        #expect(surface.contains("!sdkAccount.loggedIn || !test.sdkAccountLoggedIn"))
        #expect(surface.contains("sdkAuthorizationPanel"))
        #expect(surface.contains("!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized"))
        #expect(surface.contains("preflightPanel"))
        #expect(surface.contains("failureRecoveryContextPanel"))
    }

    @Test("in-process retry is controller gated by retired package and driver ownership")
    func retryConsumesControllerAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("var canRestartFromFreshOFF1: Bool { failedAttemptCanRestartFromOFF1 }"))
        #expect(app.contains("currentConnectionToken == nil && localBLESettlementToken == nil && driver == nil"))
        #expect(app.contains("func retry()"))
        #expect(app.contains("guard phase == .failed, canRestartFromFreshOFF1 else"))

        let failure = String(try section(in: app, from: "private var failurePanel: some View", to: "private var completionPanel: some View"))
        #expect(failure.contains("test.retry()"))
        #expect(failure.contains(".disabled(!authorityReady || test.membershipBusy)"))
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
