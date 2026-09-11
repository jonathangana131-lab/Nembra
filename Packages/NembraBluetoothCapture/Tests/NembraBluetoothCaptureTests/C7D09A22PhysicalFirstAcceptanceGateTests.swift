import Foundation
import Testing
@testable import NembraBluetoothCapture

struct C7D09A22PhysicalFirstAcceptanceGateTests {
    private func readyPreflight() -> TuyaAuthenticatedReadOnlyPreflightSnapshot {
        TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 0,
            authenticatedAtUptimeNanoseconds: 1_000_000_000,
            latestObservedUptimeNanoseconds: 46_000_000_000,
            applicationPayloadCount: 2,
            latestApplicationPayloadUptimeNanoseconds: 31_000_000_001,
            connectionGeneration: 1
        )
    }

    private func qualifyingEvidence(
        rawNotifyPayloadCount: Int = 2,
        rawNotifyObservedAfterAuthentication: Bool = true,
        canonicalFD50CharacteristicTupleProven: Bool = true,
        sameAuthenticatedTransportCustodyProven: Bool = true,
        rawNotifyConnectionGeneration: UInt64? = 1,
        latestRawNotifyUptimeNanoseconds: UInt64? = 31_000_000_001,
        retainedRawNotifyPayloads: [Data] = [Data([0x01]), Data([0x02])]
    ) -> C7D09A22PhysicalFirstAcceptanceGate.Evidence {
        C7D09A22PhysicalFirstAcceptanceGate.Evidence(
            authenticatedPreflight: readyPreflight(),
            rawNotifyPayloadCount: rawNotifyPayloadCount,
            rawNotifyObservedAfterAuthentication: rawNotifyObservedAfterAuthentication,
            canonicalFD50CharacteristicTupleProven: canonicalFD50CharacteristicTupleProven,
            sameAuthenticatedTransportCustodyProven: sameAuthenticatedTransportCustodyProven,
            rawNotifyConnectionGeneration: rawNotifyConnectionGeneration,
            latestRawNotifyUptimeNanoseconds: latestRawNotifyUptimeNanoseconds,
            retainedRawNotifyPayloads: retainedRawNotifyPayloads
        )
    }

    @Test
    func sdkOnlyEvidenceCannotClaimPhysicalFirstAcceptance() {
        let evidence = C7D09A22PhysicalFirstAcceptanceGate.Evidence(
            authenticatedPreflight: readyPreflight(),
            rawNotifyPayloadCount: 0,
            rawNotifyObservedAfterAuthentication: false,
            canonicalFD50CharacteristicTupleProven: false,
            sameAuthenticatedTransportCustodyProven: false
        )

        #expect(C7D09A22PhysicalFirstAcceptanceGate.verdict(for: evidence) != .accepted)
        #expect(!C7D09A22PhysicalFirstAcceptanceGate.authorizesStationarySemanticMapping(for: evidence))
        #expect(!C7D09A22PhysicalFirstAcceptanceGate.authorizesTelemetrySemantics(for: evidence))
        #expect(!C7D09A22PhysicalFirstAcceptanceGate.authorizesControlWrites(for: evidence))
        #expect(!C7D09A22PhysicalFirstAcceptanceGate.authorizesPairingResetOrUnbind(for: evidence))
    }

    @Test
    func rawNotifyMustBeCanonicalSameTransportAndSameGeneration() {
        let missingTransportCustody = qualifyingEvidence(sameAuthenticatedTransportCustodyProven: false)
        #expect(C7D09A22PhysicalFirstAcceptanceGate.verdict(for: missingTransportCustody) != .accepted)
        #expect(!C7D09A22PhysicalFirstAcceptanceGate.authorizesStationarySemanticMapping(for: missingTransportCustody))

        let missingGeneration = qualifyingEvidence(rawNotifyConnectionGeneration: nil)
        #expect(C7D09A22PhysicalFirstAcceptanceGate.verdict(for: missingGeneration) != .accepted)

        let staleGeneration = qualifyingEvidence(rawNotifyConnectionGeneration: 2)
        #expect(C7D09A22PhysicalFirstAcceptanceGate.verdict(for: staleGeneration) != .accepted)
        #expect(!C7D09A22PhysicalFirstAcceptanceGate.authorizesStationarySemanticMapping(for: staleGeneration))
    }

    @Test
    func summaryClaimsCannotReplaceRepeatedRetainedRawBytes() {
        let oneRetainedPayload = qualifyingEvidence(
            rawNotifyPayloadCount: 2,
            retainedRawNotifyPayloads: [Data([0x01])]
        )
        #expect(C7D09A22PhysicalFirstAcceptanceGate.verdict(for: oneRetainedPayload) != .accepted)

        let mismatchedSummary = qualifyingEvidence(rawNotifyPayloadCount: 3)
        #expect(C7D09A22PhysicalFirstAcceptanceGate.verdict(for: mismatchedSummary) != .accepted)

        let emptyRetainedPayload = qualifyingEvidence(
            retainedRawNotifyPayloads: [Data([0x01]), Data()]
        )
        #expect(C7D09A22PhysicalFirstAcceptanceGate.verdict(for: emptyRetainedPayload) != .accepted)
    }

    @Test
    func rawNotifyItselfMustCrossHistoricalPostAuthenticationRejectionWindow() {
        let earlyNotify = qualifyingEvidence(latestRawNotifyUptimeNanoseconds: 31_000_000_000)
        #expect(C7D09A22PhysicalFirstAcceptanceGate.verdict(for: earlyNotify) != .accepted)

        let missingNotifyChronology = qualifyingEvidence(latestRawNotifyUptimeNanoseconds: nil)
        #expect(C7D09A22PhysicalFirstAcceptanceGate.verdict(for: missingNotifyChronology) != .accepted)
    }

    @Test
    func repeatedRetainedPostRejectionNotifyEvidenceAuthorizesOnlyStationaryMapping() {
        let complete = qualifyingEvidence()

        #expect(C7D09A22PhysicalFirstAcceptanceGate.verdict(for: complete) == .accepted)
        #expect(C7D09A22PhysicalFirstAcceptanceGate.authorizesStationarySemanticMapping(for: complete))
        #expect(!C7D09A22PhysicalFirstAcceptanceGate.authorizesTelemetrySemantics(for: complete))
        #expect(!C7D09A22PhysicalFirstAcceptanceGate.authorizesControlWrites(for: complete))
        #expect(!C7D09A22PhysicalFirstAcceptanceGate.authorizesPairingResetOrUnbind(for: complete))
    }
}
