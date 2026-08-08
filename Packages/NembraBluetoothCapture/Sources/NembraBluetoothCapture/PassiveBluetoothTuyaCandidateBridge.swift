import Foundation
import NembraCore

/// Fail-closed projection errors while adapting immutable passive-capture
/// evidence into the public Tuya candidate analyzer. These are tooling errors
/// or unsupported raw observations, never physical ES80 protocol claims.
public enum PassiveBluetoothTuyaCandidateProjectionError: Error, Equatable, Sendable {
    case emptyPeripheralIdentifier
    case requestedPeripheralNotPresent(peripheralIdentifier: String)
    case emptyValuePayload(
        captureRecordIndex: Int,
        captureSequenceNumber: UInt64,
        serviceUUID: String,
        characteristicUUID: String,
        origin: PassiveBluetoothValueOrigin
    )
    case continuityGenerationOverflow(
        captureRecordIndex: Int,
        captureSequenceNumber: UInt64
    )
}

/// Capture-level provenance copied losslessly onto every detached candidate
/// transcript. Offline analysis must remain attributable to the exact evidence
/// session rather than depending on external filename or UI bookkeeping.
public struct PassiveBluetoothTuyaCandidateCaptureContext: Equatable, Sendable {
    public let sessionID: UUID
    public let vehicleIdentity: VehicleIdentity
    public let sessionStartedAt: Date
    public let peripheralIdentifier: String

    init(
        sessionID: UUID,
        vehicleIdentity: VehicleIdentity,
        sessionStartedAt: Date,
        peripheralIdentifier: String
    ) {
        self.sessionID = sessionID
        self.vehicleIdentity = vehicleIdentity
        self.sessionStartedAt = sessionStartedAt
        self.peripheralIdentifier = peripheralIdentifier
    }
}

/// Exact value-source identity used by the bridge. The candidate analyzer's
/// GATT stream identity is preserved verbatim, while CoreBluetooth value origin
/// is kept separate so read responses are never silently spliced together with
/// subscription/notification evidence from the same characteristic.
public struct PassiveBluetoothTuyaCandidateSourceStream: Equatable, Sendable {
    public let valueStreamIdentity: TuyaCandidateValueStreamIdentity
    public let origin: PassiveBluetoothValueOrigin

    init(
        valueStreamIdentity: TuyaCandidateValueStreamIdentity,
        origin: PassiveBluetoothValueOrigin
    ) {
        self.valueStreamIdentity = valueStreamIdentity
        self.origin = origin
    }
}

/// One lossless source mapping from a raw capture record into an analyzer
/// observation. Immutable capture sequence is projected as the stronger scoped
/// callback-order authority; uptime and wall-clock remain captured metadata.
public struct PassiveBluetoothTuyaCandidateSourceFragment: Equatable, Sendable {
    public let captureRecordIndex: Int
    public let captureSequenceNumber: UInt64
    public let receivedAtDate: Date
    public let observation: TuyaCandidateFragmentObservation

    init(
        captureRecordIndex: Int,
        captureSequenceNumber: UInt64,
        receivedAtDate: Date,
        observation: TuyaCandidateFragmentObservation
    ) {
        self.captureRecordIndex = captureRecordIndex
        self.captureSequenceNumber = captureSequenceNumber
        self.receivedAtDate = receivedAtDate
        self.observation = observation
    }
}

/// One exact GATT + value-origin transcript, kept in first-observed stream order.
public struct PassiveBluetoothTuyaCandidateStreamTranscript: Equatable, Sendable {
    public let captureContext: PassiveBluetoothTuyaCandidateCaptureContext
    public let sourceStream: PassiveBluetoothTuyaCandidateSourceStream
    public let fragments: [PassiveBluetoothTuyaCandidateSourceFragment]

    init(
        captureContext: PassiveBluetoothTuyaCandidateCaptureContext,
        sourceStream: PassiveBluetoothTuyaCandidateSourceStream,
        fragments: [PassiveBluetoothTuyaCandidateSourceFragment]
    ) {
        self.captureContext = captureContext
        self.sourceStream = sourceStream
        self.fragments = fragments
    }

