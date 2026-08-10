import Foundation
import Testing

@Suite("Tuya authenticated callback terminal fences")
struct TuyaAuthenticatedCallbackTerminalSourceTests {
    private static func appSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("App")
                .appendingPathComponent("NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
    }

    private static func authenticatedCallback(_ source: String) throws -> Substring {
        let start = try #require(
            source.range(of: "private func authenticated(token: TuyaReadOnlyConnectionToken) async")?.lowerBound
        )
        let end = try #require(
            source.range(
                of: "private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async",
                range: start..<source.endIndex
            )?.lowerBound
        )
        return source[start..<end]
    }

    @Test("SDK success callback cannot silently abandon a current authenticating generation")
    func successCallbackMustRetireAuthorityLoss() throws {
        let callback = try Self.authenticatedCallback(Self.appSource())

        let silentAuthorityGuard = """
        guard phase == .authenticating,
              currentConnectionToken == token,
              sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let driver else { return }
        """

        #expect(!callback.contains(silentAuthorityGuard))
        #expect(callback.contains("invalidateSourceAuthority"))
    }

    @Test("authentication-promotion rejection cannot leave the ledger token live behind failed UI")
    func promotionFailureMustRetireGeneration() throws {
        let callback = try Self.authenticatedCallback(Self.appSource())
        let rejectionMessage = "Authenticated-session chronology rejected the SDK success callback"
        let rejection = try #require(callback.range(of: rejectionMessage))
        let tail = callback[rejection.lowerBound...]

        #expect(!tail.contains("failLocally(\"Authenticated-session chronology rejected the SDK success callback"))
        #expect(
            tail.contains("invalidateSourceAuthority")
                || tail.contains("markAuthenticationFailed")
                || tail.contains("currentConnectionToken = nil")
        )
    }
}
