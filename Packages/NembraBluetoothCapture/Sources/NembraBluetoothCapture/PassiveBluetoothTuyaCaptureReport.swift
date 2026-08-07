import Foundation
import NembraCore

/// Fail-closed report construction errors. These describe an internal mapping
/// inconsistency in offline tooling and never become physical ES80 claims.
public enum PassiveBluetoothTuyaCaptureReportError: Error, Equatable, Sendable {
    case sourceFragmentUnavailable(streamIndex: Int, observationIndex: Int)
}

/// Stable, machine-readable summary of one immutable passive capture projected
/// through Nembra's bounded public-family Tuya framing candidate analyzer.
///
/// This report intentionally excludes raw encrypted bytes, decryption, DP
/// semantics, field names, units, scales, and any notion of verified telemetry.
/// It exists so a physical capture can be consumed reproducibly without asking
/// the operator to copy/edit hex or manually reconstruct GATT streams.
public struct PassiveBluetoothTuyaCaptureReport: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let capture: CaptureSummary
    public let analysisPolicy: AnalysisPolicySummary
    public let streams: [StreamReport]

    public struct CaptureSummary: Equatable, Codable, Sendable {
        public let sessionID: UUID
        public let vehicleIdentity: VehicleIdentity
        public let sessionStartedAt: Date
        public let peripheralIdentifier: String
        public let totalCaptureRecordCount: Int
    }

    public struct AnalysisPolicySummary: Equatable, Codable, Sendable {
        public let maximumEncryptedMessageBytes: Int
        public let maximumFragmentCount: Int
    }

    public struct StreamReport: Equatable, Codable, Sendable {
        public let serviceIdentifier: String
        public let characteristicIdentifier: String
        public let valueOrigin: String
        public let fragmentCount: Int
        public let fragments: [SourceReference]
        public let events: [EventReport]
    }

    /// Exact immutable capture provenance for one stream-local analyzer
    /// observation. Payload bytes are deliberately not duplicated into the
    /// summary; the source artifact remains the authority for raw bytes.
    public struct SourceReference: Equatable, Codable, Sendable {
        public let analysisObservationIndex: Int
        public let captureRecordIndex: Int
        public let captureSequenceNumber: UInt64
        public let receivedAtUptimeNanoseconds: UInt64
        public let receivedAtDate: Date
        public let continuityGeneration: UInt64
        public let payloadByteCount: Int
    }

    public struct EventReport: Equatable, Codable, Sendable {
        public enum Kind: String, Equatable, Codable, Sendable {
            case completed
            case rejectedCandidate
            case incompleteAtBoundary
            case incompleteAtEnd
            case unexpectedAnalyzerFailure
        }

        public let kind: Kind
        public let startObservationIndex: Int?
        public let endObservationIndex: Int?
        public let lastAcceptedObservationIndex: Int?
        public let failingObservationIndex: Int?
        public let nextObservationIndex: Int?
        public let boundary: String?
        public let error: String?
        public let startSource: SourceReference?
        public let endSource: SourceReference?
        public let lastAcceptedSource: SourceReference?
        public let failingSource: SourceReference?
        public let nextSource: SourceReference?
        public let completedMessage: CompletedMessageSummary?
    }

    public struct CompletedMessageSummary: Equatable, Codable, Sendable {
        public let continuityGeneration: UInt64
        public let protocolVersionByte: UInt8
        public let protocolVersionHighNibble: UInt8
        public let encryptedByteCount: Int
        public let fragmentCount: Int
        public let firstReceiptUptimeNanoseconds: UInt64
        public let lastReceiptUptimeNanoseconds: UInt64
    }

    /// Deterministic JSON intended for durable offline analysis handoff. Dates
    /// use the same millisecond epoch precision as the passive-capture artifact;
    /// sorted keys keep diffs reviewable.
    public func jsonData(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }
}

public enum PassiveBluetoothTuyaCaptureReportBuilder {
    /// Returns exact peripheral identifiers that have target-attributable GATT,
    /// connection, subscription, or raw-value evidence in first-observed order.
    ///
    /// Advertisement-only identifiers are intentionally excluded: the research
    /// capture performs broad discovery, so an advertisement is candidate
    /// catalog evidence rather than proof of the selected physical target.
    public static func attributablePeripheralIdentifiers(
        in session: PassiveBluetoothCaptureSession
    ) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        func append(_ identifier: String) {
            guard seen.insert(identifier).inserted else { return }
            result.append(identifier)
        }

