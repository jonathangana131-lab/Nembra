import Foundation

/// Final share model for one sealed Experiment One run.
///
/// This is software evidence, not physical identity or field authorization. The build-instance ID
/// remains only a rendezvous key for an independently accepted external build record.
public struct PassiveBluetoothExperimentOneExportEnvelope: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public struct PowerCycleEvidence: Codable, Equatable, Sendable {
        public struct Window: Codable, Equatable, Sendable {
            public let phaseRawValue: Int
            public let windowSequence: UInt64
            public let startedAtUptimeNanoseconds: UInt64
            public let endedAtUptimeNanoseconds: UInt64
            public let observedCandidateCount: Int

            init(_ receipt: PassiveBluetoothPowerCycleObservationWindowReceipt) {
                phaseRawValue = receipt.phase.rawValue
                windowSequence = receipt.windowSequence.rawValue
                startedAtUptimeNanoseconds = receipt.startedAtUptimeNanoseconds
                endedAtUptimeNanoseconds = receipt.endedAtUptimeNanoseconds
                observedCandidateCount = receipt.observedCandidateCount
            }
        }

        public struct Candidate: Codable, Equatable, Sendable {
            public let id: UUID
            public let isConnectable: Bool?
        }

        public struct Snapshot: Codable, Equatable, Sendable {
            public let observationSeriesIdentity: UUID
            public let windowSequence: UInt64
            public let candidates: [Candidate]

            init(_ snapshot: PassiveBluetoothCandidateObservationSnapshot) {
                observationSeriesIdentity = snapshot.observationSeriesIdentity.rawValue
                windowSequence = snapshot.windowSequence.rawValue
                candidates = snapshot.candidates.map {
                    Candidate(id: $0.id, isConnectable: $0.isConnectable)
                }
            }
        }

        public enum CorrelationDisposition: String, Codable, Equatable, Sendable {
            case invalidObservationAuthority
            case invalidObservationWindowOrder
            case noRepeatableCandidate
            case ambiguousRepeatableCandidates
            case singleRepeatableCandidate
        }

        public struct Correlation: Codable, Equatable, Sendable {
            public let disposition: CorrelationDisposition
            public let repeatableCandidateIdentifiers: [UUID]
        }

        public let windows: [Window]
        public let observationSnapshots: [Snapshot]
        public let correlation: Correlation

        init(_ result: PassiveBluetoothPowerCycleObservationResult) {
            windows = result.windows.map(Window.init)
            observationSnapshots = result.observationSnapshots.map(Snapshot.init)
            correlation = Correlation(result.correlation)
        }
    }

    public let schemaVersion: Int
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID
    public let correlatedPeripheralIdentifier: UUID
    public let nembraBuildIdentifier: String
    public let nembraBuildInstanceID: String
    public let nembraBuildCommitSHA: String
    public let runtimeExecutableSHA256: String
    /// Exact sealed controller JSON bytes. Codable carries these as base64 in the outer JSON.
    public let captureJSON: Data
    /// Canonical schema-v3 manifest bytes. Import verification rebinds them to `captureJSON`.
    public let stationaryManifestJSON: Data
    public let powerCycleEvidence: PowerCycleEvidence

    init(
        correlatedPeripheralIdentifier: UUID,
        runtimeIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        captureJSON: Data,
        stationaryManifestJSON: Data,
        powerCycleEvidence: PowerCycleEvidence
    ) {
        schemaVersion = Self.currentSchemaVersion
        experimentRecipeID = .es80FingerprintV1
        self.correlatedPeripheralIdentifier = correlatedPeripheralIdentifier
        nembraBuildIdentifier = runtimeIdentity.buildIdentifier
        nembraBuildInstanceID = runtimeIdentity.buildInstanceID
        nembraBuildCommitSHA = runtimeIdentity.sourceCommitSHA
        runtimeExecutableSHA256 = runtimeIdentity.executableSHA256
        self.captureJSON = captureJSON
        self.stationaryManifestJSON = stationaryManifestJSON
        self.powerCycleEvidence = powerCycleEvidence
    }
}

extension PassiveBluetoothExperimentOneExportEnvelope.PowerCycleEvidence.Correlation {
    init(_ report: PassiveBluetoothPowerCycleTargetCorrelationReport) {
        let disposition: PassiveBluetoothExperimentOneExportEnvelope.PowerCycleEvidence.CorrelationDisposition
        switch report.disposition {
        case .invalidObservationAuthority: disposition = .invalidObservationAuthority
        case .invalidObservationWindowOrder: disposition = .invalidObservationWindowOrder
        case .noRepeatableCandidate: disposition = .noRepeatableCandidate
        case .ambiguousRepeatableCandidates: disposition = .ambiguousRepeatableCandidates
        case .singleRepeatableCandidate: disposition = .singleRepeatableCandidate
        }
        self.init(
            disposition: disposition,
            repeatableCandidateIdentifiers: report.repeatableCandidateIdentifiers
        )
    }
}
