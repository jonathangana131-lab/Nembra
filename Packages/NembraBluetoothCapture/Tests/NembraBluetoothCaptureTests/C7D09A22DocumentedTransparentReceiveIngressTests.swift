import Foundation
import Testing
@testable import NembraBluetoothCapture

struct C7D09A22DocumentedTransparentReceiveIngressTests {
    private func authenticatedContext() async throws -> (
        ledger: TuyaAuthenticatedReadOnlySessionLedger,
        token: TuyaReadOnlyConnectionToken,
        snapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot
    ) {
        let ledger = TuyaAuthenticatedReadOnlySessionLedger()
        let token = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: token)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        return (ledger, token, await ledger.currentPreflightSnapshot())
    }

    @Test
    @MainActor
    func lifecycleFailsClosedBeforeBeginAndAfterRetirement() async throws {
        let ingress = C7D09A22DocumentedTransparentReceiveIngress()
        let payload = Data([0x01, 0x02, 0x03])

        #expect(ingress.capture(payload: payload, callbackDeviceID: "demo") == nil)
        #expect(!ingress.hasActiveGeneration)

        let context = try await authenticatedContext()
        let began = await ingress.begin(
            connectionToken: context.token,
            expectedDeviceID: " demo ",
            sdkConnectionStartedAtUptimeNanoseconds: 1,
            authenticatedPreflightSnapshot: context.snapshot
        )

        #expect(began)
        #expect(ingress.hasActiveGeneration)

        let receipt = ingress.capture(payload: payload, callbackDeviceID: " demo ")
        #expect(receipt != nil)
        #expect(receipt?.payload == payload)
        #expect(receipt?.callbackDeviceID == "demo")
        #expect(receipt?.capturedConnectionGeneration == context.token.diagnosticGeneration)

        await ingress.retire()
        #expect(!ingress.hasActiveGeneration)
        #expect(ingress.capture(payload: payload, callbackDeviceID: "demo") == nil)
    }

    @Test
    @MainActor
    func unauthenticatedGenerationCannotArmIngress() async throws {
        let ingress = C7D09A22DocumentedTransparentReceiveIngress()
        let ledger = TuyaAuthenticatedReadOnlySessionLedger()
        let token = try await ledger.beginConnection()
        let snapshot = await ledger.currentPreflightSnapshot()

        #expect(!(await ingress.begin(
            connectionToken: token,
            expectedDeviceID: "demo",
            sdkConnectionStartedAtUptimeNanoseconds: 1,
            authenticatedPreflightSnapshot: snapshot
        )))
        #expect(!ingress.hasActiveGeneration)
        #expect(ingress.capture(payload: Data([0xAB]), callbackDeviceID: "demo") == nil)
    }

    @Test
    @MainActor
    func rejectsWrongDeviceBeforeGenerationStamping() async throws {
        let ingress = C7D09A22DocumentedTransparentReceiveIngress()
        let context = try await authenticatedContext()

        #expect(await ingress.begin(
            connectionToken: context.token,
            expectedDeviceID: "demo",
            sdkConnectionStartedAtUptimeNanoseconds: 1,
            authenticatedPreflightSnapshot: context.snapshot
        ))

        #expect(ingress.capture(payload: Data([0xAA]), callbackDeviceID: "other-device") == nil)
        #expect(ingress.capture(payload: Data([0xBB]), callbackDeviceID: " demo ") != nil)
    }

    @Test
    @MainActor
    func emptyExpectedDeviceIDCannotArmIngress() async throws {
        let ingress = C7D09A22DocumentedTransparentReceiveIngress()
        let context = try await authenticatedContext()

        #expect(!(await ingress.begin(
            connectionToken: context.token,
            expectedDeviceID: "   ",
            sdkConnectionStartedAtUptimeNanoseconds: 1,
            authenticatedPreflightSnapshot: context.snapshot
        )))
        #expect(!ingress.hasActiveGeneration)
        #expect(ingress.capture(payload: Data([0xCC]), callbackDeviceID: "demo") == nil)
    }

    @Test
    @MainActor
    func newBeginRetiresOldGenerationAndDeviceBeforeAdmittingCallbacks() async throws {
        let ingress = C7D09A22DocumentedTransparentReceiveIngress()
        let first = try await authenticatedContext()

        #expect(await ingress.begin(
            connectionToken: first.token,
            expectedDeviceID: "demo-one",
            sdkConnectionStartedAtUptimeNanoseconds: 1,
            authenticatedPreflightSnapshot: first.snapshot
        ))
        let firstReceipt = ingress.capture(
            payload: Data([0xAA]),
            callbackDeviceID: "demo-one"
        )
        #expect(firstReceipt?.capturedConnectionGeneration == first.token.diagnosticGeneration)

        let secondLedger = TuyaAuthenticatedReadOnlySessionLedger()
        _ = try await secondLedger.beginConnection()
        let secondToken = try await secondLedger.beginConnection()
        try await secondLedger.markAuthenticationStarted(for: secondToken)
        try await secondLedger.markAuthenticated(for: secondToken, method: .smartLifeAppSDK)
        let secondSnapshot = await secondLedger.currentPreflightSnapshot()

        #expect(await ingress.begin(
            connectionToken: secondToken,
            expectedDeviceID: "demo-two",
            sdkConnectionStartedAtUptimeNanoseconds: 2,
            authenticatedPreflightSnapshot: secondSnapshot
        ))

        #expect(ingress.capture(payload: Data([0xBA]), callbackDeviceID: "demo-one") == nil)
        let secondReceipt = ingress.capture(
            payload: Data([0xBB]),
            callbackDeviceID: "demo-two"
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
