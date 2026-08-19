import CoreBluetooth
import CoreLocation
import Foundation
import NembraCore
import Observation
import UIKit

enum AutomaticCaptureAppSceneState: String, Equatable {
    case active
    case inactive
    case background
    case unknown

    var title: String {
        switch self {
        case .active: "Open"
        case .inactive: "Transitioning"
        case .background: "Background"
        case .unknown: "Not observed"
        }
    }
}

enum AutomaticCaptureForceQuitObservability: Equatable {
    /// Public iOS APIs do not tell a running process whether a prior process was
    /// removed from the app switcher. If Nembra is running, a prior force quit
    /// has necessarily already been followed by a reopen; a later force quit
    /// terminates the process before it can update UI or persisted readiness.
    case notObservableUsingPublicAPI
}

enum AutomaticCaptureFirstUnlockEvidence: Equatable {
    /// A sentinel protected as "until first user authentication" was read back.
    /// Unlike `UIApplication.isProtectedDataAvailable`, this remains readable
    /// after an ordinary relock and therefore distinguishes that state from the
    /// pre-first-unlock interval after a reboot.
    case confirmedByProtectedSentinel
    case notConfirmed
}

struct AutomaticCapturePlatformFacts: Equatable {
    let relaunchPolicy: AutomaticCaptureRelaunchPolicy
    let accessorySetupAuthorization: AccessorySetupAuthorizationEvidence
    let accessorySetupDescriptor: AccessorySetupDescriptorEvidence
    let knownAccessory: AutomaticCaptureKnownAccessoryEvidence
    let bluetoothAuthorization: AutomaticCaptureBluetoothAuthorization
    let bluetoothRadioState: AutomaticCaptureBluetoothRadioState
    let restorationConfiguration: AutomaticCaptureRestorationConfigurationEvidence
    let backgroundService: AutomaticCaptureBackgroundServiceEvidence
    let locationAuthorization: AutomaticCaptureLocationAuthorization
    let backgroundLocationSession: AutomaticCaptureBackgroundLocationSessionEvidence
    let lifecycle: AutomaticCaptureLifecycleEvidence
    let storage: AutomaticCaptureStorageEvidence
    let sceneState: AutomaticCaptureAppSceneState
    let forceQuitObservability: AutomaticCaptureForceQuitObservability
    let firstUnlockEvidence: AutomaticCaptureFirstUnlockEvidence
}

@MainActor
protocol AutomaticCapturePlatformFactsProviding: AnyObject {
    func snapshot(sceneState: AutomaticCaptureAppSceneState) -> AutomaticCapturePlatformFacts
}

/// Read-only adapter for facts the current app and public iOS APIs can prove.
/// It deliberately does not create a `CBCentralManager`: the future production
/// transport must remain the single Core Bluetooth owner and publish radio /
/// restoration facts into this boundary when its physical descriptor is known.
@MainActor
final class SystemAutomaticCapturePlatformFactsProvider: AutomaticCapturePlatformFactsProviding {
    private let application: UIApplication
    private let bundle: Bundle
    private let fileManager: FileManager
    private let locationManager: CLLocationManager
    private let startupStorageUnavailable: Bool

    init(
        application: UIApplication = .shared,
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        locationManager: CLLocationManager = CLLocationManager(),
        startupStorageUnavailable: Bool = false
    ) {
        self.application = application
        self.bundle = bundle
        self.fileManager = fileManager
        self.locationManager = locationManager
        self.startupStorageUnavailable = startupStorageUnavailable
    }

