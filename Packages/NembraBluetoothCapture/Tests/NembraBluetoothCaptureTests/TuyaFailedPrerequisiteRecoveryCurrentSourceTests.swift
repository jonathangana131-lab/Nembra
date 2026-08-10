import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture failed-prerequisite recovery reachability")
struct TuyaFailedPrerequisiteRecoveryCurrentSourceTests {
    @Test("failed account loss exposes the official SDK login surface")
    func accountLossCanBeRecoveredWithoutImpossibleRestart() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let primary = try section(in: app, from: "private var primarySurface: some View", to: "private var preflightPanel: some View")
        let body = String(primary)

        #expect(body.contains("case .failed:"))
        #expect(body.contains("!sdkAccount.loggedIn || !test.sdkAccountLoggedIn"))
        #expect(body.contains("sdkAuthorizationPanel"))
    }

    @Test("failed membership loss exposes exact-scooter verification again")
    func membershipLossCanBeRecoveredWithoutLeavingCapture() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let primary = try section(in: app, from: "private var primarySurface: some View", to: "private var preflightPanel: some View")
        let body = String(primary)

        #expect(body.contains("!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized"))
        #expect(body.contains("preflightPanel"))
    }

    @Test("failed prerequisite recovery keeps the exact failure reason visible")
    func recoveryDoesNotEraseWhyAttemptFailed() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let surface = try section(in: app, from: "private struct SecureLinkView: View", to: "private struct SecureTransfer: Transferable")
        let body = String(surface)

        #expect(body.contains("failureRecoveryContextPanel"))
        let context = try section(in: app, from: "private var failureRecoveryContextPanel: some View", to: "private var failurePanel: some View")
        #expect(context.contains("Text(test.message)"))
        #expect(context.contains("does not reuse the failed attempt as evidence"))
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
