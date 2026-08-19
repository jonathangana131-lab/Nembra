import Foundation

// MARK: - Automatic-capture readiness

/// Whether the evaluated OS/runtime requires AccessorySetupKit authorization
/// before Core Bluetooth restoration may relaunch the app.
///
/// The platform adapter supplies this policy from the running OS. NembraCore
/// deliberately does not guess it from a version number.
public enum AutomaticCaptureRelaunchPolicy: String, Codable, Equatable, Sendable {
    case accessorySetupKitRequired
    case accessorySetupKitNotRequired
}

/// Exact authorization evidence reported by the AccessorySetupKit adapter.
/// `authorized` is not inferred from a remembered peripheral or a successful
/// Core Bluetooth connection.
public enum AccessorySetupAuthorizationEvidence: String, Codable, Equatable, Sendable {
    case notEvaluated
    case notDetermined
    case authorized
    case denied
    case removed
    case frameworkUnavailable
}

/// Evidence that Nembra can describe the intended accessory without guessing
/// advertising identifiers or service UUIDs.
public enum AccessorySetupDescriptorEvidence: Equatable, Codable, Sendable {
    case absent
    case unverified
    case captureVerified(provenanceID: String)

    private enum Kind: String, Codable {
        case absent
        case unverified
        case captureVerified
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case provenanceID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .absent:
            self = .absent
        case .unverified:
            self = .unverified
        case .captureVerified:
            let provenanceID = try container.decode(String.self, forKey: .provenanceID)
            guard !provenanceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .provenanceID,
                    in: container,
                    debugDescription: "Verified descriptor provenance cannot be empty."
                )
            }
            self = .captureVerified(provenanceID: provenanceID)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .absent:
            try container.encode(Kind.absent, forKey: .kind)
        case .unverified:
            try container.encode(Kind.unverified, forKey: .kind)
        case let .captureVerified(provenanceID):
            let normalized = provenanceID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                throw EncodingError.invalidValue(
                    provenanceID,
                    .init(
                        codingPath: encoder.codingPath,
                        debugDescription: "Verified descriptor provenance cannot be empty."
                    )
                )
            }
            try container.encode(Kind.captureVerified, forKey: .kind)
            try container.encode(normalized, forKey: .provenanceID)
        }
    }

    public var isCaptureVerified: Bool {
        if case let .captureVerified(provenanceID) = self {
            return !provenanceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }
}

/// Identity custody across AccessorySetupKit and Core Bluetooth. Both values
/// are opaque platform identifiers; this type contains no scooter descriptor.
public struct AutomaticCaptureKnownAccessoryEvidence: Equatable, Codable, Sendable {
    public let knownPeripheralIdentifier: UUID?
    public let authorizedAccessoryPeripheralIdentifier: UUID?

    public init(
        knownPeripheralIdentifier: UUID?,
        authorizedAccessoryPeripheralIdentifier: UUID?
    ) {
        self.knownPeripheralIdentifier = knownPeripheralIdentifier
        self.authorizedAccessoryPeripheralIdentifier = authorizedAccessoryPeripheralIdentifier
    }

    public var hasKnownPeripheral: Bool {
        knownPeripheralIdentifier != nil
    }

    public var hasExactAuthorizedIdentityMatch: Bool {
        guard let knownPeripheralIdentifier,
              let authorizedAccessoryPeripheralIdentifier else {
            return false
        }
        return knownPeripheralIdentifier == authorizedAccessoryPeripheralIdentifier
    }
}

public enum AutomaticCaptureBluetoothAuthorization: String, Codable, Equatable, Sendable {
    case notDetermined
    case allowed
    case denied
    case restricted
}

public enum AutomaticCaptureBluetoothRadioState: String, Codable, Equatable, Sendable {
    case poweredOn
    case poweredOff
    case resetting
    case unsupported
    case unknown
}

/// The adapter records whether the concrete Core Bluetooth configuration meets
/// every restoration prerequisite. A non-empty identifier alone is insufficient.
public struct AutomaticCaptureRestorationConfigurationEvidence: Equatable, Codable, Sendable {
    public enum PendingWork: String, Codable, Equatable, Sendable {
        case none
        case knownPeripheralConnectionOrSubscription
    }

    public let persistedCentralRestorationIdentifier: String?
    public let bluetoothCentralBackgroundModeDeclared: Bool
    public let restorationHandlerInstalledBeforeOrdinaryInitialization: Bool
    public let pendingWork: PendingWork

    public init(
        persistedCentralRestorationIdentifier: String?,
        bluetoothCentralBackgroundModeDeclared: Bool,
        restorationHandlerInstalledBeforeOrdinaryInitialization: Bool,
        pendingWork: PendingWork
    ) {
        self.persistedCentralRestorationIdentifier = persistedCentralRestorationIdentifier
        self.bluetoothCentralBackgroundModeDeclared = bluetoothCentralBackgroundModeDeclared
        self.restorationHandlerInstalledBeforeOrdinaryInitialization = restorationHandlerInstalledBeforeOrdinaryInitialization
        self.pendingWork = pendingWork
    }

    public var isStableAndRestorable: Bool {
        guard let persistedCentralRestorationIdentifier,
              !persistedCentralRestorationIdentifier
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return bluetoothCentralBackgroundModeDeclared
            && restorationHandlerInstalledBeforeOrdinaryInitialization
            && pendingWork == .knownPeripheralConnectionOrSubscription
    }
}

/// Some platform services can be independently unavailable even when the
/// Bluetooth radio is on. The app adapter decides whether that unavailability
/// blocks the concrete automatic-capture path; NembraCore does not overgeneralize.
public enum AutomaticCaptureBackgroundServiceEvidence: String, Codable, Equatable, Sendable {
    case available
    case notRequiredForConfiguredPath
    case unavailableBlocksAutomaticCapture
    case unknown
}

