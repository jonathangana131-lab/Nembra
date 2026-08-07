import Foundation
import NembraCore

/// Publicly researched transport families worth checking against raw ES80
/// evidence. A match is a *candidate fingerprint*, never protocol verification.
public enum PassiveBluetoothTransportCandidateFamily: String, CaseIterable, Sendable {
    case tuyaModernFD50
    case tuyaLegacyA201
    case tuyaLegacy1910
}

public enum PassiveBluetoothTransportCandidateStrength: Int, Comparable, Sendable {
    /// Candidate service appeared in an advertisement/service-data key or GATT
    /// discovery, but expected characteristic-family evidence is absent.
    case serviceObserved = 1

    /// Candidate service plus at least one characteristic from the researched
    /// family appeared in discovered GATT evidence.
    case characteristicFamilyObserved = 2

    /// Candidate service plus both primary data-path characteristics researched
    /// for that family appeared. This is still not target protocol proof.
    case expectedDataPathObserved = 3

    public static func < (
        lhs: PassiveBluetoothTransportCandidateStrength,
        rhs: PassiveBluetoothTransportCandidateStrength
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct PassiveBluetoothTransportCandidateMatch: Equatable, Sendable {
    public let family: PassiveBluetoothTransportCandidateFamily
    public let strength: PassiveBluetoothTransportCandidateStrength
    public let observedServiceUUIDs: Set<String>
    public let observedCharacteristicUUIDs: Set<String>

    public init(
        family: PassiveBluetoothTransportCandidateFamily,
        strength: PassiveBluetoothTransportCandidateStrength,
        observedServiceUUIDs: Set<String>,
        observedCharacteristicUUIDs: Set<String>
    ) {
        self.family = family
        self.strength = strength
        self.observedServiceUUIDs = observedServiceUUIDs
        self.observedCharacteristicUUIDs = observedCharacteristicUUIDs
    }
}

public struct PassiveBluetoothTransportFingerprintReport: Equatable, Sendable, Identifiable {
    public let peripheralIdentifier: String
    public let observedServiceUUIDs: Set<String>
    public let characteristicUUIDsByService: [String: Set<String>]
    public let candidateMatches: [PassiveBluetoothTransportCandidateMatch]

    public var id: String { peripheralIdentifier }

    public init(
        peripheralIdentifier: String,
        observedServiceUUIDs: Set<String>,
        characteristicUUIDsByService: [String: Set<String>],
        candidateMatches: [PassiveBluetoothTransportCandidateMatch]
    ) {
        self.peripheralIdentifier = peripheralIdentifier
        self.observedServiceUUIDs = observedServiceUUIDs
        self.characteristicUUIDsByService = characteristicUUIDsByService
        self.candidateMatches = candidateMatches
    }
}

public enum PassiveBluetoothTransportFingerprint {
    private struct CandidateDefinition {
        let family: PassiveBluetoothTransportCandidateFamily
        let serviceUUID: String
        let primaryCharacteristics: Set<String>
        let optionalCharacteristics: Set<String>
    }

    private struct ObservedTopology {
        var services: Set<String> = []
        var characteristicsByService: [String: Set<String>] = [:]

        mutating func observeService(_ serviceUUID: String) {
            services.insert(serviceUUID)
        }

        mutating func observeCharacteristic(_ characteristicUUID: String, serviceUUID: String) {
            services.insert(serviceUUID)
            characteristicsByService[serviceUUID, default: []].insert(characteristicUUID)
        }
    }

    private static let definitions: [CandidateDefinition] = [
        CandidateDefinition(
            family: .tuyaModernFD50,
            serviceUUID: "FD50",
            primaryCharacteristics: [
                "00000001-0000-1001-8001-00805F9B07D0",
                "00000002-0000-1001-8001-00805F9B07D0"
            ],
            optionalCharacteristics: [
                "00000003-0000-1001-8001-00805F9B07D0"
            ]
        ),
        CandidateDefinition(
            family: .tuyaLegacyA201,
            serviceUUID: "A201",
            primaryCharacteristics: ["2B10", "2B11"],
            optionalCharacteristics: []
        ),
        CandidateDefinition(
            family: .tuyaLegacy1910,
            serviceUUID: "1910",
            primaryCharacteristics: ["2B10", "2B11"],
            optionalCharacteristics: []
        )
    ]

    /// Produces one report per physically observed CoreBluetooth peripheral so
    /// advertisements from unrelated nearby devices can never contaminate a
    /// selected scooter's candidate transport fingerprint.
    public static func analyzeAll(
        _ session: PassiveBluetoothCaptureSession
    ) -> [PassiveBluetoothTransportFingerprintReport] {
        observedPeripheralIdentifiers(in: session)
            .sorted()
            .map { analyze(session, peripheralIdentifier: $0) }
    }

    /// Summarizes raw advertisement/GATT identifiers for exactly one peripheral
    /// without decoding payloads or choosing a single candidate-family winner.
    /// Multiple candidate families can match and an empty match list is valid.
    /// Connection lifecycle alone establishes no GATT topology. A subscription
    /// record may establish only the exact service/characteristic path it names.
    ///
    /// The report-level topology is an "ever observed" inventory. Candidate
    /// strength is stricter: it is the strongest topology actually observed
    /// inside one parent-model byte-continuity segment. Evidence on opposite
    /// sides of a disconnect/interruption may remain visible in the inventory,
    /// but it can never be combined to manufacture a stronger transport match.
    public static func analyze(
        _ session: PassiveBluetoothCaptureSession,
        peripheralIdentifier: String
    ) -> PassiveBluetoothTransportFingerprintReport {
        var aggregate = ObservedTopology()
        var currentSegment = ObservedTopology()
        var segments: [ObservedTopology] = []

        for record in session.records {
            if record.event.breaksByteContinuity {
                segments.append(currentSegment)
                currentSegment = ObservedTopology()
                continue
            }

            switch record.event {
            case let .advertisement(observation)
                where observation.peripheralIdentifier == peripheralIdentifier:
                for service in observation.serviceUUIDs {
                    observeService(service, aggregate: &aggregate, segment: &currentSegment)
                }
                for service in observation.overflowServiceUUIDs {
                    observeService(service, aggregate: &aggregate, segment: &currentSegment)
                }
                // Service Solicitation has the opposite GAP role: it names
                // services the peripheral wants a central to provide. Preserve
                // those UUIDs in raw advertisement evidence, but never promote
                // them into peripheral-hosted GATT/candidate-service topology.
                for service in observation.serviceData.keys {
                    observeService(service, aggregate: &aggregate, segment: &currentSegment)
                }

            case let .service(observation)
                where observation.peripheralIdentifier == peripheralIdentifier:
                observeService(
                    observation.serviceUUID,
                    aggregate: &aggregate,
                    segment: &currentSegment
                )

            case let .includedService(observation)
                where observation.peripheralIdentifier == peripheralIdentifier:
                observeService(
                    observation.parentServiceUUID,
                    aggregate: &aggregate,
                    segment: &currentSegment
                )
                observeService(
                    observation.includedServiceUUID,
                    aggregate: &aggregate,
                    segment: &currentSegment
                )

            case let .characteristic(observation)
                where observation.peripheralIdentifier == peripheralIdentifier:
                observeCharacteristic(
                    observation.characteristicUUID,
                    serviceUUID: observation.serviceUUID,
                    aggregate: &aggregate,
                    segment: &currentSegment
                )

            case let .descriptor(observation)
                where observation.peripheralIdentifier == peripheralIdentifier:
                // Descriptor evidence confirms the parent GATT path existed even
                // if a partial/imported capture lacks a separate service record.
                observeCharacteristic(
                    observation.characteristicUUID,
                    serviceUUID: observation.serviceUUID,
                    aggregate: &aggregate,
                    segment: &currentSegment
                )

            case let .subscription(observation)
                where observation.peripheralIdentifier == peripheralIdentifier:
                // Subscription-state evidence names one exact observed GATT path.
                // It does not say anything about application protocol meaning.
                observeCharacteristic(
                    observation.characteristicUUID,
                    serviceUUID: observation.serviceUUID,
                    aggregate: &aggregate,
                    segment: &currentSegment
                )

            case let .value(observation)
                where observation.peripheralIdentifier == peripheralIdentifier:
                // Same rule for partial captures containing value evidence.
                observeCharacteristic(
                    observation.characteristicUUID,
                    serviceUUID: observation.serviceUUID,
                    aggregate: &aggregate,
                    segment: &currentSegment
                )

            default:
                break
            }
        }
        segments.append(currentSegment)

        let matches = definitions.compactMap { definition -> PassiveBluetoothTransportCandidateMatch? in
            guard aggregate.services.contains(definition.serviceUUID) else { return nil }
            let aggregateCharacteristics = aggregate.characteristicsByService[definition.serviceUUID] ?? []
            let researchedCharacteristics = definition.primaryCharacteristics
                .union(definition.optionalCharacteristics)
            let matchingCharacteristics = aggregateCharacteristics.intersection(researchedCharacteristics)

            let strongestSegment = segments.compactMap { segment -> PassiveBluetoothTransportCandidateStrength? in
                guard segment.services.contains(definition.serviceUUID) else { return nil }
                let observedCharacteristics = segment.characteristicsByService[definition.serviceUUID] ?? []
                let matching = observedCharacteristics.intersection(researchedCharacteristics)

                if definition.primaryCharacteristics.isSubset(of: observedCharacteristics) {
                    return .expectedDataPathObserved
                }
                if !matching.isEmpty {
                    return .characteristicFamilyObserved
                }
                return .serviceObserved
            }
            .max()

            guard let strength = strongestSegment else { return nil }
            return PassiveBluetoothTransportCandidateMatch(
                family: definition.family,
                strength: strength,
                observedServiceUUIDs: [definition.serviceUUID],
                observedCharacteristicUUIDs: matchingCharacteristics
            )
        }
        .sorted { lhs, rhs in
            if lhs.strength != rhs.strength { return lhs.strength > rhs.strength }
            return lhs.family.rawValue < rhs.family.rawValue
        }

        return PassiveBluetoothTransportFingerprintReport(
            peripheralIdentifier: peripheralIdentifier,
            observedServiceUUIDs: aggregate.services,
            characteristicUUIDsByService: aggregate.characteristicsByService,
            candidateMatches: matches
        )
    }

    private static func observeService(
        _ rawServiceUUID: String,
        aggregate: inout ObservedTopology,
        segment: inout ObservedTopology
    ) {
        let serviceUUID = normalize(rawServiceUUID)
        aggregate.observeService(serviceUUID)
        segment.observeService(serviceUUID)
    }

    private static func observeCharacteristic(
        _ rawCharacteristicUUID: String,
        serviceUUID rawServiceUUID: String,
        aggregate: inout ObservedTopology,
        segment: inout ObservedTopology
    ) {
        let serviceUUID = normalize(rawServiceUUID)
        let characteristicUUID = normalize(rawCharacteristicUUID)
        aggregate.observeCharacteristic(characteristicUUID, serviceUUID: serviceUUID)
        segment.observeCharacteristic(characteristicUUID, serviceUUID: serviceUUID)
    }

    private static func observedPeripheralIdentifiers(
        in session: PassiveBluetoothCaptureSession
    ) -> Set<String> {
        var identifiers: Set<String> = []
        for record in session.records {
            switch record.event {
            case let .advertisement(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .connection(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .service(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .includedService(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .characteristic(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .descriptor(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .subscription(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .value(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case .stockAppState, .interruption:
                break
            }
        }
        return identifiers
    }

    private static func normalize(_ identifier: String) -> String {
        identifier.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
