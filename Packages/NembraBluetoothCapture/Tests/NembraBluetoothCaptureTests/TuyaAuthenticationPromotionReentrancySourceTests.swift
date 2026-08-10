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
        #expect(postAwaitFence.contains("accountIdentityLeaseIsAuthorized"))
    }

    @Test("watchdog starts only after the post-await authority fence")
    func watchdogCannotStartForRetiredPromotion() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authenticated = String(try section(
            in: source,
            from: "private func authenticated(token: TuyaReadOnlyConnectionToken) async",
            to: "private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async"
        ))

        let refresh = try #require(authenticated.range(of: "await refreshLedgerSnapshot()"))
        let watchdog = try #require(authenticated.range(
            of: "startWatchdog(token: token)",
            range: refresh.upperBound..<authenticated.endIndex
        ))
        let postAwait = String(authenticated[refresh.upperBound..<watchdog.lowerBound])

        #expect(postAwait.contains("currentConnectionToken == token"))
        #expect(postAwait.contains("phase == .authenticating"))
        #expect(postAwait.contains("accountIdentityLeaseIsAuthorized"))
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
