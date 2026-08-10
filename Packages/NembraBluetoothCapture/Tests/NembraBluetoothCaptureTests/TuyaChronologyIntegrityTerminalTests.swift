import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya chronology-integrity terminal")
struct TuyaChronologyIntegrityTerminalTests {
    @Test("authentication clock regression retires generation without another clock sample")
    func authenticationRegressionCannotStrandCallbackAuthority() async throws {
        let clock = MutableUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: { clock.now() })
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        let before = await ledger.currentPreflightSnapshot()
        clock.advance(to: 1_499)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed) {
            try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        }
        try await ledger.markChronologyIntegrityInvalidated(for: token)
        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Read-only session chronology integrity was invalidated."))
        #expect(failed.authenticationMethod == nil)
        #expect(failed.authenticatedAtUptimeNanoseconds == nil)
        #expect(failed.applicationPayloadCount == 0)
        #expect(failed.latestObservedUptimeNanoseconds == before.latestObservedUptimeNanoseconds)
        clock.advance(to: 2_000)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        }
    }
}

private final class MutableUptimeClock: @unchecked Sendable {
    private let lock = NSLock(); private var value: UInt64
    init(_ value: UInt64) { self.value = value }
    func now() -> UInt64 { lock.lock(); defer { lock.unlock() }; return value }
    func advance(to value: UInt64) { lock.lock(); self.value = value; lock.unlock() }
}