public enum AutomaticCaptureLocationAuthorization: String, Codable, Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case whileInUse
    case always
}

public enum AutomaticCaptureBackgroundLocationSessionEvidence: String, Codable, Equatable, Sendable {
    case configured
    case notConfigured
    case unavailable
    case notEvaluated
}

public enum AutomaticCaptureStorageEvidence: String, Codable, Equatable, Sendable {
    case writableAndVerified
    case unavailable
    case lastWriteFailed
}

/// Lifecycle evidence persisted by the app shell. A manual force quit and the
/// pre-first-unlock interval are explicit blockers, never hidden by a generic
/// "ready" boolean.
public struct AutomaticCaptureLifecycleEvidence: Equatable, Codable, Sendable {
    public let hasCompletedFirstUnlockAfterDeviceRestart: Bool
    public let requiresForegroundReopenAfterManualForceQuit: Bool

    public init(
        hasCompletedFirstUnlockAfterDeviceRestart: Bool,
        requiresForegroundReopenAfterManualForceQuit: Bool
    ) {
        self.hasCompletedFirstUnlockAfterDeviceRestart = hasCompletedFirstUnlockAfterDeviceRestart
        self.requiresForegroundReopenAfterManualForceQuit = requiresForegroundReopenAfterManualForceQuit
    }
}

public struct AutomaticRideCaptureReadinessInput: Equatable, Codable, Sendable {
    public let isAutomaticCaptureEnabled: Bool
    public let relaunchPolicy: AutomaticCaptureRelaunchPolicy
    public let accessorySetupAuthorization: AccessorySetupAuthorizationEvidence
    public let accessorySetupDescriptor: AccessorySetupDescriptorEvidence
    public let knownAccessory: AutomaticCaptureKnownAccessoryEvidence
    public let bluetoothAuthorization: AutomaticCaptureBluetoothAuthorization
    public let bluetoothRadioState: AutomaticCaptureBluetoothRadioState
    public let restorationConfiguration: AutomaticCaptureRestorationConfigurationEvidence
    public let backgroundService: AutomaticCaptureBackgroundServiceEvidence
    public let locationAuthorization: AutomaticCaptureLocationAuthorization
    public let backgroundLocationSession: AutomaticCaptureBackgroundLocationSessionEvidence
    public let lifecycle: AutomaticCaptureLifecycleEvidence
    public let storage: AutomaticCaptureStorageEvidence

    public init(
        isAutomaticCaptureEnabled: Bool,
        relaunchPolicy: AutomaticCaptureRelaunchPolicy,
        accessorySetupAuthorization: AccessorySetupAuthorizationEvidence,
        accessorySetupDescriptor: AccessorySetupDescriptorEvidence,
        knownAccessory: AutomaticCaptureKnownAccessoryEvidence,
        bluetoothAuthorization: AutomaticCaptureBluetoothAuthorization,
        bluetoothRadioState: AutomaticCaptureBluetoothRadioState,
        restorationConfiguration: AutomaticCaptureRestorationConfigurationEvidence,
        backgroundService: AutomaticCaptureBackgroundServiceEvidence,
        locationAuthorization: AutomaticCaptureLocationAuthorization,
        backgroundLocationSession: AutomaticCaptureBackgroundLocationSessionEvidence,
        lifecycle: AutomaticCaptureLifecycleEvidence,
        storage: AutomaticCaptureStorageEvidence
    ) {
        self.isAutomaticCaptureEnabled = isAutomaticCaptureEnabled
        self.relaunchPolicy = relaunchPolicy
        self.accessorySetupAuthorization = accessorySetupAuthorization
        self.accessorySetupDescriptor = accessorySetupDescriptor
        self.knownAccessory = knownAccessory
        self.bluetoothAuthorization = bluetoothAuthorization
        self.bluetoothRadioState = bluetoothRadioState
        self.restorationConfiguration = restorationConfiguration
        self.backgroundService = backgroundService
        self.locationAuthorization = locationAuthorization
        self.backgroundLocationSession = backgroundLocationSession
        self.lifecycle = lifecycle
        self.storage = storage
    }
}

public enum AutomaticRideCaptureReadinessIssue: String, Codable, Equatable, CaseIterable, Sendable {
    case intentionallyDisabled
    case deviceRestartAwaitingFirstUnlock
    case foregroundReopenRequiredAfterManualForceQuit
    case storageUnavailable
    case storageWriteFailed
    case accessorySetupFrameworkUnavailable
    case accessorySetupAuthorizationNotEvaluated
    case accessorySetupAuthorizationNotDetermined
    case accessorySetupAuthorizationDenied
    case accessorySetupAuthorizationRemoved
    case accessoryDescriptorAbsent
    case accessoryDescriptorUnverified
    case authorizedAccessoryIdentityMismatch
    case knownPeripheralMissing
    case bluetoothAuthorizationNotDetermined
    case bluetoothAuthorizationDenied
    case bluetoothAuthorizationRestricted
    case bluetoothPoweredOff
    case bluetoothResetting
    case bluetoothUnsupported
    case bluetoothStateUnknown
    case restorationConfigurationIncomplete
    case backgroundServiceUnavailable
    case backgroundServiceUnknown
    case locationAuthorizationNotDetermined
    case locationAuthorizationDenied
    case locationAuthorizationRestricted
    case locationOnlyWhileInUse
    case backgroundLocationSessionNotConfigured
    case backgroundLocationSessionUnavailable
    case backgroundLocationSessionNotEvaluated

