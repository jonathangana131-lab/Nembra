import Foundation
import Testing
@testable import NembraBluetoothCapture

struct C7D09A22DocumentedTransparentReceiveIngressTests {
    @Test
    @MainActor
    func lifecycleFailsClosedBeforeBeginAndAfterRetirement() async throws {
        let ingress = C7D09A22DocumentedTransparentReceiveIngress()
        let payload = Data([0x01, 0x02, 0x03])

        #expect(ingress.capture(payload: payload, callbackDeviceID: "demo") == nil)
        #expect(!ingress.hasActiveGeneration)

        let ledger = TuyaAuthenticatedReadOnlySessionLedger()
        let token = try await ledger.beginConnection()
        let began = await ingress.begin(
            connectionToken: token,
            expectedDeviceID: "demo",
            sdkConnectionStartedAtUptimeNanoseconds: 1
        )

        #expect(began)
        #expect(ingress.hasActiveGeneration)

        let receipt = ingress.capture(payload: payload, callbackDeviceID: " demo ")
        #expect(receipt != nil)
        #expect(receipt?.payload == payload)
        #expect(receipt?.callbackDeviceID == "demo")
        #expect(receipt?.capturedConnectionGeneration == token.diagnosticGeneration)

        await ingress.retire()
        #expect(!ingress.hasActiveGeneration)
        #expect(ingress.capture(payload: payload, callbackDeviceID: "demo") == nil)
    }

    @Test
    @MainActor
    func newBeginRetiresOldGenerationBeforeAdmittingCallbacks() async throws {
        let ingress = C7D09A22DocumentedTransparentReceiveIngress()
        let ledger = TuyaAuthenticatedReadOnlySessionLedger()

        let firstToken = try await ledger.beginConnection()
        #expect(await ingress.begin(
            connectionToken: firstToken,
            expectedDeviceID: "demo",
            sdkConnectionStartedAtUptimeNanoseconds: 1
        ))
        let firstReceipt = ingress.capture(
            payload: Data([0xAA]),
            callbackDeviceID: "demo"
        )
        #expect(firstReceipt?.capturedConnectionGeneration == firstToken.diagnosticGeneration)

        let secondToken = try await ledger.beginConnection()
        #expect(await ingress.begin(
            connectionToken: secondToken,
            expectedDeviceID: "demo",
            sdkConnectionStartedAtUptimeNanoseconds: 2
        ))
        let secondReceipt = ingress.capture(
            payload: Data([0xBB]),
            callbackDeviceID: "demo"
        )

        #expect(secondReceipt?.capturedConnectionGeneration == secondToken.diagnosticGeneration)
        #expect(secondReceipt?.capturedConnectionGeneration != firstReceipt?.capturedConnectionGeneration)
        #expect(!ingress.authorizesRawFD50CharacteristicCustody)
        #expect(!ingress.authorizesPhysicalFirstAcceptance)
        #expect(!ingress.authorizesStationaryMapping)
        #expect(!ingress.authorizesTelemetrySemantics)
        #expect(!ingress.authorizesControlWrites)
        #expect(!ingress.authorizesPairingResetOrUnbind)
    }
}