    func snapshot(sceneState: AutomaticCaptureAppSceneState) -> AutomaticCapturePlatformFacts {
        let backgroundModes = Set(bundle.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? [])
        let hasBluetoothBackgroundMode = backgroundModes.contains("bluetooth-central")
        let hasLocationBackgroundMode = backgroundModes.contains("location")
        let firstUnlockEvidence = firstUnlockEvidence()

        return AutomaticCapturePlatformFacts(
            relaunchPolicy: relaunchPolicy,
            // ASK setup cannot be attempted safely until an accepted physical
            // artifact proves the exact ES80 discovery descriptor.
            accessorySetupAuthorization: .notEvaluated,
            accessorySetupDescriptor: .absent,
            knownAccessory: AutomaticCaptureKnownAccessoryEvidence(
                knownPeripheralIdentifier: nil,
                authorizedAccessoryPeripheralIdentifier: nil
            ),
            bluetoothAuthorization: bluetoothAuthorization,
            // Authorization is globally observable; radio state is not observed
            // here because constructing a second central would violate ownership.
            bluetoothRadioState: .unknown,
            restorationConfiguration: AutomaticCaptureRestorationConfigurationEvidence(
                persistedCentralRestorationIdentifier: nil,
                bluetoothCentralBackgroundModeDeclared: hasBluetoothBackgroundMode,
                restorationHandlerInstalledBeforeOrdinaryInitialization: false,
                pendingWork: .none
            ),
            backgroundService: hasBluetoothBackgroundMode
                ? .unknown
                : .unavailableBlocksAutomaticCapture,
            locationAuthorization: locationAuthorization,
            backgroundLocationSession: hasLocationBackgroundMode
                ? .notEvaluated
                : .notConfigured,
            lifecycle: AutomaticCaptureLifecycleEvidence(
                hasCompletedFirstUnlockAfterDeviceRestart: firstUnlockEvidence == .confirmedByProtectedSentinel,
                // A running process cannot prove historical force-quit state.
                // The permanent limitation is presented separately below.
                requiresForegroundReopenAfterManualForceQuit: false
            ),
            // Storage is probed independently from lifecycle evidence. A normal
            // relock must not be mislabeled as a device-restart condition.
            storage: startupStorageUnavailable ? .unavailable : storageEvidence(),
            sceneState: sceneState,
            forceQuitObservability: .notObservableUsingPublicAPI,
            firstUnlockEvidence: firstUnlockEvidence
        )
    }

    private var relaunchPolicy: AutomaticCaptureRelaunchPolicy {
        if #available(iOS 26.0, *) {
            .accessorySetupKitRequired
        } else {
            .accessorySetupKitNotRequired
        }
    }

    private var bluetoothAuthorization: AutomaticCaptureBluetoothAuthorization {
        switch CBCentralManager.authorization {
        case .allowedAlways: .allowed
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .restricted
        }
    }

    private var locationAuthorization: AutomaticCaptureLocationAuthorization {
        switch locationManager.authorizationStatus {
        case .authorizedAlways: .always
        case .authorizedWhenInUse: .whileInUse
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .restricted
        }
    }

    private func firstUnlockEvidence() -> AutomaticCaptureFirstUnlockEvidence {
        guard let directory = applicationSupportDirectory else {
            return .notConfirmed
        }

        let sentinelURL = directory.appendingPathComponent(
            ".first-unlock-evidence-v1",
            isDirectory: false
        )
        let sentinel = Data("nembra-first-unlock-evidence-v1".utf8)

        if let persisted = try? Data(contentsOf: sentinelURL), persisted == sentinel {
            return .confirmedByProtectedSentinel
        }

        // A missing sentinel can only be established while protected data is
        // currently available. Its protection class then remains readable
        // after subsequent ordinary locks, but not before first unlock on a
        // later reboot.
        guard application.isProtectedDataAvailable else {
            return .notConfirmed
        }

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try sentinel.write(to: sentinelURL, options: .atomic)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: sentinelURL.path
            )
            let persisted = try Data(contentsOf: sentinelURL)
            return persisted == sentinel ? .confirmedByProtectedSentinel : .notConfirmed
        } catch {
            return .notConfirmed
        }
    }

    private func storageEvidence() -> AutomaticCaptureStorageEvidence {
        guard let directory = applicationSupportDirectory else {
            return .unavailable
        }

        let probeURL = directory.appendingPathComponent(".automatic-capture-storage-probe", isDirectory: false)
        let probe = Data(UUID().uuidString.utf8)

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: probeURL) }
            try probe.write(to: probeURL, options: .atomic)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: probeURL.path
            )
            let persisted = try Data(contentsOf: probeURL)
            return persisted == probe ? .writableAndVerified : .lastWriteFailed
        } catch {
            return .lastWriteFailed
        }
    }

    private var applicationSupportDirectory: URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Nembra", isDirectory: true)
    }
}

