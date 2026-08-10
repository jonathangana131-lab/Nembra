import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture retained-generation prerequisite recovery")
struct TuyaRetainedGenerationPrerequisiteRecoverySourceTests {
    @Test("missing account or membership never bypasses relaunch-only retained generation")
    func prerequisiteRecoveryRequiresRetiredGenerationAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(
            in: app,
            from: "private var primarySurface: some View",
            to: "private var preflightPanel: some View"
        )
        let body = String(surface)

        #expect(body.contains("case .failed:"))
        #expect(body.contains("test.canRestartFromFreshOFF1 && test.privateConfig && (!sdkAccount.loggedIn || !test.sdkAccountLoggedIn)"))
        #expect(body.contains("test.canRestartFromFreshOFF1 && test.sdkAccountLoggedIn && (!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized)"))
        #expect(body.contains("sdkAuthorizationPanel"))
        #expect(body.contains("preflightPanel"))
        #expect(body.contains("failurePanel"))
    }

    @Test("restart authority proves all app-owned connection handles retired")
    func restartAuthorityRequiresNoRetainedConnectionOwner() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(
            in: app,
            from: "var failedAttemptCanRestartFromOFF1: Bool",
            to: "var secureSessionEstablished: Bool"
        )
        let body = String(controller)

        #expect(body.contains("phase == .failed"))
        #expect(body.contains("currentConnectionToken == nil"))
        #expect(body.contains("localBLESettlementToken == nil"))
        #expect(body.contains("driver == nil"))
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
