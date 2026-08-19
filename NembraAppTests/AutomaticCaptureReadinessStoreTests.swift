import Foundation
import NembraCore
import XCTest
@testable import Nembra

@MainActor
private final class StubAutomaticCaptureFactsProvider: AutomaticCapturePlatformFactsProviding {
    var base: AutomaticCapturePlatformFacts

    init(base: AutomaticCapturePlatformFacts) {
        self.base = base
    }

    func snapshot(sceneState: AutomaticCaptureAppSceneState) -> AutomaticCapturePlatformFacts {
        AutomaticCapturePlatformFacts(
            relaunchPolicy: base.relaunchPolicy,
            accessorySetupAuthorization: base.accessorySetupAuthorization,
            accessorySetupDescriptor: base.accessorySetupDescriptor,
            knownAccessory: base.knownAccessory,
            bluetoothAuthorization: base.bluetoothAuthorization,
            bluetoothRadioState: base.bluetoothRadioState,
            restorationConfiguration: base.restorationConfiguration,
            backgroundService: base.backgroundService,
            locationAuthorization: base.locationAuthorization,
            backgroundLocationSession: base.backgroundLocationSession,
            lifecycle: base.lifecycle,
            storage: base.storage,
            sceneState: sceneState,
            forceQuitObservability: base.forceQuitObservability,
            firstUnlockEvidence: base.firstUnlockEvidence
        )
    }
}

final class AutomaticCaptureReadinessStoreTests: XCTestCase {
    @MainActor
    func testDisabledPreferenceRemainsOffWhileSetupBlockersStayVisible() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AutomaticCaptureReadinessStore(
            userDefaults: defaults,
            factsProvider: StubAutomaticCaptureFactsProvider(base: blockedFacts()),
            initialSceneState: .active
        )