    public var blocksAutomaticTelemetryCapture: Bool {
        switch self {
        case .locationAuthorizationNotDetermined,
             .locationAuthorizationDenied,
             .locationAuthorizationRestricted,
             .locationOnlyWhileInUse,
             .backgroundLocationSessionNotConfigured,
             .backgroundLocationSessionUnavailable,
             .backgroundLocationSessionNotEvaluated:
            false
        default:
            true
        }
    }

    public var blocksAutomaticRoadCoverage: Bool {
        true
    }
}

public enum AutomaticRideCaptureReadinessStatus: String, Codable, Equatable, Sendable {
    case ready
    case locationLimited
    case actionRequired
    case intentionallyDisabled
}

/// A permanent truth statement carried with readiness results. Public iOS APIs
/// provide best-effort restoration eligibility, not an always-running daemon.
public enum AutomaticCaptureDeliveryExpectation: String, Codable, Equatable, Sendable {
    case bestEffortSubjectToSystemSchedulingAndLifecycle
}

public struct AutomaticRideCaptureReadiness: Equatable, Codable, Sendable {
    public let status: AutomaticRideCaptureReadinessStatus
    public let canCaptureRideTelemetryWithoutOpeningApp: Bool
    public let canCaptureRoadCoverageWithoutOpeningApp: Bool
    public let issues: [AutomaticRideCaptureReadinessIssue]
    public let deliveryExpectation: AutomaticCaptureDeliveryExpectation

    public init(
        status: AutomaticRideCaptureReadinessStatus,
        canCaptureRideTelemetryWithoutOpeningApp: Bool,
        canCaptureRoadCoverageWithoutOpeningApp: Bool,
        issues: [AutomaticRideCaptureReadinessIssue],
        deliveryExpectation: AutomaticCaptureDeliveryExpectation = .bestEffortSubjectToSystemSchedulingAndLifecycle
    ) {
        self.status = status
        self.canCaptureRideTelemetryWithoutOpeningApp = canCaptureRideTelemetryWithoutOpeningApp
        self.canCaptureRoadCoverageWithoutOpeningApp = canCaptureRoadCoverageWithoutOpeningApp
        self.issues = issues
        self.deliveryExpectation = deliveryExpectation
    }
}

public enum AutomaticRideCaptureReadinessEvaluator {
    public static func evaluate(
        _ input: AutomaticRideCaptureReadinessInput
    ) -> AutomaticRideCaptureReadiness {
        guard input.isAutomaticCaptureEnabled else {
            return AutomaticRideCaptureReadiness(
                status: .intentionallyDisabled,
                canCaptureRideTelemetryWithoutOpeningApp: false,
                canCaptureRoadCoverageWithoutOpeningApp: false,
                issues: [.intentionallyDisabled]
            )
        }

        var issues: [AutomaticRideCaptureReadinessIssue] = []

        if !input.lifecycle.hasCompletedFirstUnlockAfterDeviceRestart {
            issues.append(.deviceRestartAwaitingFirstUnlock)
        }
        if input.lifecycle.requiresForegroundReopenAfterManualForceQuit {
            issues.append(.foregroundReopenRequiredAfterManualForceQuit)
        }

        switch input.storage {
        case .writableAndVerified:
            break
        case .unavailable:
            issues.append(.storageUnavailable)
        case .lastWriteFailed:
            issues.append(.storageWriteFailed)
        }

        if input.relaunchPolicy == .accessorySetupKitRequired {
            switch input.accessorySetupAuthorization {
            case .authorized:
                break
            case .notEvaluated:
                issues.append(.accessorySetupAuthorizationNotEvaluated)
            case .notDetermined:
                issues.append(.accessorySetupAuthorizationNotDetermined)
            case .denied:
                issues.append(.accessorySetupAuthorizationDenied)
            case .removed:
                issues.append(.accessorySetupAuthorizationRemoved)
            case .frameworkUnavailable:
                issues.append(.accessorySetupFrameworkUnavailable)
            }

            switch input.accessorySetupDescriptor {
            case .absent:
                issues.append(.accessoryDescriptorAbsent)
            case .unverified:
                issues.append(.accessoryDescriptorUnverified)
            case .captureVerified:
                if !input.accessorySetupDescriptor.isCaptureVerified {
                    issues.append(.accessoryDescriptorUnverified)
                }
            }

            if input.accessorySetupAuthorization == .authorized,
               !input.knownAccessory.hasExactAuthorizedIdentityMatch {
                issues.append(.authorizedAccessoryIdentityMismatch)
            }
        }

        if !input.knownAccessory.hasKnownPeripheral {
            issues.append(.knownPeripheralMissing)
        }

        switch input.bluetoothAuthorization {
        case .allowed:
            break
        case .notDetermined:
            issues.append(.bluetoothAuthorizationNotDetermined)
        case .denied:
            issues.append(.bluetoothAuthorizationDenied)
        case .restricted:
            issues.append(.bluetoothAuthorizationRestricted)
        }

        switch input.bluetoothRadioState {
        case .poweredOn:
            break
        case .poweredOff:
            issues.append(.bluetoothPoweredOff)
        case .resetting:
            issues.append(.bluetoothResetting)
        case .unsupported:
            issues.append(.bluetoothUnsupported)
        case .unknown:
            issues.append(.bluetoothStateUnknown)
        }

        if !input.restorationConfiguration.isStableAndRestorable {
            issues.append(.restorationConfigurationIncomplete)
        }

        switch input.backgroundService {
        case .available, .notRequiredForConfiguredPath:
            break
        case .unavailableBlocksAutomaticCapture:
            issues.append(.backgroundServiceUnavailable)
        case .unknown:
            issues.append(.backgroundServiceUnknown)
        }

        switch input.locationAuthorization {
        case .always:
            break
        case .whileInUse:
            issues.append(.locationOnlyWhileInUse)
        case .notDetermined:
            issues.append(.locationAuthorizationNotDetermined)
        case .denied:
            issues.append(.locationAuthorizationDenied)
        case .restricted:
            issues.append(.locationAuthorizationRestricted)
        }

        if input.locationAuthorization == .always {
            switch input.backgroundLocationSession {
            case .configured:
                break
            case .notConfigured:
                issues.append(.backgroundLocationSessionNotConfigured)
            case .unavailable:
                issues.append(.backgroundLocationSessionUnavailable)
            case .notEvaluated:
                issues.append(.backgroundLocationSessionNotEvaluated)
            }
        }

        let telemetryIssues = issues.filter(\.blocksAutomaticTelemetryCapture)
        let canCaptureTelemetry = telemetryIssues.isEmpty
        let canCaptureRoadCoverage = canCaptureTelemetry
            && !issues.contains(where: \.blocksAutomaticRoadCoverage)

        let status: AutomaticRideCaptureReadinessStatus
        if !canCaptureTelemetry {
            status = .actionRequired
        } else if !canCaptureRoadCoverage {
            status = .locationLimited
        } else {
            status = .ready
        }

        return AutomaticRideCaptureReadiness(
            status: status,
            canCaptureRideTelemetryWithoutOpeningApp: canCaptureTelemetry,
            canCaptureRoadCoverageWithoutOpeningApp: canCaptureRoadCoverage,
            issues: issues
        )
    }
}