struct AutomaticCapturePresentationBlocker: Identifiable, Equatable {
    let issue: AutomaticRideCaptureReadinessIssue
    let title: String
    let detail: String

    var id: String { issue.rawValue }
}

@MainActor
@Observable
final class AutomaticCaptureReadinessStore {
    static let preferenceKey = "nembra.preference.automatic-capture.v1"

    var isAutomaticCaptureEnabled: Bool {
        didSet {
            guard isAutomaticCaptureEnabled != oldValue else { return }
            userDefaults.set(isAutomaticCaptureEnabled, forKey: Self.preferenceKey)
            evaluate()
            lastActionMessage = isAutomaticCaptureEnabled
                ? "Automatic capture is requested. It will remain blocked until every required setup fact is verified."
                : "Automatic capture is off."
        }
    }

    private(set) var facts: AutomaticCapturePlatformFacts
    private(set) var readiness: AutomaticRideCaptureReadiness
    private(set) var setupReadiness: AutomaticRideCaptureReadiness
    private(set) var lastRefreshedAt: Date
    private(set) var lastActionMessage: String?

    @ObservationIgnored private let factsProvider: any AutomaticCapturePlatformFactsProviding
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let now: () -> Date

    init(
        userDefaults: UserDefaults = .standard,
        factsProvider: (any AutomaticCapturePlatformFactsProviding)? = nil,
        initialSceneState: AutomaticCaptureAppSceneState = .unknown,
        now: @escaping () -> Date = Date.init
    ) {
        let resolvedProvider = factsProvider ?? SystemAutomaticCapturePlatformFactsProvider()
        let initialFacts = resolvedProvider.snapshot(sceneState: initialSceneState)
        let isEnabled = userDefaults.bool(forKey: Self.preferenceKey)

        self.userDefaults = userDefaults
        self.factsProvider = resolvedProvider
        self.now = now
        self.isAutomaticCaptureEnabled = isEnabled
        self.facts = initialFacts
        self.readiness = Self.evaluate(facts: initialFacts, enabled: isEnabled)
        self.setupReadiness = Self.evaluate(facts: initialFacts, enabled: true)
        self.lastRefreshedAt = now()
        self.lastActionMessage = nil
    }

    func updateSceneState(_ sceneState: AutomaticCaptureAppSceneState) {
        facts = factsProvider.snapshot(sceneState: sceneState)
        lastRefreshedAt = now()
        evaluate()
    }

    func refresh() {
        facts = factsProvider.snapshot(sceneState: facts.sceneState)
        lastRefreshedAt = now()
        evaluate()
    }

    /// Refreshes observable facts and attempts no transport mutation. The
    /// production restoration owner does not exist yet, so claiming a re-arm
    /// would manufacture authority. This action stays useful now and can later
    /// delegate to that single owner without changing Settings semantics.
    func refreshAndRearm() {
        refresh()

        guard isAutomaticCaptureEnabled else {
            lastActionMessage = "Status refreshed. Turn on automatic capture when you want Nembra to use it after setup is complete."
            return
        }
        guard facts.sceneState == .active else {
            lastActionMessage = "Status refreshed. Reopen Nembra in the foreground before re-arming automatic capture."
            return
        }
        guard setupReadiness.status == .ready else {
            lastActionMessage = "Status refreshed. Setup is still incomplete, so Nembra did not claim automatic capture was re-armed."
            return
        }

        lastActionMessage = "Status refreshed. Re-arm is unavailable until the production Bluetooth restoration owner is physically verified and installed."
    }

    var settingsRowSubtitle: String {
        guard isAutomaticCaptureEnabled else {
            return switch setupReadiness.status {
            case .ready: "Off · setup ready"
            case .locationLimited: "Off · routes limited"
            case .actionRequired: "Off · setup not complete"
            case .intentionallyDisabled: "Off"
            }
        }
        return switch readiness.status {
        case .ready: "Best-effort ready"
        case .locationLimited: "Telemetry ready · routes limited"
        case .actionRequired: "Setup required"
        case .intentionallyDisabled: "Off"
        }
    }

    var telemetryStatusText: String {
        guard isAutomaticCaptureEnabled else { return "Off" }
        return readiness.canCaptureRideTelemetryWithoutOpeningApp
            ? "Best-effort ready"
            : "Blocked"
    }

