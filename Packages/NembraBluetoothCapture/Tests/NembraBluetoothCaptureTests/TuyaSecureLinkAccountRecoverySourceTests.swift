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
            to: "private var correlationDisplayedWindowOrdinal: Int"
        )

        #expect(authorizer.contains("func signOut()"))
        #expect(authorizer.contains("user.loginOut"))
        #expect(authorizer.contains("loggedIn = OfficialTuyaFactory.accountLoggedIn"))
        #expect(authorizer.contains("codeSent = false"))
        #expect(authorizer.contains("Capture remains locked; relaunch before trying another account."))
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

    @Test("logout state change revokes membership and any current attempt authority")
    func logoutRevokesMembershipAndAttemptAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let secureLink = try section(
            in: app,
            from: "private struct SecureLinkView: View",
            to: "private struct SecureTransfer: Transferable"
        )
        let invalidation = try section(
            in: app,
            from: "func invalidateSDKMembership()",
            to: "func verifySDKMembership"
        )
        let packageRetirement = try section(
            in: app,
            from: "private func abandonPackageCorrelation()",
            to: "private func releasePackageCorrelationLease()"
        )

        #expect(secureLink.contains(".onChange(of: sdkAccount.loggedIn)"))
        #expect(secureLink.contains("else { test.invalidateSDKMembership() }"))
        #expect(invalidation.contains("membershipRequestID = UUID()"))
        #expect(invalidation.contains("sdkDeviceMembershipVerified = false"))
        #expect(invalidation.contains("membershipAccountUID = nil"))
        #expect(invalidation.contains("membershipDeviceID = nil"))
        #expect(invalidation.contains("pendingCorrelatedTargetID = nil"))
        #expect(invalidation.contains("abandonPackageCorrelation()"))
        #expect(packageRetirement.contains("correlationSession?.abandonCurrentWindow()"))
        #expect(packageRetirement.contains("correlationSession = nil"))
        #expect(packageRetirement.contains("releasePackageCorrelationLease()"))
        #expect(invalidation.contains("phase = .failed"))
        #expect(invalidation.contains("invalidateSourceAuthority("))
    }

    @Test("account recovery preserves the accepted correlation presentation repair")
    func preservesCorrelationTruth() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("private var correlationDisplayedWindowOrdinal: Int"))
        #expect(app.contains("test.phase == .correlated ? 4 : min(test.correlationCompletedWindowCount + 1, 4)"))
        #expect(app.contains("Text(\"\\(correlationDisplayedWindowOrdinal)/4\")"))
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
