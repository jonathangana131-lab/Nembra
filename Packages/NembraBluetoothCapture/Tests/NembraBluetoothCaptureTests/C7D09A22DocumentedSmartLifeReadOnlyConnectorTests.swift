import Testing
@testable import NembraBluetoothCapture

struct C7D09A22DocumentedSmartLifeReadOnlyConnectorTests {
    private func c7d09a22Identity() throws -> C7D09A22DocumentedSmartLifeReadOnlyConnector.LinkedDeviceIdentity {
        try #require(
            C7D09A22DocumentedSmartLifeReadOnlyConnector.LinkedDeviceIdentity(
                deviceID: "demo",
                uuid: "6815A5F5-4D1E-E004-BAE8-6DF924123907",
                productID: "FD50"
            )
        )
    }

    @Test
    @MainActor
    func linkedAccountIdentityRoutesOnlyDocumentedAuthenticatedConnectInputs() async throws {
        let identity = try c7d09a22Identity()
        let connector = C7D09A22DocumentedSmartLifeReadOnlyConnector()
        var observedUUID: String?
        var observedProductID: String?

        _ = try await connector.connect(identity: identity) { uuid, productID in
            observedUUID = uuid
            observedProductID = productID
            // This closure models the app's official Smart Life SDK connect + exact-UUID
            // SDK-local-online observation. It deliberately has no DP/write/reset API.
        }

        #expect(observedUUID == identity.uuid)
        #expect(observedProductID == identity.productID)

        let snapshot = await connector.currentPreflightSnapshot()
        #expect(snapshot.authenticationState == .authenticated)
        #expect(snapshot.authenticationMethod == .smartLifeAppSDK)
        #expect(snapshot.hasActiveCallbackAuthority)
        #expect(connector.authorizesRawFD50CharacteristicCustody == false)
        #expect(connector.authorizesTelemetrySemantics == false)
        #expect(connector.authorizesControlWrites == false)
        #expect(connector.authorizesPairingResetOrUnbind == false)
    }

    @Test
    @MainActor
    func exactUUIDSDKOnlineObservationIsRequiredBeforeSurvivalClockAdvances() async throws {
        let identity = try c7d09a22Identity()
        let connector = C7D09A22DocumentedSmartLifeReadOnlyConnector()
        _ = try await connector.connect(identity: identity) { _, _ in }

        let before = await connector.currentPreflightSnapshot()
        var observedUUID: String?
        var rejectedOfflineObservation = false

        do {
            try await connector.observeAuthenticatedConnection { uuid in
                observedUUID = uuid
                return false
            }
        } catch {
            rejectedOfflineObservation = true
            #expect(
                error as? C7D09A22DocumentedSmartLifeReadOnlyConnector.ConnectError ==
                    .exactUUIDNotObservedOnline
            )
        }

        #expect(rejectedOfflineObservation)
        #expect(observedUUID == identity.uuid)
        let afterRejectedObservation = await connector.currentPreflightSnapshot()
        #expect(
            afterRejectedObservation.latestObservedUptimeNanoseconds ==
                before.latestObservedUptimeNanoseconds
        )

        try await connector.observeAuthenticatedConnection { uuid in
            #expect(uuid == identity.uuid)
            return true
        }

        let afterAcceptedObservation = await connector.currentPreflightSnapshot()
        #expect(afterAcceptedObservation.latestObservedUptimeNanoseconds != nil)
        if let previous = before.latestObservedUptimeNanoseconds,
           let accepted = afterAcceptedObservation.latestObservedUptimeNanoseconds {
            #expect(accepted >= previous)
        }
        #expect(afterAcceptedObservation.authenticationMethod == .smartLifeAppSDK)
        #expect(afterAcceptedObservation.hasActiveCallbackAuthority)
    }

    @Test
    @MainActor
    func sdkLivenessCheckFailureCannotManufactureConnectionSurvival() async throws {
        enum ProbeFailure: Error { case unavailable }

        let identity = try c7d09a22Identity()
        let connector = C7D09A22DocumentedSmartLifeReadOnlyConnector()
        _ = try await connector.connect(identity: identity) { _, _ in }
        let before = await connector.currentPreflightSnapshot()

        var rejected = false
        do {
            try await connector.observeAuthenticatedConnection { uuid in
                #expect(uuid == identity.uuid)
                throw ProbeFailure.unavailable
            }
        } catch {
            rejected = true
            #expect(
                error as? C7D09A22DocumentedSmartLifeReadOnlyConnector.ConnectError ==
                    .sdkLivenessObservationFailed
            )
        }

        #expect(rejected)
        let after = await connector.currentPreflightSnapshot()
        #expect(after.latestObservedUptimeNanoseconds == before.latestObservedUptimeNanoseconds)
    }

    @Test
    @MainActor
    func adoptsExactLiveAppTokenWithoutCreatingOrRetiringAnotherGeneration() async throws {
        let identity = try c7d09a22Identity()
        let ledger = TuyaAuthenticatedReadOnlySessionLedger()
        let liveAppToken = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: liveAppToken)
        try await ledger.markAuthenticated(for: liveAppToken, method: .smartLifeAppSDK)

        let beforeAdoption = try await ledger.currentPreflightSnapshot(for: liveAppToken)
        let connector = C7D09A22DocumentedSmartLifeReadOnlyConnector(ledger: ledger)
        try await connector.adoptAuthenticatedSession(
            identity: identity,
            connectionToken: liveAppToken
        )

        let afterAdoption = try await ledger.currentPreflightSnapshot(for: liveAppToken)
        #expect(afterAdoption.connectionGeneration == liveAppToken.diagnosticGeneration)
        #expect(afterAdoption.connectionGeneration == beforeAdoption.connectionGeneration)
        #expect(afterAdoption.connectionStartedAtUptimeNanoseconds == beforeAdoption.connectionStartedAtUptimeNanoseconds)
        #expect(afterAdoption.authenticatedAtUptimeNanoseconds == beforeAdoption.authenticatedAtUptimeNanoseconds)
        #expect(afterAdoption.latestObservedUptimeNanoseconds == beforeAdoption.latestObservedUptimeNanoseconds)
        #expect(afterAdoption.authenticationMethod == .smartLifeAppSDK)
        #expect(afterAdoption.hasActiveCallbackAuthority)

        await connector.retire()

        // Adoption is evidence custody only. Retiring the coordinator must not retire the
        // live app's authenticated callback authority or create a replacement generation.
        let afterEvidenceRetirement = try await ledger.currentPreflightSnapshot(for: liveAppToken)
        #expect(afterEvidenceRetirement.connectionGeneration == liveAppToken.diagnosticGeneration)
        #expect(afterEvidenceRetirement.authenticationState == .authenticated)
        #expect(afterEvidenceRetirement.hasActiveCallbackAuthority)
    }

    @Test
    @MainActor
    func rejectsForeignLedgerTokenInsteadOfSplittingAuthenticationFromEvidence() async throws {
        let identity = try c7d09a22Identity()
        let liveLedger = TuyaAuthenticatedReadOnlySessionLedger()
        let foreignLedger = TuyaAuthenticatedReadOnlySessionLedger()
        let liveToken = try await liveLedger.beginConnection()
        try await liveLedger.markAuthenticationStarted(for: liveToken)
        try await liveLedger.markAuthenticated(for: liveToken, method: .smartLifeAppSDK)

        let connector = C7D09A22DocumentedSmartLifeReadOnlyConnector(ledger: foreignLedger)
        var rejected = false
        do {
            try await connector.adoptAuthenticatedSession(
                identity: identity,
                connectionToken: liveToken
            )
        } catch {
            rejected = true
            #expect(
                error as? C7D09A22DocumentedSmartLifeReadOnlyConnector.ConnectError ==
                    .existingAuthenticatedSessionInvalid
            )
        }

        #expect(rejected)
        let liveSnapshot = try await liveLedger.currentPreflightSnapshot(for: liveToken)
        #expect(liveSnapshot.authenticationState == .authenticated)
        #expect(liveSnapshot.hasActiveCallbackAuthority)
    }

    @Test
    @MainActor
    func rejectsNonSmartLifeAuthenticatedTokenWithoutRetiringLiveAuthority() async throws {
        let identity = try c7d09a22Identity()
        let ledger = TuyaAuthenticatedReadOnlySessionLedger()
        let token = try await ledger.beginConnection()
        try await ledger.markAuthenticationStarted(for: token)
        try await ledger.markAuthenticated(for: token, method: .documentedDeviceSharing)

        let connector = C7D09A22DocumentedSmartLifeReadOnlyConnector(ledger: ledger)
        var rejected = false
        do {
            try await connector.adoptAuthenticatedSession(identity: identity, connectionToken: token)
        } catch {
            rejected = true
            #expect(
                error as? C7D09A22DocumentedSmartLifeReadOnlyConnector.ConnectError ==
                    .existingAuthenticatedSessionInvalid
            )
        }

        #expect(rejected)
        let snapshot = try await ledger.currentPreflightSnapshot(for: token)
        #expect(snapshot.authenticationState == .authenticated)
        #expect(snapshot.hasActiveCallbackAuthority)
    }

    @Test
    @MainActor
    func rejectsIncompleteLinkedAccountIdentityBeforeAnySessionCanExist() async {
        #expect(
            C7D09A22DocumentedSmartLifeReadOnlyConnector.LinkedDeviceIdentity(
                deviceID: "demo",
                uuid: "   ",
                productID: "FD50"
            ) == nil
        )
    }
}