        for record in session.records {
            switch record.event {
            case let .connection(observation):
                append(observation.peripheralIdentifier)
            case let .service(observation):
                append(observation.peripheralIdentifier)
            case let .includedService(observation):
                append(observation.peripheralIdentifier)
            case let .characteristic(observation):
                append(observation.peripheralIdentifier)
            case let .descriptor(observation):
                append(observation.peripheralIdentifier)
            case let .subscription(observation):
                append(observation.peripheralIdentifier)
            case let .value(observation):
                append(observation.peripheralIdentifier)
            case .advertisement, .stockAppState, .interruption:
                continue
            }
        }

        return result
    }

    /// Builds one deterministic summary for an explicitly selected peripheral.
    /// Resource limits are caller-owned offline safety bounds, not device
    /// protocol expectations or learned ES80 limits.
    public static func make(
        session: PassiveBluetoothCaptureSession,
        peripheralIdentifier: String,
        policy: TuyaCandidateFragmentReassemblyPolicy
    ) throws -> PassiveBluetoothTuyaCaptureReport {
        let analyses = try PassiveBluetoothTuyaCandidateBridge.analyze(
            session: session,
            peripheralIdentifier: peripheralIdentifier,
            policy: policy
        )

        let streams = try analyses.enumerated().map { streamIndex, analysis in
            try makeStreamReport(analysis, streamIndex: streamIndex)
        }

        return PassiveBluetoothTuyaCaptureReport(
            schemaVersion: PassiveBluetoothTuyaCaptureReport.currentSchemaVersion,
            capture: .init(
                sessionID: session.id,
                vehicleIdentity: session.vehicleIdentity,
                sessionStartedAt: session.startedAt,
                peripheralIdentifier: peripheralIdentifier,
                totalCaptureRecordCount: session.records.count
            ),
            analysisPolicy: .init(
                maximumEncryptedMessageBytes: policy.maximumEncryptedMessageBytes,
                maximumFragmentCount: policy.maximumFragmentCount
            ),
            streams: streams
        )
    }

    private static func makeStreamReport(
        _ analysis: PassiveBluetoothTuyaCandidateStreamAnalysis,
        streamIndex: Int
    ) throws -> PassiveBluetoothTuyaCaptureReport.StreamReport {
        let transcript = analysis.transcript
        let fragmentReferences = transcript.fragments.enumerated().map { index, fragment in
            sourceReference(fragment, observationIndex: index)
        }
        let eventReports = try analysis.events.map { event in
            try makeEventReport(
                event,
                transcript: transcript,
                streamIndex: streamIndex
            )
        }

        return .init(
            serviceIdentifier: transcript.sourceStream.valueStreamIdentity.serviceIdentifier,
            characteristicIdentifier: transcript.sourceStream.valueStreamIdentity.characteristicIdentifier,
            valueOrigin: transcript.sourceStream.origin.rawValue,
            fragmentCount: transcript.fragments.count,
            fragments: fragmentReferences,
            events: eventReports
        )
    }

    private static func makeEventReport(
        _ event: TuyaCandidateTranscriptEvent,
        transcript: PassiveBluetoothTuyaCandidateStreamTranscript,
        streamIndex: Int
    ) throws -> PassiveBluetoothTuyaCaptureReport.EventReport {
        switch event {
        case let .completed(startObservationIndex, endObservationIndex, message):
            return .init(
                kind: .completed,
                startObservationIndex: startObservationIndex,
                endObservationIndex: endObservationIndex,
                lastAcceptedObservationIndex: endObservationIndex,
                failingObservationIndex: nil,
                nextObservationIndex: nil,
                boundary: nil,
                error: nil,
                startSource: try requiredSourceReference(
                    transcript,
                    observationIndex: startObservationIndex,
                    streamIndex: streamIndex
                ),
                endSource: try requiredSourceReference(
                    transcript,
                    observationIndex: endObservationIndex,
                    streamIndex: streamIndex
                ),
                lastAcceptedSource: try requiredSourceReference(
                    transcript,
                    observationIndex: endObservationIndex,
                    streamIndex: streamIndex
                ),
                failingSource: nil,
                nextSource: nil,
                completedMessage: .init(
                    continuityGeneration: message.continuityGeneration,
                    protocolVersionByte: message.protocolVersionByte,
                    protocolVersionHighNibble: message.protocolVersionHighNibble,
                    encryptedByteCount: message.encryptedBytes.count,
                    fragmentCount: message.fragmentCount,
                    firstReceiptUptimeNanoseconds: message.firstReceiptUptimeNanoseconds,
                    lastReceiptUptimeNanoseconds: message.lastReceiptUptimeNanoseconds
                )
            )

        case let .rejectedCandidate(
            startObservationIndex,
            lastAcceptedObservationIndex,
            failingObservationIndex,
            error
        ):
            return .init(
                kind: .rejectedCandidate,
                startObservationIndex: startObservationIndex,
                endObservationIndex: nil,
                lastAcceptedObservationIndex: lastAcceptedObservationIndex,
                failingObservationIndex: failingObservationIndex,
                nextObservationIndex: nil,
                boundary: nil,
                error: describe(error),
                startSource: try requiredSourceReference(
                    transcript,
                    observationIndex: startObservationIndex,
                    streamIndex: streamIndex
                ),
                endSource: nil,
                lastAcceptedSource: try lastAcceptedObservationIndex.map {
                    try requiredSourceReference(
                        transcript,
                        observationIndex: $0,
                        streamIndex: streamIndex
                    )
                },
                failingSource: try requiredSourceReference(
                    transcript,
                    observationIndex: failingObservationIndex,
                    streamIndex: streamIndex
                ),
                nextSource: nil,
                completedMessage: nil
            )

        case let .incompleteAtBoundary(
            startObservationIndex,
            lastAcceptedObservationIndex,
            nextObservationIndex,
            boundary
        ):
            return .init(
                kind: .incompleteAtBoundary,
                startObservationIndex: startObservationIndex,
                endObservationIndex: nil,
                lastAcceptedObservationIndex: lastAcceptedObservationIndex,
                failingObservationIndex: nil,
                nextObservationIndex: nextObservationIndex,
                boundary: describe(boundary),
                error: nil,
                startSource: try requiredSourceReference(
                    transcript,
                    observationIndex: startObservationIndex,
                    streamIndex: streamIndex
                ),
                endSource: nil,
                lastAcceptedSource: try requiredSourceReference(
                    transcript,
                    observationIndex: lastAcceptedObservationIndex,
                    streamIndex: streamIndex
                ),
                failingSource: nil,
                nextSource: try requiredSourceReference(
                    transcript,
                    observationIndex: nextObservationIndex,
                    streamIndex: streamIndex
                ),
                completedMessage: nil
            )

        case let .incompleteAtEnd(startObservationIndex, lastAcceptedObservationIndex):
            return .init(
                kind: .incompleteAtEnd,
                startObservationIndex: startObservationIndex,
                endObservationIndex: nil,
                lastAcceptedObservationIndex: lastAcceptedObservationIndex,
                failingObservationIndex: nil,
                nextObservationIndex: nil,
                boundary: nil,
                error: nil,
                startSource: try requiredSourceReference(
                    transcript,
                    observationIndex: startObservationIndex,
                    streamIndex: streamIndex
                ),
                endSource: nil,
                lastAcceptedSource: try requiredSourceReference(
                    transcript,
                    observationIndex: lastAcceptedObservationIndex,
                    streamIndex: streamIndex
                ),
                failingSource: nil,
                nextSource: nil,
                completedMessage: nil
            )

        case let .unexpectedAnalyzerFailure(failingObservationIndex):
            return .init(
                kind: .unexpectedAnalyzerFailure,
                startObservationIndex: nil,
                endObservationIndex: nil,
                lastAcceptedObservationIndex: nil,
                failingObservationIndex: failingObservationIndex,
                nextObservationIndex: nil,
                boundary: nil,
                error: "unexpectedAnalyzerFailure",
                startSource: nil,
                endSource: nil,
                lastAcceptedSource: nil,
                failingSource: try requiredSourceReference(
                    transcript,
                    observationIndex: failingObservationIndex,
                    streamIndex: streamIndex
                ),
                nextSource: nil,
                completedMessage: nil
            )
        }
    }

    private static func requiredSourceReference(
        _ transcript: PassiveBluetoothTuyaCandidateStreamTranscript,
        observationIndex: Int,
        streamIndex: Int
    ) throws -> PassiveBluetoothTuyaCaptureReport.SourceReference {
        guard let fragment = transcript.sourceFragment(
            atAnalysisObservationIndex: observationIndex
        ) else {
            throw PassiveBluetoothTuyaCaptureReportError.sourceFragmentUnavailable(
                streamIndex: streamIndex,
                observationIndex: observationIndex
            )
        }
        return sourceReference(fragment, observationIndex: observationIndex)
    }

    private static func sourceReference(
        _ fragment: PassiveBluetoothTuyaCandidateSourceFragment,
        observationIndex: Int
    ) -> PassiveBluetoothTuyaCaptureReport.SourceReference {
        .init(
            analysisObservationIndex: observationIndex,
            captureRecordIndex: fragment.captureRecordIndex,
            captureSequenceNumber: fragment.captureSequenceNumber,
            receivedAtUptimeNanoseconds: fragment.observation.receiptUptimeNanoseconds,
            receivedAtDate: fragment.receivedAtDate,
            continuityGeneration: fragment.observation.continuityGeneration,
            payloadByteCount: fragment.observation.bytes.count
        )
    }

    private static func describe(_ boundary: TuyaCandidateTranscriptBoundary) -> String {
        switch boundary {
        case .streamIdentityChanged:
            "streamIdentityChanged"
        case .continuityGenerationChanged:
            "continuityGenerationChanged"
        case .streamIdentityAndContinuityGenerationChanged:
            "streamIdentityAndContinuityGenerationChanged"
        }
    }

    private static func describe(_ error: TuyaCandidateOfflineAnalysisError) -> String {
        switch error {
        case .emptyStreamIdentityField:
            "emptyStreamIdentityField"
        case .emptyFragment:
            "emptyFragment"
        case .malformedVarint:
            "malformedVarint"
        case .varintOverflow:
            "varintOverflow"
        case .firstFragmentRequired:
            "firstFragmentRequired"
        case let .unexpectedPacketIndex(expected, actual):
            "unexpectedPacketIndex(expected:\(expected),actual:\(actual))"
        case .invalidMaximumEncryptedMessageBytes:
            "invalidMaximumEncryptedMessageBytes"
        case .invalidMaximumFragmentCount:
            "invalidMaximumFragmentCount"
        case .declaredLengthZero:
            "declaredLengthZero"
        case let .declaredLengthExceedsPolicy(declared, maximum):
            "declaredLengthExceedsPolicy(declared:\(declared),maximum:\(maximum))"
        case let .fragmentCountExceedsPolicy(maximum):
            "fragmentCountExceedsPolicy(maximum:\(maximum))"
        case .streamChanged:
            "streamChanged"
        case .continuityGenerationChanged:
            "continuityGenerationChanged"
        case .nonMonotonicReceiptUptime:
            "nonMonotonicReceiptUptime"
        case let .assembledLengthExceeded(declared, actual):
            "assembledLengthExceeded(declared:\(declared),actual:\(actual))"
        case .messageAlreadyComplete:
            "messageAlreadyComplete"
        case .encryptedEnvelopeTooShort:
            "encryptedEnvelopeTooShort"
        case .encryptedCiphertextNotBlockAligned:
            "encryptedCiphertextNotBlockAligned"
        case .logicalPacketTooShort:
            "logicalPacketTooShort"
        case let .logicalPacketLengthMismatch(expected, actual):
            "logicalPacketLengthMismatch(expected:\(expected),actual:\(actual))"
        case let .logicalPacketPaddingLengthMismatch(expected, actual):
            "logicalPacketPaddingLengthMismatch(expected:\(expected),actual:\(actual))"
        case .nonZeroLogicalPacketPadding:
            "nonZeroLogicalPacketPadding"
        case let .logicalPacketCRCFailed(expected, actual):
            "logicalPacketCRCFailed(expected:\(expected),actual:\(actual))"
        }
    }
}
