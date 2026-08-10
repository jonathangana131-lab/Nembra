import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated read-only session ledger")
struct TuyaAuthenticatedReadOnlySessionLedgerTests {
    @Test("reconnect clears provenance and prior payload authority")
    func reconnectClearsPriorEvidence() async throws {
        let clock = TestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let first = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: first)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: first, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: first)
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
        clock.advance(to: 25)
        try await ledger.markAuthenticationStarted(for: second)
        clock.advance(to: 30)
        try await ledger.markAuthenticated(for: second, method: .smartLifeAppSDK)
        clock.advance(to: 40)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: first)
        }
        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.connectionGeneration == second.diagnosticGeneration)
        #expect(snapshot.applicationPayloadCount == 0)
    }

    @Test("same generation from another ledger cannot cross the owner boundary")
    func crossLedgerTokenRejected() async throws {
        let firstClock = TestUptimeClock(10)
        let secondClock = TestUptimeClock(10)
        let firstLedger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: firstClock.now)
        let secondLedger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: secondClock.now)
        let firstToken = try await firstLedger.beginConnection()
        let secondToken = try await secondLedger.beginConnection()
        #expect(firstToken.diagnosticGeneration == secondToken.diagnosticGeneration)
        #expect(firstToken != secondToken)
        secondClock.advance(to: 15)
        try await secondLedger.markAuthenticationStarted(for: secondToken)
        secondClock.advance(to: 20)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection) {
            try await secondLedger.markAuthenticated(for: firstToken, method: .smartLifeAppSDK)
        }
        let secondSnapshot = await secondLedger.currentPreflightSnapshot()
        #expect(secondSnapshot.authenticationState == .authenticating)
        #expect(secondSnapshot.authenticationMethod == nil)
    }

    @Test("authentication success cannot skip authentication-start chronology")
    func authenticationStartIsRequired() async throws {
        let clock = TestUptimeClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        let before = await ledger.currentPreflightSnapshot()
        clock.advance(to: 110)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.invalidAuthenticationTransition) {
            try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        }
        #expect(await ledger.currentPreflightSnapshot() == before)
    }

    @Test("authentication failure cannot skip authentication-start chronology")
    func authenticationFailureStartIsRequired() async throws {
        let clock = TestUptimeClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        let before = await ledger.currentPreflightSnapshot()
        clock.advance(to: 110)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.invalidAuthenticationTransition) {
            try await ledger.markAuthenticationFailed(for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == before)
    }

    @Test("application update admission is post-auth and non-empty")
    func applicationUpdateAdmissionIsFailClosed() async throws {
        let clock = TestUptimeClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 110)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.authenticationRequired) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        clock.advance(to: 120)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 130)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 140)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.emptyApplicationUpdate) {
            try await ledger.recordApplicationUpdate(isNonEmpty: false, for: token)
        }
    }

    @Test("liveness cannot advance before authentication")
    func preAuthLivenessIsRejected() async throws {
        let clock = TestUptimeClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        let before = await ledger.currentPreflightSnapshot()
        clock.advance(to: 200)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.authenticationRequired) {
            try await ledger.observeCurrentConnection(for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == before)
    }

    @Test("official provenance plus application update and continuous exact stability window earns gate")
    func acceptedGateUsesSealedChronology() async throws {
        let clock = TestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        let target = 2_000 + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds
        try await advanceLedgerContinuously(clock: clock, ledger: ledger, token: token, from: 3_000, through: target)
        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.authenticationMethod == .smartLifeAppSDK)
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == 3_000)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .readyForStationaryMapping)
    }

    @Test("accepted horizon is immutable after sealing")
    func acceptedHorizonRejectsLateCallbacks() async throws {
        let clock = TestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        let target = 2_000 + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds
        try await advanceLedgerContinuously(clock: clock, ledger: ledger, token: token, from: 3_000, through: target)
        try await ledger.sealAcceptedObservation(for: token)
        let sealed = await ledger.currentPreflightSnapshot()
        clock.advance(to: target + 1)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.observeCurrentConnection(for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == sealed)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: sealed) == .readyForStationaryMapping)
    }

    @Test("preflight cannot be sealed before canonical readiness")
    func earlySealIsRejected() async throws {
        let clock = TestUptimeClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 150)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 200)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.preflightNotReady) {
            try await ledger.sealAcceptedObservation(for: token)
        }
        clock.advance(to: 300)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
    }

    @Test("post-auth observation timeout is terminal without inventing disconnect")
    func observationTimeoutRejectsLateUpdate() async throws {
        let clock = TestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 60_000_002_000)
        try await ledger.markApplicationObservationTimedOut(for: token)
        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Authenticated session produced no application update before the observation deadline."))
        #expect(failed.authenticationMethod == .smartLifeAppSDK)
        #expect(failed.authenticatedAtUptimeNanoseconds == 2_000)
        #expect(failed.applicationPayloadCount == 0)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: failed) == .blocked(reason: "Authenticated session produced no application update before the observation deadline."))
        clock.advance(to: 61_000_002_000)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == failed)
    }

    @Test("late SDK failure revokes authority without erasing earned chronology")
    func lateSDKFailurePreservesDiagnosticHistory() async throws {
        let clock = TestUptimeClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 150)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 200)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 300)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        clock.advance(to: 400)
        try await ledger.markAuthenticationFailed(for: token)
        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Tuya SDK session failed."))
        #expect(failed.authenticationMethod == .smartLifeAppSDK)
        #expect(failed.authenticatedAtUptimeNanoseconds == 200)
        #expect(failed.applicationPayloadCount == 1)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == 300)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: failed) == .blocked(reason: "Tuya SDK session failed."))
        clock.advance(to: 500)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == failed)
    }

    @Test("clock regression cannot rewrite accepted chronology")
    func clockRegressionFailsClosed() async throws {
        let clock = TestUptimeClock(5_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 5_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 6_000)
        try await ledger.markAuthenticated(for: token, method: .documentedDeviceSharing)
        let before = await ledger.currentPreflightSnapshot()
        clock.advance(to: 5_999)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed) {
            try await ledger.observeCurrentConnection(for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == before)
    }

    @Test("disconnect retires auth provenance and payload authority")
    func disconnectRetiresAuthority() async throws {
        let clock = TestUptimeClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 150)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 200)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 300)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
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
}

private func advanceLedgerContinuously(
    clock: TestUptimeClock,
    ledger: TuyaAuthenticatedReadOnlySessionLedger,
    token: TuyaReadOnlyConnectionToken,
    from start: UInt64,
    through target: UInt64
) async throws {
    var cursor = start
    let gap = TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds
    while cursor < target {
        cursor = min(target, cursor + gap)
        clock.advance(to: cursor)
        try await ledger.observeCurrentConnection(for: token)
    }
}

private final class TestUptimeClock: @unchecked Sendable {
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