// MARK: - Product projection of RideEnginePhase

public enum AutomaticRideCaptureIdleProjection: Equatable, Sendable {
    case armed
    case connectingOrRestoring
    case connectedIdle
    case closed(rideSessionID: UUID?)
    case needsReview
}

public enum AutomaticRideCaptureProductPhase: Equatable, Sendable {
    case armed
    case connectingOrRestoring
    case connectedIdle
    case candidate(candidateID: UUID)
    case active(rideSessionID: UUID)
    case temporaryGap(rideSessionID: UUID)
    case candidateEnd(rideSessionID: UUID)
    case closed(rideSessionID: UUID?)
    case needsReview
}

/// Presentation/lifecycle projection only. Movement detection and ride identity
/// remain owned by `RideEngine`; this type cannot start or end a ride.
public enum AutomaticRideCapturePhaseProjector {
    public static func project(
        rideEnginePhase: RideEnginePhase,
        candidateID: UUID?,
        idleProjection: AutomaticRideCaptureIdleProjection
    ) -> AutomaticRideCaptureProductPhase {
        if idleProjection == .needsReview {
            return .needsReview
        }

        switch rideEnginePhase {
        case .idle:
            switch idleProjection {
            case .armed:
                return .armed
            case .connectingOrRestoring:
                return .connectingOrRestoring
            case .connectedIdle:
                return .connectedIdle
            case let .closed(rideSessionID):
                return .closed(rideSessionID: rideSessionID)
            case .needsReview:
                return .needsReview
            }
        case .candidate:
            guard let candidateID else { return .needsReview }
            return .candidate(candidateID: candidateID)
        case let .active(session):
            return .active(rideSessionID: session.id)
        case let .temporarilyDisconnected(disconnected):
            return .temporaryGap(rideSessionID: disconnected.session.id)
        case let .endingCandidate(ending):
            return .candidateEnd(rideSessionID: ending.session.id)
        }
    }
}

// MARK: - Crash-safe candidate evidence journal

public enum AutomaticRideCandidateJournalError: Error, Equatable, Sendable {
    case invalidEntry
    case invalidSnapshot
    case candidateNotStarted
    case activeCandidateConflict
    case candidateIdentityMismatch
    case invalidSequence(expected: UInt64, received: UInt64)
    case conflictingReplay(sequence: UInt64)
    case foreignProcessEpoch
    case invalidTransition
    case rideEngineHasNotConfirmedRide
    case promotedRideSessionConflict
    case corruptedSnapshot
    case conflictingGenerations
    case unsupportedSchema(Int)
    case generationOverflow
}

/// Durable equivalent of `RideObservation` with a stable candidate/sequence key
/// and an explicit process epoch around monotonic uptime.
///
/// A decoded entry crosses the same validation boundary as a live
/// `RideObservation`. Prior-process uptime remains preserved evidence but is
/// never returned as an observation for a different process epoch.
public struct AutomaticRideCandidateEvidenceEntry: Codable, Equatable, Sendable {
    public let candidateID: UUID
    public let sequence: UInt64
    public let processEpochID: UUID
    public let receivedAtUptimeNanoseconds: UInt64
    public let receivedAtDate: Date
    public let connection: VehicleConnectionState
    public let speedSample: SpeedTelemetrySample?
    public let odometerKilometers: Double?
    public let qualityScreenedGPSDistanceDeltaMeters: Double?
    public let motionIndicatesMovement: Bool

    private enum CodingKeys: String, CodingKey {
        case candidateID
        case sequence
        case processEpochID
        case receivedAtUptimeNanoseconds
        case receivedAtDate
        case connection
        case speedSample
        case odometerKilometers
        case qualityScreenedGPSDistanceDeltaMeters
        case motionIndicatesMovement
    }

