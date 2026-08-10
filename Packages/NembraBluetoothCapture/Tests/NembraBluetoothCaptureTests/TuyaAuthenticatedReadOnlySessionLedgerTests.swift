import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated read-only session ledger")
struct TuyaAuthenticatedReadOnlySessionLedgerTests {
    @Test("reconnect clears provenance and prior application authority")
    func reconnectClearsPriorEvidence() async throws {
        let clock = TestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let first = try await ledger.beginConnection()
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: first, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(fieldCount: 1, for: first)
        clock.advance(to: 4_000)
        let second = try await ledger.beginConnection()
        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(second.diagnosticGeneration == first.diagnosticGeneration + 1)
        #expect(snapshot.authenticationState == .waitingForAuthentication)
        #expect(snapshot.authenticationMethod == nil)
        #expect(snapshot.applicationPayloadCount == 0)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == nil)
        #expect(snapshot.authenticatedAtUptimeNanoseconds == nil)
        #expect(snapshot.connectionGeneration == second.diagnosticGeneration)
    }

    @Test("stale callback cannot contaminate newer connection generation")
    func staleGenerationRejected() async throws {
        let clock = TestUptimeClock(10)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let first = try await ledger.beginConnection()
        clock.advance(to: 20)
        let second = try await ledger.beginConnection()
        clock.advance(to: 30)
        try await ledger.markAuthenticated(for: second, method: .smartLifeAppSDK)
        clock.advance(to: 40)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection) {
            try await ledger.recordApplicationUpdate(fieldCount: 1, for: first)
        }
        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.connectionGeneration == second.diagnosticGeneration)
        #expect(snapshot.applicationPayloadCount == 0)
    }

    @Test("application update admission is post-auth and non-empty")
    func applicationAdmissionIsFailClosed() async throws {
        let clock = TestUptimeClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 110)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.authenticationRequired) {
            try await ledger.recordApplicationUpdate(fieldCount: 1, for: token)
        }
        clock.advance(to: 120)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 130)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 140)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.emptyApplicationUpdate) {
            try await ledger.recordApplicationUpdate(fieldCount: 0, for: token)
        }
    }

    @Test("official provenance plus decoded application update and exact stability window earns gate")
    func acceptedGateUsesSealedChronology() async throws {
        let clock = TestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(fieldCount: 2, for: token)
        clock.advance(to: 2_000 + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds)
        try await ledger.observeCurrentConnection(for: token)
        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.authenticationMethod == .smartLifeAppSDK)
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == 3_000)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .readyForStationaryMapping)
    }

    @Test("clock regression cannot rewrite accepted chronology")
    func clockRegressionFailsClosed() async throws {
        let clock = TestUptimeClock(5_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 6_000)
        try await ledger.markAuthenticated(for: token, method: .documentedDeviceSharing)
        let before = await ledger.currentPreflightSnapshot()
        clock.advance(to: 5_999)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed) {
            try await ledger.observeCurrentConnection(for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == before)
    }

    @Test("disconnect retires auth provenance and application authority")
    func disconnectRetiresAuthority() async throws {
        let clock = TestUptimeClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 200)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 300)
        try await ledger.recordApplicationUpdate(fieldCount: 1, for: token)
        clock.advance(to: 400)
        try await ledger.endConnection(for: token)
        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.authenticationState == .unavailable(reason: "Bluetooth connection ended."))
        #expect(snapshot.authenticationMethod == nil)
        #expect(snapshot.applicationPayloadCount == 0)
        #expect(snapshot.authenticatedAtUptimeNanoseconds == nil)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == nil)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .blocked(reason: "Bluetooth connection ended."))
    }

    @Test("terminal invalidation blocks late authenticated callbacks")
    func invalidationBlocksLateCallbacks() async throws {
        let clock = TestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.invalidateAttempt(for: token)
        clock.advance(to: 4_000)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(fieldCount: 1, for: token)
        }
        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.authenticationState == .failed(reason: "Authenticated read-only attempt invalidated."))
        #expect(snapshot.applicationPayloadCount == 0)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .blocked(reason: "Authenticated read-only attempt invalidated."))
    }

    @Test("authentication failure retires token so late success cannot revive attempt")
    func authenticationFailureIsTerminal() async throws {
        let clock = TestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticationFailed(for: token)
        clock.advance(to: 2_500)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        }
        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.authenticationState == .failed(reason: "Tuya authentication failed."))
        #expect(snapshot.authenticationMethod == nil)
    }
}

private final class TestUptimeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64
    init(_ value: UInt64) { self.value = value }
    var now: @Sendable () -> UInt64 { { [self] in lock.lock(); defer { lock.unlock() }; return value } }
    func advance(to newValue: UInt64) { lock.lock(); value = newValue; lock.unlock() }
}
