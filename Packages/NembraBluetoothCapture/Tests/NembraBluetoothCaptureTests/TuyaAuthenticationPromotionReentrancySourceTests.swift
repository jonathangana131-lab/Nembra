import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authentication promotion reentrancy")
struct TuyaAuthenticationPromotionReentrancySourceTests {
    @Test("post-await auth promotion cannot resurrect a retired generation")
    func authenticatedPromotionRevalidatesAuthorityAfterActorHops() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authenticated = String(try section(
            in: source,
            from: "private func authenticated(token: TuyaReadOnlyConnectionToken) async",
            to: "private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async"
        ))

        let promotion = try #require(authenticated.range(of: "try await sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)"))
        let refresh = try #require(authenticated.range(
            of: "await refreshLedgerSnapshot()",
            range: promotion.upperBound..<authenticated.endIndex
        ))
        let observing = try #require(authenticated.range(
            of: "phase = .observing",
            range: refresh.upperBound..<authenticated.endIndex
        ))
        let postAwaitFence = String(authenticated[refresh.upperBound..<observing.lowerBound])

        #expect(postAwaitFence.contains("currentConnectionToken == token"))
        #expect(postAwaitFence.contains("phase == .authenticating"))
        #expect(postAwaitFence.contains("sdkAccountLoggedIn"))
        #expect(postAwaitFence.contains("sdkDeviceMembershipVerified"))
        #expect(postAwaitFence.contains("accountIdentityLeaseIsAuthorized"))
        #expect(postAwaitFence.contains("sdk_source_authority_lost_during_auth_promotion"))
        #expect(postAwaitFence.contains("sdk_driver_authority_lost_during_auth_promotion"))
    }

    @Test("watchdog and observing publication remain after the post-await fence")
    func watchdogCannotStartForRetiredPromotion() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authenticated = String(try section(
            in: source,
            from: "private func authenticated(token: TuyaReadOnlyConnectionToken) async",
            to: "private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async"
        ))

        let refresh = try #require(authenticated.range(of: "await refreshLedgerSnapshot()"))
        let observing = try #require(authenticated.range(of: "phase = .observing", range: refresh.upperBound..<authenticated.endIndex))
        let watchdog = try #require(authenticated.range(of: "startWatchdog(token: token)", range: observing.upperBound..<authenticated.endIndex))
        let postAwait = String(authenticated[refresh.upperBound..<observing.lowerBound])

        #expect(postAwait.contains("currentConnectionToken == token"))
        #expect(postAwait.contains("phase == .authenticating"))
        #expect(postAwait.contains("accountIdentityLeaseIsAuthorized"))
        #expect(observing.lowerBound < watchdog.lowerBound)
    }

    @Test("retired token and phase drift return without double-terminalizing")
    func alreadyRetiredResumePathsOnlyIgnore() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authenticated = String(try section(
            in: source,
            from: "private func authenticated(token: TuyaReadOnlyConnectionToken) async",
            to: "private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async"
        ))
        let refresh = try #require(authenticated.range(of: "await refreshLedgerSnapshot()"))
        let observing = try #require(authenticated.range(of: "phase = .observing", range: refresh.upperBound..<authenticated.endIndex))
        let fence = String(authenticated[refresh.upperBound..<observing.lowerBound])

        #expect(fence.contains("stale_auth_promotion_resume_ignored"))
        #expect(fence.contains("auth_promotion_resume_phase_changed_ignored"))

        // A still-current generation must revalidate both account/device authority and the official
        // driver after the actor hops. Those are two distinct source terminals; the stale-token and
        // phase-drift branches above still only log-and-return and do not double-terminalize.
        #expect(fence.contains("sdk_source_authority_lost_during_auth_promotion"))
        #expect(fence.contains("sdk_driver_authority_lost_during_auth_promotion"))
        let sourceInvalidations = fence.components(separatedBy: "await invalidateSourceAuthority(").count - 1
        #expect(sourceInvalidations == 2)
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