    public init(
        candidateID: UUID,
        sequence: UInt64,
        processEpochID: UUID,
        receivedAtUptimeNanoseconds: UInt64,
        receivedAtDate: Date,
        connection: VehicleConnectionState,
        speedSample: SpeedTelemetrySample? = nil,
        odometerKilometers: Double? = nil,
        qualityScreenedGPSDistanceDeltaMeters: Double? = nil,
        motionIndicatesMovement: Bool = false
    ) throws {
        guard sequence > 0 else {
            throw AutomaticRideCandidateJournalError.invalidEntry
        }

        do {
            _ = try RideObservation(
                receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
                receivedAtDate: receivedAtDate,
                connection: connection,
                speedSample: speedSample,
                odometerKilometers: odometerKilometers,
                qualityScreenedGPSDistanceDeltaMeters: qualityScreenedGPSDistanceDeltaMeters,
                motionIndicatesMovement: motionIndicatesMovement
            )
        } catch {
            throw AutomaticRideCandidateJournalError.invalidEntry
        }

        self.candidateID = candidateID
        self.sequence = sequence
        self.processEpochID = processEpochID
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.receivedAtDate = receivedAtDate
        self.connection = connection
        self.speedSample = speedSample
        self.odometerKilometers = odometerKilometers
        self.qualityScreenedGPSDistanceDeltaMeters = qualityScreenedGPSDistanceDeltaMeters
        self.motionIndicatesMovement = motionIndicatesMovement
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                candidateID: container.decode(UUID.self, forKey: .candidateID),
                sequence: container.decode(UInt64.self, forKey: .sequence),
                processEpochID: container.decode(UUID.self, forKey: .processEpochID),
                receivedAtUptimeNanoseconds: container.decode(UInt64.self, forKey: .receivedAtUptimeNanoseconds),
                receivedAtDate: container.decode(Date.self, forKey: .receivedAtDate),
                connection: container.decode(VehicleConnectionState.self, forKey: .connection),
                speedSample: container.decodeIfPresent(SpeedTelemetrySample.self, forKey: .speedSample),
                odometerKilometers: container.decodeIfPresent(Double.self, forKey: .odometerKilometers),
                qualityScreenedGPSDistanceDeltaMeters: container.decodeIfPresent(
                    Double.self,
                    forKey: .qualityScreenedGPSDistanceDeltaMeters
                ),
                motionIndicatesMovement: container.decode(Bool.self, forKey: .motionIndicatesMovement)
            )
        } catch AutomaticRideCandidateJournalError.invalidEntry {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Candidate evidence contains invalid RideObservation values."
                )
            )
        }
    }

    public func rideObservation(
        forProcessEpochID currentProcessEpochID: UUID
    ) throws -> RideObservation? {
        guard processEpochID == currentProcessEpochID else {
            return nil
        }
        return try RideObservation(
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            receivedAtDate: receivedAtDate,
            connection: connection,
            speedSample: speedSample,
            odometerKilometers: odometerKilometers,
            qualityScreenedGPSDistanceDeltaMeters: qualityScreenedGPSDistanceDeltaMeters,
            motionIndicatesMovement: motionIndicatesMovement
        )
    }
}

public enum AutomaticRideCandidateJournalStatus: String, Codable, Equatable, Sendable {
    case collecting
    case interruptedAwaitingFreshEvidence
    case promoted
    case retired
}

public enum AutomaticRideCandidateRetirementReason: String, Codable, Equatable, Sendable {
    case candidateCancelled
    case insufficientEvidence
    case supersededAfterInterruption
    case promotedEvidenceCommitted
    case userDeletedEvidence
}

/// One complete active-candidate snapshot. Sequence numbers are contiguous and
/// monotonic uptime is ordered only within the same process epoch.
public struct AutomaticRideCandidateJournalSnapshot: Codable, Equatable, Sendable {
    public let candidateID: UUID
    public let evaluationProcessEpochID: UUID
    public let beganAtDate: Date
    public let lastMutationAtDate: Date
    public let status: AutomaticRideCandidateJournalStatus
    public let promotedRideSessionID: UUID?
    public let retirementReason: AutomaticRideCandidateRetirementReason?
    public let entries: [AutomaticRideCandidateEvidenceEntry]

    private enum CodingKeys: String, CodingKey {
        case candidateID
        case evaluationProcessEpochID
        case beganAtDate
        case lastMutationAtDate
        case status
        case promotedRideSessionID
        case retirementReason
        case entries
    }

    public init(
        candidateID: UUID,
        evaluationProcessEpochID: UUID,
        beganAtDate: Date,
        lastMutationAtDate: Date,
        status: AutomaticRideCandidateJournalStatus,
        promotedRideSessionID: UUID?,
        retirementReason: AutomaticRideCandidateRetirementReason?,
        entries: [AutomaticRideCandidateEvidenceEntry]
    ) throws {
        guard beganAtDate.timeIntervalSinceReferenceDate.isFinite,
              lastMutationAtDate.timeIntervalSinceReferenceDate.isFinite else {
            throw AutomaticRideCandidateJournalError.invalidSnapshot
        }

        switch status {
        case .collecting, .interruptedAwaitingFreshEvidence:
            guard promotedRideSessionID == nil, retirementReason == nil else {
                throw AutomaticRideCandidateJournalError.invalidSnapshot
            }
        case .promoted:
            guard promotedRideSessionID != nil, retirementReason == nil else {
                throw AutomaticRideCandidateJournalError.invalidSnapshot
            }
        case .retired:
            guard retirementReason != nil else {
                throw AutomaticRideCandidateJournalError.invalidSnapshot
            }
        }

        var priorByProcessEpoch: [UUID: UInt64] = [:]
        for (index, entry) in entries.enumerated() {
            let expectedSequence = UInt64(index) + 1
            guard entry.candidateID == candidateID,
                  entry.sequence == expectedSequence else {
                throw AutomaticRideCandidateJournalError.invalidSnapshot
            }
            if let priorUptime = priorByProcessEpoch[entry.processEpochID],
               entry.receivedAtUptimeNanoseconds <= priorUptime {
                throw AutomaticRideCandidateJournalError.invalidSnapshot
            }
            priorByProcessEpoch[entry.processEpochID] = entry.receivedAtUptimeNanoseconds
        }

        self.candidateID = candidateID
        self.evaluationProcessEpochID = evaluationProcessEpochID
        self.beganAtDate = beganAtDate
        self.lastMutationAtDate = lastMutationAtDate
        self.status = status
        self.promotedRideSessionID = promotedRideSessionID
        self.retirementReason = retirementReason
        self.entries = entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                candidateID: container.decode(UUID.self, forKey: .candidateID),
                evaluationProcessEpochID: container.decode(UUID.self, forKey: .evaluationProcessEpochID),
                beganAtDate: container.decode(Date.self, forKey: .beganAtDate),
                lastMutationAtDate: container.decode(Date.self, forKey: .lastMutationAtDate),
                status: container.decode(AutomaticRideCandidateJournalStatus.self, forKey: .status),
                promotedRideSessionID: container.decodeIfPresent(UUID.self, forKey: .promotedRideSessionID),
                retirementReason: container.decodeIfPresent(
                    AutomaticRideCandidateRetirementReason.self,
                    forKey: .retirementReason
                ),
                entries: container.decode([AutomaticRideCandidateEvidenceEntry].self, forKey: .entries)
            )
        } catch AutomaticRideCandidateJournalError.invalidSnapshot {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Candidate journal snapshot violates durable invariants."
                )
            )
        }
    }
}

