import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture failed prerequisite recovery")
struct TuyaFailedPrerequisiteRecoverySourceTests {
    @Test("failed product state routes to the exact missing prerequisite")
    func failedStateRoutesToRecovery() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(in: app, from: "private var primarySurface: some View", to: "private var preflightPanel: some View")
        let body = String(surface)

        #expect(body.contains("case .failed:"))
        #expect(body.contains("!test.fieldBuildIsAuthoritative || !test.privateConfig"))
        #expect(body.contains("failureRecoveryContextPanel"))
        #expect(body.contains("test.canRestartFromFreshOFF1 && (!sdkAccount.loggedIn || !test.sdkAccountLoggedIn)"))
        #expect(body.contains("sdkAuthorizationPanel"))
        #expect(body.contains("test.canRestartFromFreshOFF1 && test.sdkAccountLoggedIn && (!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized)"))
        #expect(body.contains("preflightPanel"))
    }

    @Test("in-process retry remains gated by controller-owned retired-session authority")
    func retryConsumesControllerAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let restartAuthority = try section(
            in: app,
            from: "var failedAttemptCanRestartFromOFF1: Bool",
            to: "var canRestartFromFreshOFF1: Bool"
        )
        #expect(restartAuthority.contains("phase == .failed"))
        #expect(restartAuthority.contains("currentConnectionToken == nil"))
        #expect(restartAuthority.contains("localBLESettlementToken == nil"))
        #expect(restartAuthority.contains("driver == nil"))
        #expect(restartAuthority.contains("OfficialTuyaFactory.packageCorrelationMayStart"))
        #expect(app.contains("func retry()"))
        #expect(app.contains("guard phase == .failed, canRestartFromFreshOFF1 else"))
        #expect(app.contains("Relaunch Capture before another OFF1 attempt"))
        let failure = try section(in: app, from: "private var failurePanel: some View", to: "private var completionPanel: some View")
        #expect(failure.contains("test.retry()"))
        #expect(failure.contains(".disabled(!authorityReady || test.membershipBusy)"))
    }

    @Test("failed hero subtitle does not promise in-process restart when generation retirement is unresolved")
    func failedHeroSubtitleRespectsRestartAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let subtitle = try section(in: app, from: "private var phaseSubtitle: String", to: "private var heroSymbol: String")
        let body = String(subtitle)
        #expect(body.contains("test.canRestartFromFreshOFF1"))
        #expect(body.contains("Relaunch Capture before another attempt"))
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
