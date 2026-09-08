import Testing
@testable import NembraBluetoothCapture

@Suite("C7D09A22 documented transport physical boundary")
struct C7D09A22DocumentedTransportPhysicalBoundaryTests {
    @Test("documented Smart Life transport evidence cannot promote raw FD50 or scooter semantics")
    @MainActor
    func documentedTransportRemainsBelowPhysicalFirstAcceptance() async {
        let preflight = C7D09A22DocumentedTransparentLivePreflight(
            preflightSnapshotProvider: { nil }
        )

        #expect(!preflight.authorizesRawFD50CharacteristicCustody)
        #expect(!preflight.authorizesPhysicalFirstAcceptance)
        #expect(!preflight.authorizesStationaryMapping)
        #expect(!preflight.authorizesTelemetrySemantics)
        #expect(!preflight.authorizesControlWrites)
        #expect(!preflight.authorizesPairingResetOrUnbind)

        let evidence = await preflight.fieldAttemptEvidence()
        #expect(!evidence.satisfiesDocumentedAuthenticatedTransportAcceptance)
        #expect(!evidence.authorizesRawFD50CharacteristicCustody)
        #expect(!evidence.authorizesPhysicalFirstAcceptance)
        #expect(!evidence.authorizesStationaryMapping)
        #expect(!evidence.authorizesTelemetrySemantics)
        #expect(!evidence.authorizesControlWrites)
        #expect(!evidence.authorizesPairingResetOrUnbind)
    }
}