public enum AutomaticRideCandidateAppendResult: Equatable, Sendable {
    case appended(AutomaticRideCandidateJournalSnapshot)
    case duplicateReplay(AutomaticRideCandidateJournalSnapshot)
}

public enum AutomaticRideCandidateMutationResult: Equatable, Sendable {
    case changed(AutomaticRideCandidateJournalSnapshot)
    case duplicateReplay(AutomaticRideCandidateJournalSnapshot)
}

public enum AutomaticRideCandidateRestoreDisposition: Equatable, Sendable {
    case noCandidate
    case collectingInCurrentProcess
    case interruptedAwaitingFreshEvidence
    case promoted(rideSessionID: UUID)
    case retired
}

public struct AutomaticRideCandidateRestoreResult: Equatable, Sendable {
    public let snapshot: AutomaticRideCandidateJournalSnapshot?
    public let disposition: AutomaticRideCandidateRestoreDisposition
    /// Only observations whose monotonic uptime belongs to the caller's process
    /// epoch. Interrupted prior-process entries are intentionally excluded.
    public let observationsForCurrentProcess: [RideObservation]

    public init(
        snapshot: AutomaticRideCandidateJournalSnapshot?,
        disposition: AutomaticRideCandidateRestoreDisposition,
        observationsForCurrentProcess: [RideObservation]
    ) {
        self.snapshot = snapshot
        self.disposition = disposition
        self.observationsForCurrentProcess = observationsForCurrentProcess
    }
}