    public var observations: [TuyaCandidateFragmentObservation] {
        fragments.map(\.observation)
    }

    public func sourceFragment(
        atAnalysisObservationIndex index: Int
    ) -> PassiveBluetoothTuyaCandidateSourceFragment? {
        guard fragments.indices.contains(index) else { return nil }
        return fragments[index]
    }
}

/// Candidate-analysis events plus the exact source transcript they reference.
/// The events remain hypotheses for a corroborated public Tuya family only.
public struct PassiveBluetoothTuyaCandidateStreamAnalysis: Equatable, Sendable {
    public let transcript: PassiveBluetoothTuyaCandidateStreamTranscript
    public let events: [TuyaCandidateTranscriptEvent]

    init(
        transcript: PassiveBluetoothTuyaCandidateStreamTranscript,
        events: [TuyaCandidateTranscriptEvent]
    ) {
        self.transcript = transcript
        self.events = events
    }
}

/// Bridges Nembra's passive CoreBluetooth evidence artifact into the bounded
/// public-family Tuya transcript analyzer without assigning any ES80 field,
/// DP, unit, scale, signedness, cadence, encryption key, or command meaning.
public enum PassiveBluetoothTuyaCandidateBridge {
    /// Projects raw value evidence for one explicitly selected peripheral into
    /// deterministic, origin-isolated candidate transcripts.
    ///
    /// Every projected value maps immutable capture `sequenceNumber` to analyzer
    /// `receiptSequenceNumber`, scoped by this exact capture session UUID.
    /// Continuity advances for every capture event already classified by the
    /// authoritative domain as `breaksByteContinuity`; target attribution remains
    /// separate from that raw-byte gap fact.
    public static func transcripts(
        in session: PassiveBluetoothCaptureSession,
        peripheralIdentifier: String
    ) throws -> [PassiveBluetoothTuyaCandidateStreamTranscript] {
        guard !peripheralIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PassiveBluetoothTuyaCandidateProjectionError.emptyPeripheralIdentifier
        }
        guard containsTargetAttributableEvidence(
            in: session,
            peripheralIdentifier: peripheralIdentifier
        ) else {
            throw PassiveBluetoothTuyaCandidateProjectionError
                .requestedPeripheralNotPresent(peripheralIdentifier: peripheralIdentifier)
        }

        let captureContext = PassiveBluetoothTuyaCandidateCaptureContext(
            sessionID: session.id,
            vehicleIdentity: session.vehicleIdentity,
            sessionStartedAt: session.startedAt,
            peripheralIdentifier: peripheralIdentifier
        )
        let receiptSequenceScope = session.id.uuidString
        var continuityGeneration: UInt64 = 0
        var builders: [StreamBuilder] = []
        var builderIndexByKey: [StreamKey: Int] = [:]

