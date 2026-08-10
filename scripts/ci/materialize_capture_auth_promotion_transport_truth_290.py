from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAuthenticationPromotionTransportTruthSourceTests.swift")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def apply() -> None:
    source = APP.read_text(encoding="utf-8")
    old = '''                    guard sdkAccountLoggedIn,
                          sdkDeviceMembershipVerified,
                          accountIdentityLeaseIsAuthorized else {
                        await invalidateSourceAuthority(
                            token: token,
                            message: "Tuya account/device source authority changed while authentication promotion was suspended.",
                            kind: "sdk_source_authority_lost_during_auth_promotion"
                        )
                        return
                    }

                    phase = .observing
'''
    new = '''                    guard sdkAccountLoggedIn,
                          sdkDeviceMembershipVerified,
                          accountIdentityLeaseIsAuthorized else {
                        await invalidateSourceAuthority(
                            token: token,
                            message: "Tuya account/device source authority changed while authentication promotion was suspended.",
                            kind: "sdk_source_authority_lost_during_auth_promotion"
                        )
                        return
                    }
                    guard let promotionDriver = self.driver else {
                        await invalidateSourceAuthority(
                            token: token,
                            message: "Official Tuya driver authority disappeared while authentication promotion was suspended.",
                            kind: "sdk_driver_authority_lost_during_auth_promotion"
                        )
                        return
                    }
                    let promotionLocalBLEOnline = promotionDriver.isLocallyConnected(uuid: tuyaUUID)
                    sdkLocalBLEOnline = promotionLocalBLEOnline
                    guard promotionLocalBLEOnline else {
                        await recordObservedTransportLoss(token: token)
                        return
                    }

                    phase = .observing
'''
    source = replace_once(source, old, new, "post-await transport truth fence")
    APP.write_text(source, encoding="utf-8")

    TEST.write_text(r'''import Foundation
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
        let observingRange = try #require(authenticated.range(
            of: "phase = .observing",
            range: refreshRange.upperBound..<authenticated.endIndex
        ))
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
''', encoding="utf-8")


def verify() -> None:
    source = APP.read_text(encoding="utf-8")
    start = source.index("private func authenticated(token: TuyaReadOnlyConnectionToken) async")
    end = source.index("private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async", start)
    auth = source[start:end]
    refresh = auth.index("await refreshLedgerSnapshot()")
    observing = auth.index("phase = .observing", refresh)
    fence = auth[refresh:observing]
    required = [
        "currentConnectionToken == token",
        "phase == .authenticating",
        "accountIdentityLeaseIsAuthorized",
        "guard let promotionDriver = self.driver else",
        "sdk_driver_authority_lost_during_auth_promotion",
        "promotionDriver.isLocallyConnected(uuid: tuyaUUID)",
        "sdkLocalBLEOnline = promotionLocalBLEOnline",
        "guard promotionLocalBLEOnline else",
        "await recordObservedTransportLoss(token: token)",
    ]
    for token in required:
        if token not in fence:
            raise SystemExit(f"missing post-await transport truth token: {token}")
    if auth.index("startWatchdog(token: token)", observing) <= observing:
        raise SystemExit("watchdog ordering invalid")
    if not TEST.exists():
        raise SystemExit("missing transport truth regression")


if __name__ == "__main__":
    import sys
    if len(sys.argv) != 2 or sys.argv[1] not in {"apply", "verify"}:
        raise SystemExit("usage: materialize_capture_auth_promotion_transport_truth_290.py apply|verify")
    apply() if sys.argv[1] == "apply" else verify()