    var roadCoverageStatusText: String {
        guard isAutomaticCaptureEnabled else { return "Off" }
        return readiness.canCaptureRoadCoverageWithoutOpeningApp
            ? "Best-effort ready"
            : (readiness.canCaptureRideTelemetryWithoutOpeningApp ? "Location limited" : "Blocked")
    }

    var bluetoothAuthorizationText: String {
        switch facts.bluetoothAuthorization {
        case .allowed: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not requested"
        }
    }

    var locationAuthorizationText: String {
        switch facts.locationAuthorization {
        case .always: "Always"
        case .whileInUse: "While Using"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not requested"
        }
    }

    var accessorySetupText: String {
        switch facts.accessorySetupDescriptor {
        case .absent: "Waiting for verified ES80 descriptor"
        case .unverified: "Descriptor evidence is unverified"
        case .captureVerified: "Descriptor evidence accepted"
        }
    }

    var restorationText: String {
        facts.restorationConfiguration.isStableAndRestorable
            ? "Configured"
            : "Not configured"
    }

    var firstUnlockText: String {
        switch facts.firstUnlockEvidence {
        case .confirmedByProtectedSentinel: "Confirmed"
        case .notConfirmed: "Open after unlocking"
        }
    }

    var forceQuitTruthText: String {
        switch facts.forceQuitObservability {
        case .notObservableUsingPublicAPI:
            "If you force-quit Nembra, iOS will not relaunch it for Bluetooth restoration. Open Nembra again before the next ride. Public iOS APIs do not tell a running app whether an earlier process was manually force-quit, so Nembra cannot silently claim that history is known."
        }
    }

    var blockers: [AutomaticCapturePresentationBlocker] {
        setupReadiness.issues.map(Self.presentationBlocker(for:))
    }

    var shouldOfferSystemSettings: Bool {
        let issues = setupReadiness.issues
        return issues.contains(.bluetoothAuthorizationDenied)
            || issues.contains(.bluetoothAuthorizationRestricted)
            || issues.contains(.locationAuthorizationDenied)
            || issues.contains(.locationAuthorizationRestricted)
            || issues.contains(.locationOnlyWhileInUse)
            || issues.contains(.accessorySetupAuthorizationDenied)
            || issues.contains(.accessorySetupAuthorizationRemoved)
    }

    private func evaluate() {
        readiness = Self.evaluate(facts: facts, enabled: isAutomaticCaptureEnabled)
        setupReadiness = Self.evaluate(facts: facts, enabled: true)
    }

    private static func evaluate(
        facts: AutomaticCapturePlatformFacts,
        enabled: Bool
    ) -> AutomaticRideCaptureReadiness {
        AutomaticRideCaptureReadinessEvaluator.evaluate(
            AutomaticRideCaptureReadinessInput(
                isAutomaticCaptureEnabled: enabled,
                relaunchPolicy: facts.relaunchPolicy,
                accessorySetupAuthorization: facts.accessorySetupAuthorization,
                accessorySetupDescriptor: facts.accessorySetupDescriptor,
                knownAccessory: facts.knownAccessory,
                bluetoothAuthorization: facts.bluetoothAuthorization,
                bluetoothRadioState: facts.bluetoothRadioState,
                restorationConfiguration: facts.restorationConfiguration,
                backgroundService: facts.backgroundService,
                locationAuthorization: facts.locationAuthorization,
                backgroundLocationSession: facts.backgroundLocationSession,
                lifecycle: facts.lifecycle,
                storage: facts.storage
            )
        )
    }

