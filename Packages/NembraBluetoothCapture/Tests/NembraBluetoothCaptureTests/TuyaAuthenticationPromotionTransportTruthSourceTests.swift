import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authentication promotion transport truth")
struct TuyaAuthenticationPromotionTransportTruthSourceTests {
    @Test("post-await promotion re-reads current driver and local BLE before observing")
    func promotionRevalidatesTransportAfterActorHops() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authenticated = String(try section(
            in: source,
            from: "private func authenticated(token: TuyaReadOnlyConnectionToken) async",
            to: "private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async"
        ))
        let refresh = try requiredOffset("await refreshLedgerSnapshot()", in: authenticated)
        let tokenFence = try requiredOffset("guard currentConnectionToken == token else", in: authenticated, after: refresh)
        let sourceFence = try requiredOffset("accountIdentityLeaseIsAuthorized else", in: authenticated, after: tokenFence)
        let currentDriver = try requiredOffset("guard let promotionDriver = self.driver else", in: authenticated, after: sourceFence)
        let driverTerminal = try requiredOffset("sdk_driver_authority_lost_during_auth_promotion", in: authenticated, after: currentDriver)
        let localBLERead = try requiredOffset("promotionDriver.isLocallyConnected(uuid: tuyaUUID)", in: authenticated, after: driverTerminal)
        let localBLEMirror = try requiredOffset("sdkLocalBLEOnline = promotionLocalBLEOnline", in: authenticated, after: localBLERead)
        let offlineFence = try requiredOffset("guard promotionLocalBLEOnline else", in: authenticated, after: localBLEMirror)
        let transportTerminal = try requiredOffset("await recordObservedTransportLoss(token: token)", in: authenticated, after: offlineFence)
        let observing = try requiredOffset("phase = .observing", in: authenticated, after: transportTerminal)
        let watchdog = try requiredOffset("startWatchdog(token: token)", in: authenticated, after: observing)
        #expect(refresh < tokenFence)
        #expect(tokenFence < sourceFence)
        #expect(sourceFence < currentDriver)
        #expect(currentDriver < driverTerminal)
        #expect(driverTerminal < localBLERead)
        #expect(localBLERead < localBLEMirror)
        #expect(localBLEMirror < offlineFence)
        #expect(offlineFence < transportTerminal)
        #expect(transportTerminal < observing)
        #expect(observing < watchdog)
    }

    @Test("transport recheck does not reuse the pre-await driver binding")
    func promotionUsesFreshCurrentDriverAuthority() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authenticated = String(try section(
            in: source,
            from: "private func authenticated(token: TuyaReadOnlyConnectionToken) async",
            to: "private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async"
        ))
        let refreshRange = try #require(authenticated.range(of: "await refreshLedgerSnapshot()"))
        let observingRange = try #require(authenticated.range(of: "phase = .observing", range: refreshRange.upperBound..<authenticated.endIndex))
        let postAwait = String(authenticated[refreshRange.upperBound..<observingRange.lowerBound])
        #expect(postAwait.contains("guard let promotionDriver = self.driver else"))
        #expect(postAwait.contains("promotionDriver.isLocallyConnected(uuid: tuyaUUID)"))
        #expect(!postAwait.contains("let isLocallyOnline = driver.isLocallyConnected"))
    }

    private func requiredOffset(_ token: String, in source: String, after: String.Index? = nil) throws -> String.Index {
        let lower = after ?? source.startIndex
        guard let range = source.range(of: token, range: lower..<source.endIndex) else {
            Issue.record("Expected source token missing: \(token)")
            throw SourceContractError.sectionMissing
        }
        return range.lowerBound
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
