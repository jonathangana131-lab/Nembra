import Testing
@testable import NembraBluetoothCapture

struct TuyaDocumentedLocalBLEReadOnlyPreflightTests {
    private let peripheral = "6815A5F5-4D1E-E004-BAE8-6DF924123907"
    private let accountDevice = "tuya-account-device-uuid"

    private func snapshot(
        accountDeviceUUID: String? = nil,
        productKey: String = "account-backed-product-key",
        generation: UInt64 = 9,
        method: TuyaReadOnlyAuthenticationMethod = .smartLifeAppSDK,
        accountAuthenticated: Bool = true,
        adapterBindingProven: Bool = true,
        accountProductKeyProven: Bool = true,
        localBLEOnline: Bool = true
    ) -> TuyaDocumentedLocalBLEReadOnlySnapshot {
        TuyaDocumentedLocalBLEReadOnlySnapshot(
            selectedPeripheralIdentifier: peripheral,
            accountDeviceUUID: accountDeviceUUID ?? accountDevice,
            productKey: productKey,
            connectionGeneration: generation,
            authenticationMethod: method,
            accountSessionAuthenticated: accountAuthenticated,
            sdkAdapterProvesSelectedPeripheralBinding: adapterBindingProven,
            sdkAdapterProvesProductKeyBelongsToAccountDevice: accountProductKeyProven,
            sdkReportsLocalBLEOnline: localBLEOnline
        )
    }

    @Test
    func differentIdentityDomainsAreAdmittedWhenSDKAdapterBindingIsProven() {
        #expect(peripheral != accountDevice)
        #expect(
            TuyaDocumentedLocalBLEReadOnlyPreflight.verdict(for: snapshot()) ==
                .readyForAuthenticatedReceiveObservation
        )
    }

    @Test
    func localBLEStatusIsMandatoryEvenWhenAdapterBindingIsProven() {
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
    func unprovenPeripheralToAccountDeviceBindingFailsClosed() {
        let verdict = TuyaDocumentedLocalBLEReadOnlyPreflight.verdict(
            for: snapshot(adapterBindingProven: false)
        )
        #expect(verdict != .readyForAuthenticatedReceiveObservation)
    }

    @Test
    func productKeyMustBeProvenFromSameLinkedAccountDevice() {
        let verdict = TuyaDocumentedLocalBLEReadOnlyPreflight.verdict(
            for: snapshot(accountProductKeyProven: false)
        )
        #expect(verdict != .readyForAuthenticatedReceiveObservation)
    }

    @Test
    func accountDeviceIdentityProductKeyAndGenerationAreRequired() {
        #expect(
            TuyaDocumentedLocalBLEReadOnlyPreflight.verdict(for: snapshot(accountDeviceUUID: "  ")) !=
                .readyForAuthenticatedReceiveObservation
        )
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
