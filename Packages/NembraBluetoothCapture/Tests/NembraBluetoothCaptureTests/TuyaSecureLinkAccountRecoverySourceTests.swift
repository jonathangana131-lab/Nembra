import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture SDK account recovery surface")
struct TuyaSecureLinkAccountRecoverySourceTests {
    @Test("wrong-account membership failure exposes an official SDK account switch")
    func wrongAccountCanRecoverWithoutBluetoothWork() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authorizer = try section(
            in: app,
            from: "private final class OfficialTuyaAccountAuthorizer: ObservableObject",
            to: "@MainActor\nprivate struct SecureLinkView: View"
        )
        let surface = try section(
            in: app,
            from: "private var preflightPanel: some View",
            to: "private var correlationPanel: some View"
        )

        #expect(authorizer.contains("func signOut()"))
        #expect(authorizer.contains("loginOut"))
        #expect(authorizer.contains("OfficialTuyaFactory.accountLoggedIn"))
        #expect(authorizer.contains("codeSent = false"))
        #expect(surface.contains("test.membershipStatus"))
        #expect(surface.contains("Use a different Tuya account"))
        #expect(surface.contains("sdkAccount.signOut()"))
        #expect(surface.contains("test.sdkAccountLoggedIn && (!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized)"))
    }

    @Test("account switching remains setup recovery rather than scooter authority")
    func accountSwitchDoesNotCreateScooterAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authorizer = try section(
            in: app,
            from: "private final class OfficialTuyaAccountAuthorizer: ObservableObject",
            to: "@MainActor\nprivate struct SecureLinkView: View"
        )

        #expect(!authorizer.contains("connectBLE"))
        #expect(!authorizer.contains("writeValue"))
        #expect(!authorizer.contains("publishDps"))
        #expect(!authorizer.contains("markAuthenticated"))
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
