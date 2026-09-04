import Foundation
import Testing
@testable import NembraBluetoothCapture

struct C7D09A22AuthenticatedSnapshotChronologyIngressTests {
    @Test
    @MainActor
    func preferredBeginDerivesConnectionChronologyFromAuthenticatedPackageSnapshot() async throws {
        let ledger = TuyaAuthenticatedReadOnlySessionLedger()
        let token = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: token)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        let snapshot = await ledger.currentPreflightSnapshot()

        #expect(snapshot.connectionStartedAtUptimeNanoseconds != nil)
        #expect(snapshot.authenticatedAtUptimeNanoseconds != nil)

        let ingress = C7D09A22DocumentedTransparentReceiveIngress()
        #expect(await ingress.begin(
            connectionToken: token,
            expectedDeviceID: " demo ",
            authenticatedPreflightSnapshot: snapshot
        ))
        #expect(ingress.hasActiveGeneration)

        let payload = Data([0xA5, 0x5A, 0x01])
        let receipt = try #require(ingress.capture(payload: payload, callbackDeviceID: "demo"))
        #expect(receipt.capturedConnectionGeneration == token.diagnosticGeneration)

        _ = await ingress.record(receipt, preflightSnapshot: snapshot)
        let diagnostic = try #require(await ingress.diagnosticSnapshot())
        #expect(diagnostic.payloadCount == 1)
        #expect(diagnostic.totalByteCount == payload.count)
        #expect(!diagnostic.authorizesRawFD50CharacteristicCustody)
        #expect(!diagnostic.authorizesPhysicalFirstAcceptance)
        #expect(!diagnostic.authorizesTelemetrySemantics)
        #expect(!diagnostic.authorizesControlWrites)
        #expect(!diagnostic.authorizesPairingResetOrUnbind)
    }

    @Test
    @MainActor
    func preferredBeginRejectsSnapshotFromDifferentPackageGeneration() async throws {
        let firstLedger = TuyaAuthenticatedReadOnlySessionLedger()
        let firstToken = try await firstLedger.beginConnection()
        try await firstLedger.markAuthenticationStarted(for: firstToken)
        try await firstLedger.markAuthenticated(for: firstToken, method: .smartLifeAppSDK)

        let secondLedger = TuyaAuthenticatedReadOnlySessionLedger()
        _ = try await secondLedger.beginConnection()
        let secondToken = try await secondLedger.beginConnection()
        try await secondLedger.markAuthenticationStarted(for: secondToken)
        try await secondLedger.markAuthenticated(for: secondToken, method: .smartLifeAppSDK)
        let secondSnapshot = await secondLedger.currentPreflightSnapshot()

        let ingress = C7D09A22DocumentedTransparentReceiveIngress()
        #expect(!(await ingress.begin(
            connectionToken: firstToken,
            expectedDeviceID: "demo",
            authenticatedPreflightSnapshot: secondSnapshot
        )))
        #expect(!ingress.hasActiveGeneration)
        #expect(ingress.capture(payload: Data([0x01]), callbackDeviceID: "demo") == nil)
    }
}