        XCTAssertEqual(store.readiness.status, .intentionallyDisabled)
        XCTAssertFalse(store.readiness.canCaptureRideTelemetryWithoutOpeningApp)
        XCTAssertEqual(store.setupReadiness.status, .actionRequired)
        XCTAssertTrue(store.blockers.contains { $0.issue == .accessoryDescriptorAbsent })
        XCTAssertTrue(store.blockers.contains { $0.issue == .restorationConfigurationIncomplete })
        XCTAssertEqual(store.settingsRowSubtitle, "Off · setup not complete")
    }

    @MainActor
    func testVerifiedFactsKeepTelemetryAndRoadReadinessSeparateFromUserIntent() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AutomaticCaptureReadinessStore.preferenceKey)
        let store = AutomaticCaptureReadinessStore(
            userDefaults: defaults,
            factsProvider: StubAutomaticCaptureFactsProvider(base: readyFacts()),
            initialSceneState: .active
        )

        XCTAssertEqual(store.readiness.status, .ready)
        XCTAssertTrue(store.readiness.canCaptureRideTelemetryWithoutOpeningApp)
        XCTAssertTrue(store.readiness.canCaptureRoadCoverageWithoutOpeningApp)
        XCTAssertEqual(store.telemetryStatusText, "Best-effort ready")
        XCTAssertEqual(store.roadCoverageStatusText, "Best-effort ready")
        XCTAssertEqual(
            store.readiness.deliveryExpectation,
            .bestEffortSubjectToSystemSchedulingAndLifecycle
        )
    }

    @MainActor
    func testWhileUsingLocationAllowsTelemetryButBlocksAutomaticRoadCoverage() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AutomaticCaptureReadinessStore.preferenceKey)
        let limited = readyFacts(
            locationAuthorization: .whileInUse,
            backgroundLocationSession: .notConfigured
        )
        let store = AutomaticCaptureReadinessStore(
            userDefaults: defaults,
            factsProvider: StubAutomaticCaptureFactsProvider(base: limited),
            initialSceneState: .active
        )

        XCTAssertEqual(store.readiness.status, .locationLimited)
        XCTAssertTrue(store.readiness.canCaptureRideTelemetryWithoutOpeningApp)
        XCTAssertFalse(store.readiness.canCaptureRoadCoverageWithoutOpeningApp)
        XCTAssertEqual(store.roadCoverageStatusText, "Location limited")
        XCTAssertTrue(store.blockers.contains { $0.issue == .locationOnlyWhileInUse })
    }

    @MainActor
    func testRefreshAndRearmNeverManufacturesReadiness() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AutomaticCaptureReadinessStore.preferenceKey)
        let store = AutomaticCaptureReadinessStore(
            userDefaults: defaults,
            factsProvider: StubAutomaticCaptureFactsProvider(base: blockedFacts()),
            initialSceneState: .active
        )

        let before = store.readiness
        store.refreshAndRearm()

        XCTAssertEqual(store.readiness, before)
        XCTAssertFalse(store.readiness.canCaptureRideTelemetryWithoutOpeningApp)
        XCTAssertTrue(store.lastActionMessage?.contains("did not claim") == true)
    }

    @MainActor
    func testSceneUpdatesRefreshTheAppFacingFactWithoutChangingAuthority() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AutomaticCaptureReadinessStore.preferenceKey)
        let store = AutomaticCaptureReadinessStore(
            userDefaults: defaults,
            factsProvider: StubAutomaticCaptureFactsProvider(base: blockedFacts()),
            initialSceneState: .active
        )

        store.updateSceneState(.background)
        store.refreshAndRearm()

        XCTAssertEqual(store.facts.sceneState, .background)
        XCTAssertTrue(store.lastActionMessage?.contains("foreground") == true)
        XCTAssertFalse(store.readiness.canCaptureRideTelemetryWithoutOpeningApp)
    }

    @MainActor
    func testPreferencePersistsButDoesNotPersistAReadyClaim() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let provider = StubAutomaticCaptureFactsProvider(base: blockedFacts())
        let first = AutomaticCaptureReadinessStore(
            userDefaults: defaults,
            factsProvider: provider,
            initialSceneState: .active
        )
        first.isAutomaticCaptureEnabled = true

        let reopened = AutomaticCaptureReadinessStore(
            userDefaults: defaults,
            factsProvider: provider,
            initialSceneState: .active
        )

        XCTAssertTrue(reopened.isAutomaticCaptureEnabled)
        XCTAssertEqual(reopened.readiness.status, .actionRequired)
        XCTAssertFalse(reopened.readiness.canCaptureRideTelemetryWithoutOpeningApp)
    }

    @MainActor
    func testOrdinaryRelockKeepsConfirmedFirstUnlockEvidence() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AutomaticCaptureReadinessStore.preferenceKey)
        let facts = blockedFacts(firstUnlockEvidence: .confirmedByProtectedSentinel)
        let store = AutomaticCaptureReadinessStore(
            userDefaults: defaults,
            factsProvider: StubAutomaticCaptureFactsProvider(base: facts),
            initialSceneState: .background
        )

        XCTAssertEqual(store.firstUnlockText, "Confirmed")
        XCTAssertFalse(
            store.setupReadiness.issues.contains(.deviceRestartAwaitingFirstUnlock),
            "A normal relock after first authentication must not be labeled as a reboot blocker."
        )
    }

    @MainActor
    func testPreFirstUnlockAndStorageFailureRemainIndependentBlockers() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AutomaticCaptureReadinessStore.preferenceKey)
        let facts = blockedFacts(
            firstUnlockEvidence: .notConfirmed,
            storage: .lastWriteFailed
        )
        let store = AutomaticCaptureReadinessStore(
            userDefaults: defaults,
            factsProvider: StubAutomaticCaptureFactsProvider(base: facts),
            initialSceneState: .background
        )

        XCTAssertTrue(store.setupReadiness.issues.contains(.deviceRestartAwaitingFirstUnlock))
        XCTAssertTrue(store.setupReadiness.issues.contains(.storageWriteFailed))
        XCTAssertEqual(store.firstUnlockText, "Open after unlocking")
    }

    @MainActor
    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "AutomaticCaptureReadinessStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    @MainActor
    private func blockedFacts(
        firstUnlockEvidence: AutomaticCaptureFirstUnlockEvidence = .confirmedByProtectedSentinel,
        storage: AutomaticCaptureStorageEvidence = .writableAndVerified
    ) -> AutomaticCapturePlatformFacts {
        AutomaticCapturePlatformFacts(
            relaunchPolicy: .accessorySetupKitRequired,
            accessorySetupAuthorization: .notEvaluated,
            accessorySetupDescriptor: .absent,
            knownAccessory: AutomaticCaptureKnownAccessoryEvidence(
                knownPeripheralIdentifier: nil,
                authorizedAccessoryPeripheralIdentifier: nil
            ),
            bluetoothAuthorization: .allowed,
            bluetoothRadioState: .unknown,
            restorationConfiguration: AutomaticCaptureRestorationConfigurationEvidence(
                persistedCentralRestorationIdentifier: nil,
                bluetoothCentralBackgroundModeDeclared: false,
                restorationHandlerInstalledBeforeOrdinaryInitialization: false,
                pendingWork: .none
            ),
            backgroundService: .unavailableBlocksAutomaticCapture,
            locationAuthorization: .whileInUse,
            backgroundLocationSession: .notConfigured,
            lifecycle: AutomaticCaptureLifecycleEvidence(
                hasCompletedFirstUnlockAfterDeviceRestart: firstUnlockEvidence == .confirmedByProtectedSentinel,
                requiresForegroundReopenAfterManualForceQuit: false
            ),
            storage: storage,
            sceneState: .active,
            forceQuitObservability: .notObservableUsingPublicAPI,
            firstUnlockEvidence: firstUnlockEvidence
        )
    }

    @MainActor
    private func readyFacts(
        locationAuthorization: AutomaticCaptureLocationAuthorization = .always,
        backgroundLocationSession: AutomaticCaptureBackgroundLocationSessionEvidence = .configured
    ) -> AutomaticCapturePlatformFacts {
        let identity = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        return AutomaticCapturePlatformFacts(
            relaunchPolicy: .accessorySetupKitRequired,
            accessorySetupAuthorization: .authorized,
            accessorySetupDescriptor: .captureVerified(provenanceID: "accepted-physical-fixture"),
            knownAccessory: AutomaticCaptureKnownAccessoryEvidence(
                knownPeripheralIdentifier: identity,
                authorizedAccessoryPeripheralIdentifier: identity
            ),
            bluetoothAuthorization: .allowed,
            bluetoothRadioState: .poweredOn,
            restorationConfiguration: AutomaticCaptureRestorationConfigurationEvidence(
                persistedCentralRestorationIdentifier: "com.nembra.production.central",
                bluetoothCentralBackgroundModeDeclared: true,
                restorationHandlerInstalledBeforeOrdinaryInitialization: true,
                pendingWork: .knownPeripheralConnectionOrSubscription
            ),
            backgroundService: .available,
            locationAuthorization: locationAuthorization,
            backgroundLocationSession: backgroundLocationSession,
            lifecycle: AutomaticCaptureLifecycleEvidence(
                hasCompletedFirstUnlockAfterDeviceRestart: true,
                requiresForegroundReopenAfterManualForceQuit: false
            ),
            storage: .writableAndVerified,
            sceneState: .active,
            forceQuitObservability: .notObservableUsingPublicAPI,
            firstUnlockEvidence: .confirmedByProtectedSentinel
        )
    }
}