        for (recordIndex, record) in session.records.enumerated() {
            if record.event.breaksByteContinuity {
                continuityGeneration = try advancedContinuityGeneration(
                    continuityGeneration,
                    recordIndex: recordIndex,
                    sequenceNumber: record.sequenceNumber
                )
            }

            switch record.event {
            case let .value(value):
                guard value.peripheralIdentifier == peripheralIdentifier else { continue }
                guard !value.payload.isEmpty else {
                    throw PassiveBluetoothTuyaCandidateProjectionError.emptyValuePayload(
                        captureRecordIndex: recordIndex,
                        captureSequenceNumber: record.sequenceNumber,
                        serviceUUID: value.serviceUUID,
                        characteristicUUID: value.characteristicUUID,
                        origin: value.origin
                    )
                }

                let valueStreamIdentity = try TuyaCandidateValueStreamIdentity(
                    peripheralIdentifier: value.peripheralIdentifier,
                    serviceIdentifier: value.serviceUUID,
                    characteristicIdentifier: value.characteristicUUID
                )
                let sourceStream = PassiveBluetoothTuyaCandidateSourceStream(
                    valueStreamIdentity: valueStreamIdentity,
                    origin: value.origin
                )
                let key = StreamKey(
                    valueStreamIdentity: valueStreamIdentity,
                    originRawValue: value.origin.rawValue
                )
                let candidateObservation = try TuyaCandidateFragmentObservation(
                    streamIdentity: valueStreamIdentity,
                    continuityGeneration: continuityGeneration,
                    receiptUptimeNanoseconds: record.receivedAtUptimeNanoseconds,
                    receiptSequenceNumber: record.sequenceNumber,
                    receiptSequenceScope: receiptSequenceScope,
                    bytes: Array(value.payload)
                )
                let sourceFragment = PassiveBluetoothTuyaCandidateSourceFragment(
                    captureRecordIndex: recordIndex,
                    captureSequenceNumber: record.sequenceNumber,
                    receivedAtDate: record.receivedAtDate,
                    observation: candidateObservation
                )

                if let builderIndex = builderIndexByKey[key] {
                    builders[builderIndex].fragments.append(sourceFragment)
                } else {
                    builderIndexByKey[key] = builders.count
                    builders.append(StreamBuilder(
                        sourceStream: sourceStream,
                        fragments: [sourceFragment]
                    ))
                }

            case .advertisement,
                 .connection,
                 .service,
                 .includedService,
                 .characteristic,
                 .descriptor,
                 .subscription,
                 .stockAppState,
                 .interruption:
                continue
            }
        }

        return builders.map { builder in
            PassiveBluetoothTuyaCandidateStreamTranscript(
                captureContext: captureContext,
                sourceStream: builder.sourceStream,
                fragments: builder.fragments
            )
        }
    }

    /// Runs the bounded candidate analyzer independently for every exact
    /// GATT + origin transcript.
    public static func analyze(
        session: PassiveBluetoothCaptureSession,
        peripheralIdentifier: String,
        policy: TuyaCandidateFragmentReassemblyPolicy
    ) throws -> [PassiveBluetoothTuyaCandidateStreamAnalysis] {
        try transcripts(
            in: session,
            peripheralIdentifier: peripheralIdentifier
        ).map { transcript in
            PassiveBluetoothTuyaCandidateStreamAnalysis(
                transcript: transcript,
                events: TuyaCandidateTranscriptAnalyzer.analyze(
                    transcript.observations,
                    policy: policy
                )
            )
        }
    }

    private static func containsTargetAttributableEvidence(
        in session: PassiveBluetoothCaptureSession,
        peripheralIdentifier: String
    ) -> Bool {
        session.records.contains { record in
            switch record.event {
            case let .connection(observation):
                observation.peripheralIdentifier == peripheralIdentifier
            case let .service(observation):
                observation.peripheralIdentifier == peripheralIdentifier
            case let .includedService(observation):
                observation.peripheralIdentifier == peripheralIdentifier
            case let .characteristic(observation):
                observation.peripheralIdentifier == peripheralIdentifier
            case let .descriptor(observation):
                observation.peripheralIdentifier == peripheralIdentifier
            case let .subscription(observation):
                observation.peripheralIdentifier == peripheralIdentifier
            case let .value(observation):
                observation.peripheralIdentifier == peripheralIdentifier
            case .advertisement, .stockAppState, .interruption:
                false
            }
        }
    }

    private static func advancedContinuityGeneration(
        _ generation: UInt64,
        recordIndex: Int,
        sequenceNumber: UInt64
    ) throws -> UInt64 {
        let advanced = generation.addingReportingOverflow(1)
        guard !advanced.overflow else {
            throw PassiveBluetoothTuyaCandidateProjectionError.continuityGenerationOverflow(
                captureRecordIndex: recordIndex,
                captureSequenceNumber: sequenceNumber
            )
        }
        return advanced.partialValue
    }

    private struct StreamKey: Hashable {
        let valueStreamIdentity: TuyaCandidateValueStreamIdentity
        let originRawValue: String
    }

    private struct StreamBuilder {
        let sourceStream: PassiveBluetoothTuyaCandidateSourceStream
        var fragments: [PassiveBluetoothTuyaCandidateSourceFragment]
    }
}
