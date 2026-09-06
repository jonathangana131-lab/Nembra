import Testing
@testable import NembraBluetoothCapture

struct TuyaDocumentedLocalBLEReadOnlyPreflightTests {
    private let peripheral = "6815A5F5-4D1E-E004-BAE8-6DF924123907"

    private func snapshot(
        accountMatchedDeviceUUID: String? = nil,
        productKey: String = "account-backed-product-key",
        generation: UInt64 = 9,
        method: TuyaAuthenticationProvenance = .smartLifeAppSDK,
        accountAuthenticated: Bool = true,
        accountMatches: Bool = true,
        localBLEOnline: Bool = true
    ) -> TuyaDocumentedLocalBLEReadOnlySnapshot {
        TuyaDocumentedLocalBLEReadOnlySnapshot(
            selectedPeripheralUUID: peripheral,
            accountMatchedDeviceUUID: accountMatchedDeviceUUID ?? peripheral.lowercased(),
            productKey: productKey,
            connectionGeneration: generation,
            authenticationMethod: method,
            accountSessionAuthenticated: accountAuthenticated,
            boundAccountMatchesSelectedPeripheral: accountMatches,
            sdkReportsLocalBLEOnline: localBLEOnline
        )
    }

    @Test
    func exactAccountBackedSmartLifeLocalBLEStateIsAdmitted() {
        #expect(
            TuyaDocumentedLocalBLEReadOnlyPreflight.verdict(for: snapshot()) ==
                .readyForAuthenticatedReceiveObservation
        )
    }

    @Test
    func localBLEStatusIsMandatoryEvenWhenCloudAccountMatches() {
        let verdict = TuyaDocumentedLocalBLEReadOnlyPreflight.verdict(
            for: snapshot(localBLEOnline: false)
        )
        #expect(verdict != .readyForAuthenticatedReceiveObservation)
    }

    @Test
    func cloudOrSharingProvenanceCannotAuthenticateBLETransport() {
        let verdict = TuyaDocumentedLocalBLEReadOnlyPreflight.verdict(
            for: snapshot(method: .documentedDeviceSharing)
        )
        #expect(verdict != .readyForAuthenticatedReceiveObservation)
    }

    @Test
    func selectedPeripheralMustMatchAccountBackedDeviceExactly() {
        let verdict = TuyaDocumentedLocalBLEReadOnlyPreflight.verdict(
            for: snapshot(accountMatchedDeviceUUID: "00000000-0000-0000-0000-000000000000")
        )
        #expect(verdict != .readyForAuthenticatedReceiveObservation)
    }

    @Test
    func productKeyAndGenerationAreRequired() {
        #expect(
            TuyaDocumentedLocalBLEReadOnlyPreflight.verdict(for: snapshot(productKey: "  ")) !=
                .readyForAuthenticatedReceiveObservation
        )
        #expect(
            TuyaDocumentedLocalBLEReadOnlyPreflight.verdict(for: snapshot(generation: 0)) !=
                .readyForAuthenticatedReceiveObservation
        )
    }

    @Test
    func admissionNeverGrantsMutationOrSemantics() {
        #expect(!TuyaDocumentedLocalBLEReadOnlyPreflight.authorizesPairingOrActivation)
        #expect(!TuyaDocumentedLocalBLEReadOnlyPreflight.authorizesDPWrites)
        #expect(!TuyaDocumentedLocalBLEReadOnlyPreflight.authorizesTransparentWrites)
        #expect(!TuyaDocumentedLocalBLEReadOnlyPreflight.authorizesFirmwareUpdate)
        #expect(!TuyaDocumentedLocalBLEReadOnlyPreflight.authorizesResetRemovalOrUnbind)
        #expect(!TuyaDocumentedLocalBLEReadOnlyPreflight.authorizesTelemetrySemantics)
        #expect(!TuyaDocumentedLocalBLEReadOnlyPreflight.authorizesPhysicalFirstAcceptance)
    }
}
