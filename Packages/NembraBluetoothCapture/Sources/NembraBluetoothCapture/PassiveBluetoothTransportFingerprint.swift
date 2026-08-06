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

public struct PassiveBluetoothTransportFingerprintReport: Equatable, Sendable {
    public let observedServiceUUIDs: Set<String>
    public let characteristicUUIDsByService: [String: Set<String>]
    public let candidateMatches: [PassiveBluetoothTransportCandidateMatch]

    public init(
        observedServiceUUIDs: Set<String>,
        characteristicUUIDsByService: [String: Set<String>],
        candidateMatches: [PassiveBluetoothTransportCandidateMatch]
    ) {
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

    /// Summarizes raw advertisement/GATT identifiers without decoding payloads
    /// or choosing a single "winner." Multiple candidate families can match the
    /// same capture, and an empty match list is a valid/important result.
    public static func analyze(
        _ session: PassiveBluetoothCaptureSession
    ) -> PassiveBluetoothTransportFingerprintReport {
        var services: Set<String> = []
        var characteristicsByService: [String: Set<String>] = [:]

        for record in session.records {
            switch record.event {
            case let .advertisement(observation):
                services.formUnion(observation.serviceUUIDs.map(normalize))
                services.formUnion(observation.overflowServiceUUIDs.map(normalize))
                services.formUnion(observation.solicitedServiceUUIDs.map(normalize))
                services.formUnion(observation.serviceData.keys.map(normalize))

            case let .service(observation):
                services.insert(normalize(observation.serviceUUID))

            case let .includedService(observation):
                services.insert(normalize(observation.parentServiceUUID))
                services.insert(normalize(observation.includedServiceUUID))

            case let .characteristic(observation):
                let service = normalize(observation.serviceUUID)
                services.insert(service)
                characteristicsByService[service, default: []]
                    .insert(normalize(observation.characteristicUUID))

            case let .descriptor(observation):
                // Descriptor evidence confirms the parent GATT path existed even
                // if a partial/imported capture lacks a separate service record.
                let service = normalize(observation.serviceUUID)
                services.insert(service)
                characteristicsByService[service, default: []]
                    .insert(normalize(observation.characteristicUUID))

            case let .value(observation):
                // Same rule for partial captures containing value evidence.
                let service = normalize(observation.serviceUUID)
                services.insert(service)
                characteristicsByService[service, default: []]
                    .insert(normalize(observation.characteristicUUID))

            case .stockAppState, .interruption:
                break
            }
        }

        let matches = definitions.compactMap { definition -> PassiveBluetoothTransportCandidateMatch? in
            guard services.contains(definition.serviceUUID) else { return nil }
            let observedCharacteristics = characteristicsByService[definition.serviceUUID] ?? []
            let researchedCharacteristics = definition.primaryCharacteristics
                .union(definition.optionalCharacteristics)
            let matchingCharacteristics = observedCharacteristics.intersection(researchedCharacteristics)

            let strength: PassiveBluetoothTransportCandidateStrength
            if definition.primaryCharacteristics.isSubset(of: observedCharacteristics) {
                strength = .expectedDataPathObserved
            } else if !matchingCharacteristics.isEmpty {
                strength = .characteristicFamilyObserved
            } else {
                strength = .serviceObserved
            }

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
            observedServiceUUIDs: services,
            characteristicUUIDsByService: characteristicsByService,
            candidateMatches: matches
        )
    }

    private static func normalize(_ identifier: String) -> String {
        identifier.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
