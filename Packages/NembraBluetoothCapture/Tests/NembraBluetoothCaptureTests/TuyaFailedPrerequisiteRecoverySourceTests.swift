import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture failed-prerequisite product recovery")
struct TuyaFailedPrerequisiteRecoverySourceTests {
    @Test("recoverable failed state exposes the control that can restore missing account or membership authority")
    func failedStateRoutesToRestorablePrerequisiteOnlyAfterGenerationRetirement() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(in: app, from: "private var primarySurface: some View", to: "private var preflightPanel: some View")
        let body = String(surface)
        #expect(body.contains("case .failed:"))
        #expect(body.contains("test.failedAttemptCanRestartFromOFF1 && test.privateConfig && (!sdkAccount.loggedIn || !test.sdkAccountLoggedIn)"))
        #expect(body.contains("sdkAuthorizationPanel"))
        #expect(body.contains("test.failedAttemptCanRestartFromOFF1 && test.sdkAccountLoggedIn && (!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized)"))
        #expect(body.contains("preflightPanel"))
        #expect(body.contains("failureRecoveryContextPanel"))
        #expect(body.contains("failurePanel"))
    }

    @Test("retained generation remains relaunch-only even if field prerequisites are also missing")
    func retainedGenerationCannotEnterInAppPrerequisiteRecovery() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(in: app, from: "var failedAttemptCanRestartFromOFF1: Bool", to: "var secureSessionEstablished: Bool")
        let surface = try section(in: app, from: "private var primarySurface: some View", to: "private var preflightPanel: some View")
        #expect(controller.contains("phase == .failed && currentConnectionToken == nil"))
        #expect(surface.contains("test.failedAttemptCanRestartFromOFF1 &&"))
    }

    @Test("recovery context preserves the exact blocker and failed-attempt boundary")
    func recoveryContextPreservesFailureReason() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let context = try section(in: app, from: "private var failureRecoveryContextPanel: some View", to: "private var failurePanel: some View")
        #expect(context.contains("Text(test.message)"))
        #expect(context.contains("Capture does not reuse the failed attempt as evidence."))
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