/// Two-slot atomic candidate journal. Each accepted packet is persisted before
/// callers may derive aggregates from it. The older slot remains a known-good
/// fallback when the newest write is truncated or interrupted.
///
/// Foundation's atomic-write semantics protect ordinary process interruption;
/// this type intentionally makes no stronger filesystem power-loss guarantee.
public actor AtomicAutomaticRideCandidateJournal {
    static let schemaVersion = 1
    static let slotAFileName = "automatic-candidate-journal-a.json"
    static let slotBFileName = "automatic-candidate-journal-b.json"

    struct Envelope: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let generation: UInt64
        let snapshot: AutomaticRideCandidateJournalSnapshot
    }

    private struct SchemaProbe: Decodable {
        let schemaVersion: Int
    }

    private enum SlotRead {
        case missing
        case valid(Envelope)
        case corrupt
        case unsupported(Int)

        var envelope: Envelope? {
            guard case let .valid(envelope) = self else { return nil }
            return envelope
        }

        var isCorrupt: Bool {
            if case .corrupt = self { return true }
            return false
        }
    }

    public let processEpochID: UUID

    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        directoryURL: URL,
        processEpochID: UUID,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.processEpochID = processEpochID
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    @discardableResult
    public func beginCandidate(
        candidateID: UUID,
        beganAtDate: Date
    ) throws -> AutomaticRideCandidateMutationResult {
        if let existing = try loadLatestSnapshot() {
            if existing.candidateID == candidateID,
               existing.status == .collecting,
               existing.evaluationProcessEpochID == processEpochID {
                return .duplicateReplay(existing)
            }
            guard existing.status == .retired else {
                throw AutomaticRideCandidateJournalError.activeCandidateConflict
            }
        }

        let snapshot = try AutomaticRideCandidateJournalSnapshot(
            candidateID: candidateID,
            evaluationProcessEpochID: processEpochID,
            beganAtDate: beganAtDate,
            lastMutationAtDate: beganAtDate,
            status: .collecting,
            promotedRideSessionID: nil,
            retirementReason: nil,
            entries: []
        )
        try persist(snapshot)
        return .changed(snapshot)
    }

    @discardableResult
    public func append(
        _ entry: AutomaticRideCandidateEvidenceEntry
    ) throws -> AutomaticRideCandidateAppendResult {
        guard entry.processEpochID == processEpochID else {
            throw AutomaticRideCandidateJournalError.foreignProcessEpoch
        }
        guard let existing = try loadLatestSnapshot() else {
            throw AutomaticRideCandidateJournalError.candidateNotStarted
        }
        guard entry.candidateID == existing.candidateID else {
            throw AutomaticRideCandidateJournalError.candidateIdentityMismatch
        }

        if let replayed = existing.entries.first(where: { $0.sequence == entry.sequence }) {
            guard replayed == entry else {
                throw AutomaticRideCandidateJournalError.conflictingReplay(sequence: entry.sequence)
            }
            return .duplicateReplay(existing)
        }

        guard existing.status == .collecting
                || existing.status == .interruptedAwaitingFreshEvidence else {
            throw AutomaticRideCandidateJournalError.invalidTransition
        }

        let expectedSequence = UInt64(existing.entries.count) + 1
        guard entry.sequence == expectedSequence else {
            throw AutomaticRideCandidateJournalError.invalidSequence(
                expected: expectedSequence,
                received: entry.sequence
            )
        }

        let nextStatus: AutomaticRideCandidateJournalStatus =
            existing.evaluationProcessEpochID == processEpochID
            ? existing.status
            : .interruptedAwaitingFreshEvidence

        let updated = try AutomaticRideCandidateJournalSnapshot(
            candidateID: existing.candidateID,
            evaluationProcessEpochID: existing.evaluationProcessEpochID,
            beganAtDate: existing.beganAtDate,
            lastMutationAtDate: entry.receivedAtDate,
            status: nextStatus,
            promotedRideSessionID: nil,
            retirementReason: nil,
            entries: existing.entries + [entry]
        )
        try persist(updated)
        return .appended(updated)
    }

    /// A restored candidate can resume only after the existing RideEngine has
    /// independently entered its candidate phase from fresh current-process
    /// evidence. Prior-process uptime is never replayed into that decision.
    @discardableResult
    public func resumeInterruptedCandidate(
        candidateID: UUID,
        after rideEnginePhase: RideEnginePhase,
        atDate: Date
    ) throws -> AutomaticRideCandidateMutationResult {
        guard case .candidate = rideEnginePhase else {
            throw AutomaticRideCandidateJournalError.invalidTransition
        }
        guard let existing = try loadLatestSnapshot() else {
            throw AutomaticRideCandidateJournalError.candidateNotStarted
        }
        guard candidateID == existing.candidateID else {
            throw AutomaticRideCandidateJournalError.candidateIdentityMismatch
        }

        if existing.status == .collecting,
           existing.evaluationProcessEpochID == processEpochID {
            return .duplicateReplay(existing)
        }

        guard existing.status == .interruptedAwaitingFreshEvidence,
              existing.entries.contains(where: { $0.processEpochID == processEpochID }) else {
            throw AutomaticRideCandidateJournalError.invalidTransition
        }

        let updated = try AutomaticRideCandidateJournalSnapshot(
            candidateID: existing.candidateID,
            evaluationProcessEpochID: processEpochID,
            beganAtDate: existing.beganAtDate,
            lastMutationAtDate: atDate,
            status: .collecting,
            promotedRideSessionID: nil,
            retirementReason: nil,
            entries: existing.entries
        )
        try persist(updated)
        return .changed(updated)
    }

    /// Promotion accepts only the session identity already created by
    /// `RideEngine`. Replaying promotion with the same session is idempotent;
    /// a different session for the candidate fails closed.
    @discardableResult
    public func promote(
        candidateID: UUID,
        using rideEnginePhase: RideEnginePhase,
        atDate: Date
    ) throws -> AutomaticRideCandidateMutationResult {
        guard case let .active(session) = rideEnginePhase else {
            throw AutomaticRideCandidateJournalError.rideEngineHasNotConfirmedRide
        }
        guard let existing = try loadLatestSnapshot() else {
            throw AutomaticRideCandidateJournalError.candidateNotStarted
        }
        guard candidateID == existing.candidateID else {
            throw AutomaticRideCandidateJournalError.candidateIdentityMismatch
        }

        if existing.status == .promoted {
            guard existing.promotedRideSessionID == session.id else {
                throw AutomaticRideCandidateJournalError.promotedRideSessionConflict
            }
            return .duplicateReplay(existing)
        }

        guard existing.status == .collecting,
              existing.evaluationProcessEpochID == processEpochID,
              existing.entries.contains(where: { $0.processEpochID == processEpochID }) else {
            throw AutomaticRideCandidateJournalError.invalidTransition
        }

        let updated = try AutomaticRideCandidateJournalSnapshot(
            candidateID: existing.candidateID,
            evaluationProcessEpochID: existing.evaluationProcessEpochID,
            beganAtDate: existing.beganAtDate,
            lastMutationAtDate: atDate,
            status: .promoted,
            promotedRideSessionID: session.id,
            retirementReason: nil,
            entries: existing.entries
        )
        try persist(updated)
        return .changed(updated)
    }

    @discardableResult
    public func retire(
        candidateID: UUID,
        reason: AutomaticRideCandidateRetirementReason,
        atDate: Date
    ) throws -> AutomaticRideCandidateMutationResult {
        guard let existing = try loadLatestSnapshot() else {
            throw AutomaticRideCandidateJournalError.candidateNotStarted
        }
        guard candidateID == existing.candidateID else {
            throw AutomaticRideCandidateJournalError.candidateIdentityMismatch
        }

        if existing.status == .retired {
            guard existing.retirementReason == reason else {
                throw AutomaticRideCandidateJournalError.invalidTransition
            }
            return .duplicateReplay(existing)
        }

        if existing.status == .promoted {
            guard reason == .promotedEvidenceCommitted else {
                throw AutomaticRideCandidateJournalError.invalidTransition
            }
        } else if reason == .promotedEvidenceCommitted {
            throw AutomaticRideCandidateJournalError.invalidTransition
        }

        let updated = try AutomaticRideCandidateJournalSnapshot(
            candidateID: existing.candidateID,
            evaluationProcessEpochID: existing.evaluationProcessEpochID,
            beganAtDate: existing.beganAtDate,
            lastMutationAtDate: atDate,
            status: .retired,
            promotedRideSessionID: existing.promotedRideSessionID,
            retirementReason: reason,
            entries: existing.entries
        )
        try persist(updated)
        return .changed(updated)
    }

    /// Loads the newest durable snapshot. A collecting candidate from another
    /// process is immediately persisted as interrupted. It returns no old
    /// monotonic observations and cannot become promoted as a side effect.
    public func restore() throws -> AutomaticRideCandidateRestoreResult {
        guard var snapshot = try loadLatestSnapshot() else {
            return AutomaticRideCandidateRestoreResult(
                snapshot: nil,
                disposition: .noCandidate,
                observationsForCurrentProcess: []
            )
        }

        if snapshot.status == .collecting,
           snapshot.evaluationProcessEpochID != processEpochID {
            snapshot = try AutomaticRideCandidateJournalSnapshot(
                candidateID: snapshot.candidateID,
                evaluationProcessEpochID: snapshot.evaluationProcessEpochID,
                beganAtDate: snapshot.beganAtDate,
                lastMutationAtDate: snapshot.lastMutationAtDate,
                status: .interruptedAwaitingFreshEvidence,
                promotedRideSessionID: nil,
                retirementReason: nil,
                entries: snapshot.entries
            )
            try persist(snapshot)
        }

        switch snapshot.status {
        case .collecting:
            let observations = try snapshot.entries.compactMap {
                try $0.rideObservation(forProcessEpochID: processEpochID)
            }
            return AutomaticRideCandidateRestoreResult(
                snapshot: snapshot,
                disposition: .collectingInCurrentProcess,
                observationsForCurrentProcess: observations
            )
        case .interruptedAwaitingFreshEvidence:
            return AutomaticRideCandidateRestoreResult(
                snapshot: snapshot,
                disposition: .interruptedAwaitingFreshEvidence,
                observationsForCurrentProcess: []
            )
        case .promoted:
            guard let rideSessionID = snapshot.promotedRideSessionID else {
                throw AutomaticRideCandidateJournalError.invalidSnapshot
            }
            return AutomaticRideCandidateRestoreResult(
                snapshot: snapshot,
                disposition: .promoted(rideSessionID: rideSessionID),
                observationsForCurrentProcess: []
            )
        case .retired:
            return AutomaticRideCandidateRestoreResult(
                snapshot: snapshot,
                disposition: .retired,
                observationsForCurrentProcess: []
            )
        }
    }

    private var slotAURL: URL {
        directoryURL.appendingPathComponent(Self.slotAFileName, isDirectory: false)
    }

    private var slotBURL: URL {
        directoryURL.appendingPathComponent(Self.slotBFileName, isDirectory: false)
    }

    private func persist(_ snapshot: AutomaticRideCandidateJournalSnapshot) throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let slotA = readSlot(at: slotAURL)
        let slotB = readSlot(at: slotBURL)
        try rejectUnsupportedSchema(slotA, slotB)
        try rejectConflictingGenerations(slotA, slotB)

        let valid = [slotA, slotB].compactMap(\.envelope)
        if valid.isEmpty, slotA.isCorrupt, slotB.isCorrupt {
            throw AutomaticRideCandidateJournalError.corruptedSnapshot
        }

        let highestGeneration = valid.map(\.generation).max() ?? 0
        guard highestGeneration < UInt64.max else {
            throw AutomaticRideCandidateJournalError.generationOverflow
        }

        let envelope = Envelope(
            schemaVersion: Self.schemaVersion,
            generation: highestGeneration + 1,
            snapshot: snapshot
        )
        let destination = destinationURL(slotA: slotA, slotB: slotB)
        let data = try encoder.encode(envelope)
        try data.write(to: destination, options: .atomic)

        guard case let .valid(verified) = readSlot(at: destination),
              verified == envelope else {
            throw AutomaticRideCandidateJournalError.corruptedSnapshot
        }
    }

    private func loadLatestSnapshot() throws -> AutomaticRideCandidateJournalSnapshot? {
        let slotA = readSlot(at: slotAURL)
        let slotB = readSlot(at: slotBURL)
        try rejectUnsupportedSchema(slotA, slotB)
        try rejectConflictingGenerations(slotA, slotB)

        let valid = [slotA, slotB].compactMap(\.envelope)
        if let newest = valid.max(by: { $0.generation < $1.generation }) {
            return newest.snapshot
        }
        if slotA.isCorrupt || slotB.isCorrupt {
            throw AutomaticRideCandidateJournalError.corruptedSnapshot
        }
        return nil
    }

    private func readSlot(at url: URL) -> SlotRead {
        guard fileManager.fileExists(atPath: url.path) else {
            return .missing
        }
        guard let data = try? Data(contentsOf: url) else {
            return .corrupt
        }

        do {
            let probe = try decoder.decode(SchemaProbe.self, from: data)
            guard probe.schemaVersion == Self.schemaVersion else {
                return .unsupported(probe.schemaVersion)
            }
            return .valid(try decoder.decode(Envelope.self, from: data))
        } catch {
            return .corrupt
        }
    }

    private func rejectUnsupportedSchema(_ slots: SlotRead...) throws {
        for slot in slots {
            if case let .unsupported(version) = slot {
                throw AutomaticRideCandidateJournalError.unsupportedSchema(version)
            }
        }
    }

    private func rejectConflictingGenerations(
        _ slotA: SlotRead,
        _ slotB: SlotRead
    ) throws {
        guard let a = slotA.envelope,
              let b = slotB.envelope,
              a.generation == b.generation,
              a != b else {
            return
        }
        throw AutomaticRideCandidateJournalError.conflictingGenerations
    }

    private func destinationURL(slotA: SlotRead, slotB: SlotRead) -> URL {
        switch (slotA, slotB) {
        case (.corrupt, .missing):
            return slotBURL
        case (.missing, .corrupt):
            return slotAURL
        default:
            break
        }

        switch (slotA.envelope, slotB.envelope) {
        case (nil, _):
            return slotAURL
        case (_, nil):
            return slotBURL
        case let (.some(a), .some(b)):
            return a.generation <= b.generation ? slotAURL : slotBURL
        }
    }
}
