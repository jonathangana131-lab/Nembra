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

        let snapshot = await secondLedger.currentPreflightSnapshot()
        #expect(snapshot.authenticationState == .authenticating)
        #expect(snapshot.authenticationMethod == nil)
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

    @Test("official provenance plus repeated surviving application observation earns canonical gate")
    func acceptedGateUsesContinuousChronology() async throws {
        let clock = TestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        let secondPayload = 2_000
            + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
            + 1
        try await advanceLedgerContinuously(
            clock: clock,
            ledger: ledger,
            token: token,
            from: 3_000,
            through: secondPayload - 1
        )
        clock.advance(to: secondPayload)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        let target = 2_000 + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds
        try await advanceLedgerContinuously(
            clock: clock,
            ledger: ledger,
            token: token,
            from: secondPayload,
            through: target
        )

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.authenticationMethod == .smartLifeAppSDK)
        #expect(snapshot.applicationPayloadCount == 2)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == secondPayload)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .readyForStationaryMapping)
    }

    @Test("accepted horizon becomes immutable before UI success")
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

        let secondPayload = 2_000
            + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
            + 1
        try await advanceLedgerContinuously(
            clock: clock,
            ledger: ledger,
            token: token,
            from: 3_000,
            through: secondPayload - 1
        )
        clock.advance(to: secondPayload)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)

        let target = 2_000 + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds
        try await advanceLedgerContinuously(
            clock: clock,
            ledger: ledger,
            token: token,
            from: secondPayload,
            through: target
        )
        try await ledger.sealAcceptedObservation(for: token)
        let sealed = await ledger.currentPreflightSnapshot()

        clock.advance(to: 90_000_000_000)
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

    @Test("post-auth incomplete-evidence deadline is terminal without inventing disconnect")
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
        let reason = "Authenticated session ended because required repeated application evidence did not become sufficient before the observation deadline."

        #expect(failed.authenticationState == .failed(reason: reason))
        #expect(failed.authenticationMethod == .smartLifeAppSDK)
        #expect(failed.authenticatedAtUptimeNanoseconds == 2_000)
        #expect(failed.applicationPayloadCount == 0)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: failed) == .blocked(reason: reason))

        clock.advance(to: 61_000_002_000)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == failed)
    }

    @Test("continuity invalidation preserves the last witnessed liveness instead of fabricating disconnect")
    func continuityInvalidationFreezesEarnedChronology() async throws {
        let clock = TestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        clock.advance(to: 4_000)
        try await ledger.observeCurrentConnection(for: token)
        let beforeGap = await ledger.currentPreflightSnapshot()

        clock.advance(to: 6_000_004_001)
        try await ledger.markObservationContinuityInvalidated(for: token)
        let failed = await ledger.currentPreflightSnapshot()

        #expect(failed.authenticationState == .failed(reason: "Authenticated observation continuity was invalidated by a long observation gap."))
        #expect(failed.authenticationMethod == beforeGap.authenticationMethod)
        #expect(failed.authenticatedAtUptimeNanoseconds == beforeGap.authenticatedAtUptimeNanoseconds)
        #expect(failed.applicationPayloadCount == beforeGap.applicationPayloadCount)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == beforeGap.latestApplicationPayloadUptimeNanoseconds)
        #expect(failed.latestObservedUptimeNanoseconds == beforeGap.latestObservedUptimeNanoseconds)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.observeCurrentConnection(for: token)
        }
    }

    @Test("automatic long-gap admission failure uses the same terminal identity and freezes last liveness")
    func automaticGapInvalidationUsesCanonicalReason() async throws {
        let clock = TestUptimeClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 150)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 200)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        let beforeGap = await ledger.currentPreflightSnapshot()

        clock.advance(to: 200 + TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds + 1)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated) {
            try await ledger.observeCurrentConnection(for: token)
        }
        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Authenticated observation continuity was invalidated by a long observation gap."))
        #expect(failed.latestObservedUptimeNanoseconds == beforeGap.latestObservedUptimeNanoseconds)
    }

    @Test("late SDK failure revokes authority without manufacturing terminal liveness")
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
        let beforeFailure = await ledger.currentPreflightSnapshot()
        clock.advance(to: 400)
        try await ledger.markAuthenticationFailed(for: token)

        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Tuya SDK session failed."))
        #expect(failed.authenticationMethod == beforeFailure.authenticationMethod)
        #expect(failed.authenticatedAtUptimeNanoseconds == beforeFailure.authenticatedAtUptimeNanoseconds)
        #expect(failed.applicationPayloadCount == beforeFailure.applicationPayloadCount)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == beforeFailure.latestApplicationPayloadUptimeNanoseconds)
        #expect(failed.latestObservedUptimeNanoseconds == beforeFailure.latestObservedUptimeNanoseconds)
        #expect(failed.latestObservedUptimeNanoseconds == 300)
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
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        let before = await ledger.currentPreflightSnapshot()

        clock.advance(to: 5_999)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed) {
            try await ledger.observeCurrentConnection(for: token)
        }
        #expect(await ledger.currentPreflightSnapshot() == before)
    }

    @Test("disconnect remains a distinct transport-loss terminal")
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

    @Test("pre-cut application delivery remains pre-cut when actor admission happens after the deadline")
    func delayedApplicationAdmissionUsesLedgerDeliveryTime() async throws {
        let clock = TestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        let deliveredAt: UInt64 = 3_000
        clock.advance(to: deliveredAt)
        let receipt = try ledger.captureApplicationReceipt(isNonEmpty: true, for: token)

        clock.advance(
            to: 2_000
                + TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds
                + 10_000
        )
        try await ledger.recordApplicationUpdate(
            receipt: receipt,
            for: token
        )

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == deliveredAt)
        #expect(snapshot.latestObservedUptimeNanoseconds == deliveredAt)
    }

    @Test("one application receipt cannot be replayed into repeated physical-readiness count")
    func applicationReceiptIsOneShot() async throws {
        let clock = TestUptimeClock(10)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await authenticatedToken(ledger: ledger, clock: clock, base: 10)

        clock.advance(to: 20)
        let receipt = try ledger.captureApplicationReceipt(isNonEmpty: true, for: token)
        try await ledger.recordApplicationUpdate(receipt: receipt, for: token)

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationAdmissionInvalidOrConsumed) {
            try await ledger.recordApplicationUpdate(receipt: receipt, for: token)
        }
        #expect((await ledger.currentPreflightSnapshot()).applicationPayloadCount == 1)
    }

    @Test("pending application delivery prevents the package from issuing a later watchdog receipt")
    func packageArbitratesApplicationBeforeLiveness() async throws {
        let clock = TestUptimeClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await authenticatedToken(ledger: ledger, clock: clock, base: 100)

        clock.advance(to: 110)
        let applicationReceipt = try ledger.captureApplicationReceipt(isNonEmpty: true, for: token)

        #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.applicationAdmissionPending) {
            _ = try ledger.captureLivenessReceipt(for: token)
        }

        ledger.releaseApplicationReceipt(applicationReceipt)
        let livenessReceipt = try ledger.captureLivenessReceipt(for: token)
        try await ledger.observeCurrentConnection(receipt: livenessReceipt, for: token)
    }

    @Test("liveness delivery time stays in the ledger clock domain even if actor execution is delayed")
    func delayedLivenessAdmissionUsesLedgerDeliveryTime() async throws {
        let clock = TestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        let observedAt: UInt64 = 3_000
        clock.advance(to: observedAt)
        let receipt = try ledger.captureLivenessReceipt(for: token)
        clock.advance(
            to: 2_000
                + TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds
                + 10_000
        )
        try await ledger.observeCurrentConnection(receipt: receipt, for: token)

        #expect((await ledger.currentPreflightSnapshot()).latestObservedUptimeNanoseconds == observedAt)
    }

    @Test("an earlier liveness receipt finishing after a later application receipt is harmless and one-shot")
    func olderLivenessActorCompletionCannotRegressAcceptedApplicationChronology() async throws {
        let clock = TestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        clock.advance(to: 3_000)
        let acceptedPriorLiveness = try ledger.captureLivenessReceipt(for: token)
        try await ledger.observeCurrentConnection(receipt: acceptedPriorLiveness, for: token)

        clock.advance(to: 4_000)
        let earlierLiveness = try ledger.captureLivenessReceipt(for: token)
        clock.advance(to: 4_500)
        let laterApplication = try ledger.captureApplicationReceipt(isNonEmpty: true, for: token)

        // Deliberately execute the later actor mutation first to model actor scheduling inversion.
        try await ledger.recordApplicationUpdate(receipt: laterApplication, for: token)
        try await ledger.observeCurrentConnection(receipt: earlierLiveness, for: token)

        let snapshot = await ledger.currentPreflightSnapshot()
        #expect(snapshot.applicationPayloadCount == 1)
        #expect(snapshot.latestApplicationPayloadUptimeNanoseconds == 4_500)
        #expect(snapshot.latestObservedUptimeNanoseconds == 4_500)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationAdmissionInvalidOrConsumed) {
            try await ledger.observeCurrentConnection(receipt: earlierLiveness, for: token)
        }
    }

    @Test("receipt from another exact ledger issuer cannot be consumed")
    func receiptCannotCrossLedgerIssuer() async throws {
        let clock = TestUptimeClock(1_000)
        let firstLedger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let firstToken = try await authenticatedToken(ledger: firstLedger, clock: clock, base: 1_000)
        clock.advance(to: 1_010)
        let foreignReceipt = try firstLedger.captureApplicationReceipt(isNonEmpty: true, for: firstToken)

        clock.advance(to: 2_000)
        let secondLedger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let secondToken = try await authenticatedToken(ledger: secondLedger, clock: clock, base: 2_000)

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationAdmissionInvalidOrConsumed) {
            try await secondLedger.recordApplicationUpdate(
                isNonEmpty: true,
                receipt: foreignReceipt,
                for: secondToken
            )
        }
        #expect((await secondLedger.currentPreflightSnapshot()).applicationPayloadCount == 0)
        firstLedger.releaseApplicationReceipt(foreignReceipt)
    }

    @Test("application receipt delivered at the strict incomplete horizon cannot rescue the generation")
    func deadlineApplicationReceiptRemainsTerminal() async throws {
        let clock = TestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        let authenticatedAt: UInt64 = 2_000
        clock.advance(to: authenticatedAt)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)

        let deadline = authenticatedAt
            + TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds
        var cursor = authenticatedAt
        let step = TuyaAuthenticatedReadOnlySessionLedger.maximumContinuousObservationGapNanoseconds - 1
        while cursor + step < deadline {
            cursor += step
            clock.advance(to: cursor)
            let liveness = try ledger.captureLivenessReceipt(for: token)
            try await ledger.observeCurrentConnection(receipt: liveness, for: token)
        }
        clock.advance(to: deadline - 1)
        let finalLiveness = try ledger.captureLivenessReceipt(for: token)
        try await ledger.observeCurrentConnection(receipt: finalLiveness, for: token)

        clock.advance(to: deadline)
        let receipt = try ledger.captureApplicationReceipt(isNonEmpty: true, for: token)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached) {
            try await ledger.recordApplicationUpdate(receipt: receipt, for: token)
        }

        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.applicationPayloadCount == 0)
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: failed) != .readyForStationaryMapping)
        #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            _ = try ledger.captureLivenessReceipt(for: token)
        }
    }

    private func authenticatedToken(
        ledger: TuyaAuthenticatedReadOnlySessionLedger,
        clock: TestUptimeClock,
        base: UInt64
    ) async throws -> TuyaReadOnlyConnectionToken {
        clock.advance(to: base)
        let token = try await ledger.beginConnection()
        clock.advance(to: base + 1)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: base + 2)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        return token
    }

    @Test("package seal refuses while an exact application delivery receipt is pending")
    func acceptedSealCannotOvertakePendingApplicationReceipt() async throws {
        let clock = TestUptimeClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.advance(to: 1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.advance(to: 2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.advance(to: 3_000)
        let pending = try ledger.captureApplicationReceipt(isNonEmpty: true, for: token)

        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.applicationAdmissionPending) {
            try await ledger.sealAcceptedObservation(for: token)
        }
        ledger.releaseApplicationReceipt(pending)
        #expect((await ledger.currentPreflightSnapshot()).applicationPayloadCount == 0)
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
