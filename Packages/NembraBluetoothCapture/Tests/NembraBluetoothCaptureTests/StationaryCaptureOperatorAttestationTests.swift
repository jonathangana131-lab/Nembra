import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Stationary capture operator attestation")
struct StationaryCaptureOperatorAttestationTests {
    private let attemptID = UUID(uuidString: "63122EBE-8700-4F7F-B7DC-C6AE0F7D9F87")!
    private let receivedAt = Date(timeIntervalSince1970: 1_787_000_000)
    private let attemptStarted: UInt64 = 10_000
    private let receivedAtUptime: UInt64 = 11_000
    private let now: UInt64 = 12_000

    @Test("complete current-attempt declaration is ready without claiming physical truth")
    func completeCurrentAttemptIsReady() {
        let attestation = makeAttestation()

        #expect(attestation.hasCompleteDeclarations)
        #expect(attestation.missingDeclarations.isEmpty)
        #expect(
            StationaryCaptureOperatorAttestationGate.verdict(
                for: attestation,
                currentAttemptID: attemptID,
                attemptStartedAtUptimeNanoseconds: attemptStarted,
                nowUptimeNanoseconds: now
            ) == .readyForOperatorDeclaredStationaryCapture
        )
        #expect(
            attestation.isCompleteForCurrentAttempt(
                currentAttemptID: attemptID,
                attemptStartedAtUptimeNanoseconds: attemptStarted,
                nowUptimeNanoseconds: now
            )
        )
    }

    @Test("all declarations are independent and incomplete input fails closed")
    func incompleteDeclarationsFailClosed() {
        let attestation = makeAttestation(
            declarations: .init(
                stationary: false,
                poweredOff: false,
                chargerDisconnected: false,
                noRiding: false,
                controlsUntouched: false
            )
        )
        let expectedMissing: [StationaryCaptureOperatorAttestation.Declaration] = [
            .stationary,
            .poweredOff,
            .chargerDisconnected,
            .noRiding,
            .controlsUntouched
        ]

        #expect(attestation.missingDeclarations == expectedMissing)
        #expect(!attestation.hasCompleteDeclarations)
        #expect(
            StationaryCaptureOperatorAttestationGate.verdict(
                for: attestation,
                currentAttemptID: attemptID,
                attemptStartedAtUptimeNanoseconds: attemptStarted,
                nowUptimeNanoseconds: now
            ) == .blocked(.incompleteDeclarations(expectedMissing))
        )
    }

    @Test("missing or previous-attempt receipts fail closed")
    func currentAttemptIsRequired() {
        #expect(
            StationaryCaptureOperatorAttestationGate.verdict(
                for: nil,
                currentAttemptID: attemptID,
                attemptStartedAtUptimeNanoseconds: attemptStarted,
                nowUptimeNanoseconds: now
            ) == .blocked(.missingAttestation)
        )
        #expect(
            StationaryCaptureOperatorAttestationGate.verdict(
                for: makeAttestation(),
                currentAttemptID: UUID(),
                attemptStartedAtUptimeNanoseconds: attemptStarted,
                nowUptimeNanoseconds: now
            ) == .blocked(.differentAttempt)
        )
    }

    @Test("monotonic receipt must belong to the current attempt")
    func receiptChronologyMustBeCurrent() {
        let beforeAttempt = makeAttestation(receivedAtUptimeNanoseconds: attemptStarted - 1)
        let fromFuture = makeAttestation(receivedAtUptimeNanoseconds: now + 1)

        for attestation in [beforeAttempt, fromFuture] {
            #expect(
                StationaryCaptureOperatorAttestationGate.verdict(
                    for: attestation,
                    currentAttemptID: attemptID,
                    attemptStartedAtUptimeNanoseconds: attemptStarted,
                    nowUptimeNanoseconds: now
                ) == .blocked(.receiptOutsideCurrentAttempt)
            )
        }
        #expect(
            StationaryCaptureOperatorAttestationGate.verdict(
                for: makeAttestation(),
                currentAttemptID: attemptID,
                attemptStartedAtUptimeNanoseconds: now + 1,
                nowUptimeNanoseconds: now
            ) == .blocked(.receiptOutsideCurrentAttempt)
        )
    }

    @Test("changed wording cannot inherit current procedure authority")
    func exactCurrentWordingIsRequired() {
        let changedWording = StationaryCaptureOperatorAttestation.Wording(
            version: "nembra-stationary-operator-attestation-v2",
            stationaryStatement: "The scooter appears stationary.",
            poweredOffStatement: "The scooter is powered OFF.",
            chargerDisconnectedStatement: "The charger is disconnected.",
            noRidingStatement: "No one will ride the scooter during this capture.",
            controlsUntouchedStatement: "No one will touch the scooter controls during this capture."
        )

        #expect(
            StationaryCaptureOperatorAttestationGate.verdict(
                for: makeAttestation(wording: changedWording),
                currentAttemptID: attemptID,
                attemptStartedAtUptimeNanoseconds: attemptStarted,
                nowUptimeNanoseconds: now
            ) == .blocked(.unsupportedWording)
        )
    }

    @Test("wall-clock and monotonic receipt plus exact wording survive Codable round trip")
    func codableReceiptRoundTrip() throws {
        let original = makeAttestation()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            StationaryCaptureOperatorAttestation.self,
            from: data
        )

        #expect(decoded == original)
        #expect(decoded.attemptID == attemptID)
        #expect(decoded.receivedAt == receivedAt)
        #expect(decoded.receivedAtUptimeNanoseconds == receivedAtUptime)
        #expect(decoded.wording == .current)
        #expect(decoded.declarations.controlsUntouched)
        #expect(decoded.declarations.poweredOff)
    }

    @Test("non-finite wall-clock receipt fails closed")
    func wallClockReceiptMustBeFinite() {
        let invalid = makeAttestation(
            receivedAt: Date(timeIntervalSinceReferenceDate: .infinity)
        )

        #expect(
            StationaryCaptureOperatorAttestationGate.verdict(
                for: invalid,
                currentAttemptID: attemptID,
                attemptStartedAtUptimeNanoseconds: attemptStarted,
                nowUptimeNanoseconds: now
            ) == .blocked(.invalidWallClockReceipt)
        )
    }

    private func makeAttestation(
        receivedAt: Date? = nil,
        receivedAtUptimeNanoseconds: UInt64? = nil,
        wording: StationaryCaptureOperatorAttestation.Wording = .current,
        declarations: StationaryCaptureOperatorAttestation.Declarations = .init(
            stationary: true,
            poweredOff: true,
            chargerDisconnected: true,
            noRiding: true,
            controlsUntouched: true
        )
    ) -> StationaryCaptureOperatorAttestation {
        StationaryCaptureOperatorAttestation(
            attemptID: attemptID,
            receivedAt: receivedAt ?? self.receivedAt,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds ?? receivedAtUptime,
            wording: wording,
            declarations: declarations
        )
    }
}
