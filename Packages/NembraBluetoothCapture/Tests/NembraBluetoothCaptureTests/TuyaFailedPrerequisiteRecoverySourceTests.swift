import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture failed-prerequisite product recovery")
struct TuyaFailedPrerequisiteRecoverySourceTests {
    @Test("failed state exposes prerequisite recovery instead of trapping the operator")
    func failedStateRoutesLostPrerequisitesToTheirRecoverySurface() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(
            in: app,
            from: "private struct SecureLinkView: View",
            to: "private struct SecureTransfer: Transferable"
        )
        let primary = try section(
            in: String(surface),
            from: "private var primarySurface: some View",
            to: "private var preflightPanel: some View"
        )
        let body = String(primary)

        // A failed attempt may coincide with a lost build/account/membership prerequisite.
        // V14 requires the operator to see the exact corrective surface, not remain trapped
        // in a terminal panel whose restart action simply fails the same prerequisite again.
        guard let failedCase = body.range(of: "case .failed:") else {
            Issue.record("Primary product routing no longer exposes an explicit failed state.")
            throw SourceContractError.requiredSourceMissing
        }
        let failedBody = String(body[failedCase.lowerBound...])

        #expect(failedBody.contains("test.fieldBuildIsAuthoritative"))
        #expect(failedBody.contains("test.privateConfig"))
        #expect(failedBody.contains("test.sdkAccountLoggedIn"))
        #expect(failedBody.contains("test.sdkDeviceMembershipVerified"))
        #expect(failedBody.contains("test.accountIdentityLeaseIsAuthorized"))
        #expect(failedBody.contains("preflightPanel"))
        #expect(failedBody.contains("sdkAuthorizationPanel"))
        #expect(failedBody.contains("failurePanel"))
    }

    @Test("lifecycle-safe failure still retains the dedicated failure panel")
    func ordinaryFailureDoesNotBypassRestartAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(
            in: app,
            from: "private struct SecureLinkView: View",
            to: "private struct SecureTransfer: Transferable"
        )
        let failure = try section(
            in: String(surface),
            from: "private var failurePanel: some View",
            to: "private var completionPanel: some View"
        )
        let body = String(failure)

        #expect(body.contains("test.failedAttemptCanRestartFromOFF1"))
        #expect(body.contains("test.canRestartFromFreshOFF1"))
        #expect(body.contains("Restart from scooter OFF"))
        #expect(body.contains("Relaunch Capture"))
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
        case requiredSourceMissing
    }
}
