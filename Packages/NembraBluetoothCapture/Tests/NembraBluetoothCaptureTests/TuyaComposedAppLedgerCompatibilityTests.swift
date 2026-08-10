import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya composed app ledger compatibility")
struct TuyaComposedAppLedgerCompatibilityTests {
    @Test("structured projection bytes count as one application observation, never byte length")
    func compatibilityProjectionIsPresenceOnly() async throws {
        let clock = TestCompatibilityClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)

        try await ledger.recordApplicationPayload(Data(repeating: 0x41, count: 99), for: token)

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == 3_000)
    }

    @Test("empty compatibility projection fails closed")
    func emptyProjectionIsRejected() async throws {
        let clock = TestCompatibilityClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.emptyApplicationUpdate) {
            try await ledger.recordApplicationPayload(Data(), for: token)
        }
    }

    @Test("post-auth terminal failure retires accepted chronology")
    func lateFailureRetiresAuthority() async throws {
        let clock = TestCompatibilityClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationPayload(Data([0x01]), for: token)
        clock.advance(to: 4_000)
        try await ledger.markAuthenticationFailed(for: token)

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.authenticationState == .failed(reason: "Tuya authentication failed."))
        #expect(snapshot.authenticationMethod == nil)
        #expect(snapshot.applicationPayloadCount == 0)
        #expect(snapshot.authenticatedAtUptimeNanoseconds == nil)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == nil)
    }

    @Test("liveness cannot advance before authentication")
    func preAuthLivenessIsRejected() async throws {
        let clock = TestCompatibilityClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 2_000)

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.authenticationRequired) {
            try await ledger.observeCurrentConnection(for: token)
        }
    }
}

private final class TestCompatibilityClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64

    init(_ value: UInt64) {
        self.value = value
    }

    var now: @Sendable () -> UInt64 {
        { [self] in
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    func advance(to newValue: UInt64) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}
