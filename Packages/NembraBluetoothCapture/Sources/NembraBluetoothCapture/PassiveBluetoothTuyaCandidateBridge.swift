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

    /// Producer-only construction prevents external callers from minting a
    /// capture context that never came from an immutable capture session.
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

    /// Producer-only construction keeps stream provenance bound to bridge
    /// projection rather than caller-authored research claims.
    init(
        valueStreamIdentity: TuyaCandidateValueStreamIdentity,
        origin: PassiveBluetoothValueOrigin
    ) {
        self.valueStreamIdentity = valueStreamIdentity
        self.origin = origin
    }
}

/// One lossless source mapping from a raw capture record into an analyzer
/// observation. Both source clocks remain present: boot-relative uptime is clock
/// metadata while immutable capture sequence is projected as the stronger scoped
/// callback-order authority. Wall-clock Date stays metadata exactly as captured
/// and never repairs ordering.
public struct PassiveBluetoothTuyaCandidateSourceFragment: Equatable, Sendable {
    public let captureRecordIndex: Int
    public let captureSequenceNumber: UInt64
    public let receivedAtDate: Date
    public let observation: TuyaCandidateFragmentObservation

    /// Producer-only construction prevents a detached analyzer observation from
    /// being relabeled as an exact raw-capture source mapping by external code.
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
/// Interleaved callbacks from other streams are intentionally filtered instead
/// of becoming fake stream-boundary evidence for this stream.
public struct PassiveBluetoothTuyaCandidateStreamTranscript: Equatable, Sendable {
    public let captureContext: PassiveBluetoothTuyaCandidateCaptureContext
    public let sourceStream: PassiveBluetoothTuyaCandidateSourceStream
    public let fragments: [PassiveBluetoothTuyaCandidateSourceFragment]

    /// Producer-only construction ensures the public transcript view cannot be
    /// assembled from mutually inconsistent context, stream, and fragments.
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

    /// Maps a stream-local analyzer observation index back to the exact raw
    /// capture record from which that observation came.
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

    /// Producer-only construction prevents external code from pairing arbitrary
    /// analyzer events with provenance they were not actually derived from.
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
    /// The requested peripheral must be present in target-attributable immutable
    /// evidence (connection or typed GATT/subscription/value evidence). A broad
    /// advertisement alone is candidate-catalog evidence and does not authorize
    /// target projection. An observed target with zero raw values legitimately
    /// returns an empty transcript set; an absent target fails closed instead of
    /// being flattened into the same result.
    ///
    /// Every projected value maps the immutable capture `sequenceNumber` to the
    /// analyzer's `receiptSequenceNumber`, scoped by this exact capture session's
    /// UUID string. The bridge never renumbers filtered stream-local fragments or
    /// invents a substitute clock/scope. Uptime and wall-clock Date remain the
    /// original capture metadata.
    ///
    /// Continuity generations advance for every gap already classified by the
    /// authoritative capture domain as `breaksByteContinuity`. Target attribution
    /// remains separate: a disconnect carrying another peripheral identifier is
    /// not relabeled as an ES80 disconnect, but its already-issued raw-byte gap is
    /// still preserved for downstream framing. Empty raw value payloads fail the
    /// whole projection rather than being dropped and accidentally allowing
    /// fragments on either side to splice.
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

    /// Runs the existing bounded candidate analyzer independently for every
    /// exact GATT + origin transcript. Analyzer observation indices remain
    /// stream-local and can be mapped back through `transcript.fragments`.
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