    private static func presentationBlocker(
        for issue: AutomaticRideCaptureReadinessIssue
    ) -> AutomaticCapturePresentationBlocker {
        let copy: (String, String) = switch issue {
        case .intentionallyDisabled:
            ("Automatic capture is off", "Turn it on only when you want Nembra to attempt best-effort capture after setup is complete.")
        case .deviceRestartAwaitingFirstUnlock:
            ("Unlock this iPhone", "Protected ride storage is unavailable until the first unlock after a device restart.")
        case .foregroundReopenRequiredAfterManualForceQuit:
            ("Reopen Nembra", "iOS does not relaunch an app for Bluetooth restoration after you force-quit it.")
        case .storageUnavailable:
            ("Ride storage unavailable", "Nembra cannot safely journal candidate evidence on this iPhone.")
        case .storageWriteFailed:
            ("Ride storage check failed", "Nembra could not write and read back its local readiness probe.")
        case .accessorySetupFrameworkUnavailable:
            ("Accessory setup unavailable", "The required iOS accessory authorization service is unavailable.")
        case .accessorySetupAuthorizationNotEvaluated:
            ("Accessory setup not started", "Nembra will not request accessory authority until the exact ES80 descriptor is physically verified.")
        case .accessorySetupAuthorizationNotDetermined:
            ("Accessory approval needed", "Complete the one-time system accessory approval when Nembra can safely offer it.")
        case .accessorySetupAuthorizationDenied:
            ("Accessory approval denied", "Allow the authorized scooter in iOS Settings, then refresh this status.")
        case .accessorySetupAuthorizationRemoved:
            ("Scooter authorization removed", "Authorize the intended scooter again before relying on automatic capture.")
        case .accessoryDescriptorAbsent:
            ("Verified scooter descriptor missing", "Capture must first prove the exact ES80 advertising or service descriptor; Nembra will not guess it.")
        case .accessoryDescriptorUnverified:
            ("Scooter descriptor unverified", "Only an accepted physical artifact can promote this descriptor into production setup.")
        case .authorizedAccessoryIdentityMismatch:
            ("Authorized scooter does not match", "The accessory identity and known peripheral must match exactly.")
        case .knownPeripheralMissing:
            ("No production scooter identity", "Nembra does not yet have a physically verified peripheral identity for automatic reconnect.")
        case .bluetoothAuthorizationNotDetermined:
            ("Bluetooth permission not requested", "Bluetooth permission is required before Nembra can receive scooter evidence.")
        case .bluetoothAuthorizationDenied:
            ("Bluetooth permission denied", "Allow Bluetooth for Nembra in iOS Settings.")
        case .bluetoothAuthorizationRestricted:
            ("Bluetooth is restricted", "This iPhone currently prevents Nembra from using Bluetooth.")
        case .bluetoothPoweredOff:
            ("Bluetooth is off", "Turn on Bluetooth to allow best-effort scooter reconnect.")
        case .bluetoothResetting:
            ("Bluetooth is restarting", "Wait for Bluetooth to recover, then refresh this status.")
        case .bluetoothUnsupported:
            ("Bluetooth unsupported", "This iPhone cannot provide the Bluetooth path automatic capture requires.")
        case .bluetoothStateUnknown:
            ("Bluetooth radio not observed", "Nembra will not create a second Bluetooth owner just to infer radio state. The production transport must publish it.")
        case .restorationConfigurationIncomplete:
            ("Background restoration not configured", "The stable central owner, restoration handler, background mode, and pending known-scooter work are not installed.")
        case .backgroundServiceUnavailable:
            ("Background Bluetooth unavailable", "The app has no declared, physically verified background Bluetooth path.")
        case .backgroundServiceUnknown:
            ("Background service not verified", "Nembra cannot claim a background reconnect path until the concrete owner is tested.")
        case .locationAuthorizationNotDetermined:
            ("Location permission not requested", "Route recording and Explore remain unavailable until location permission is granted.")
        case .locationAuthorizationDenied:
            ("Location permission denied", "Ride telemetry may continue later, but route and Explore coverage require Location access.")
        case .locationAuthorizationRestricted:
            ("Location is restricted", "This iPhone currently prevents route and Explore capture.")
        case .locationOnlyWhileInUse:
            ("Location limited to While Using", "Automatic route and Explore capture require Always access after the foreground setup flow.")
        case .backgroundLocationSessionNotConfigured:
            ("Background route capture not configured", "Nembra has not installed a ride-scoped background location session.")
        case .backgroundLocationSessionUnavailable:
            ("Background route capture unavailable", "Ride telemetry may continue later, but route evidence cannot be captured in the background.")
        case .backgroundLocationSessionNotEvaluated:
            ("Background route capture not verified", "A real ride lifecycle test is required before Nembra can claim route readiness.")
        }

        return AutomaticCapturePresentationBlocker(
            issue: issue,
            title: copy.0,
            detail: copy.1
        )
    }
}
