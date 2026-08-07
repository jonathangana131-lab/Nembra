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
    case serviceObserved = 1
    case characteristicFamilyObserved = 2
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

    private struct EvidenceAccumulator {
        var services: Set<String> = []
        var characteristicsByService: [String: Set<String>] = [:]

        var isEmpty: Bool {
            services.isEmpty && characteristicsByService.isEmpty
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

    public static func analyzeAll(
        _ session: PassiveBluetoothCaptureSession
    ) -> [PassiveBluetoothTransportFingerprintReport] {
        observedPeripheralIdentifiers(in: session)
            .sorted()
            .compactMap { analyze(session, peripheralIdentifier: $0) }
    }

    /// Aggregate identifier sets are descriptive ever-observed evidence. Match
    /// strength must come from one uninterrupted continuity segment for this
    /// exact peripheral. Structured disconnects from unrelated imported devices
    /// do not fragment the selected peripheral; generic interruptions remain a
    /// global observation gap because they carry no peripheral identity.
    ///
    /// Returns `nil` when the requested identifier never appears in any typed
    /// peripheral observation in the artifact. A non-`nil` report with empty
    /// topology/candidates therefore means the target was genuinely observed but
    /// no researched hosted-service evidence was established (for example,
    /// solicitation-only advertisement evidence).
    public static func analyze(
        _ session: PassiveBluetoothCaptureSession,
        peripheralIdentifier: String
    ) -> PassiveBluetoothTransportFingerprintReport? {
        guard observedPeripheralIdentifiers(in: session).contains(peripheralIdentifier) else {
            return nil
        }

        var aggregate = EvidenceAccumulator()
        var currentSegment = EvidenceAccumulator()
        var segments: [EvidenceAccumulator] = []

        for record in session.records {
            if breaksContinuity(
                record.event,
                peripheralIdentifier: peripheralIdentifier
            ) {
                if !currentSegment.isEmpty {
                    segments.append(currentSegment)
                }
                currentSegment = EvidenceAccumulator()
            }

            accumulate(
                record.event,
                peripheralIdentifier: peripheralIdentifier,
                into: &aggregate
            )
            accumulate(
                record.event,
                peripheralIdentifier: peripheralIdentifier,
                into: &currentSegment
            )
        }

        if !currentSegment.isEmpty {
            segments.append(currentSegment)
        }

        let matches = definitions.compactMap { definition in
            strongestMatch(for: definition, in: segments)
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

    private static func accumulate(
        _ event: PassiveBluetoothCaptureEvent,
        peripheralIdentifier: String,
        into evidence: inout EvidenceAccumulator
    ) {
        switch event {
        case let .advertisement(observation)
            where observation.peripheralIdentifier == peripheralIdentifier:
            evidence.services.formUnion(observation.serviceUUIDs.map(normalize))
            evidence.services.formUnion(observation.overflowServiceUUIDs.map(normalize))
            // Reconciled from PR #164: Service Solicitation has the opposite GAP
            // role. Preserve solicited UUIDs in raw advertisement evidence, but
            // never promote them into peripheral-hosted service topology.
            evidence.services.formUnion(observation.serviceData.keys.map(normalize))

        case let .service(observation)
            where observation.peripheralIdentifier == peripheralIdentifier:
            evidence.services.insert(normalize(observation.serviceUUID))

        case let .includedService(observation)
            where observation.peripheralIdentifier == peripheralIdentifier:
            evidence.services.insert(normalize(observation.parentServiceUUID))
            evidence.services.insert(normalize(observation.includedServiceUUID))

        case let .characteristic(observation)
            where observation.peripheralIdentifier == peripheralIdentifier:
            let service = normalize(observation.serviceUUID)
            evidence.services.insert(service)
            evidence.characteristicsByService[service, default: []]
                .insert(normalize(observation.characteristicUUID))

        case let .descriptor(observation)
            where observation.peripheralIdentifier == peripheralIdentifier:
            let service = normalize(observation.serviceUUID)
            evidence.services.insert(service)
            evidence.characteristicsByService[service, default: []]
                .insert(normalize(observation.characteristicUUID))

        case let .subscription(observation)
            where observation.peripheralIdentifier == peripheralIdentifier:
            let service = normalize(observation.serviceUUID)
            evidence.services.insert(service)
            evidence.characteristicsByService[service, default: []]
                .insert(normalize(observation.characteristicUUID))

        case let .value(observation)
            where observation.peripheralIdentifier == peripheralIdentifier:
            let service = normalize(observation.serviceUUID)
            evidence.services.insert(service)
            evidence.characteristicsByService[service, default: []]
                .insert(normalize(observation.characteristicUUID))

        default:
            break
        }
    }

    private static func strongestMatch(
        for definition: CandidateDefinition,
        in segments: [EvidenceAccumulator]
    ) -> PassiveBluetoothTransportCandidateMatch? {
        var strongest: PassiveBluetoothTransportCandidateMatch?

        for segment in segments {
            guard let candidate = match(for: definition, in: segment) else { continue }
            if strongest == nil || candidate.strength > strongest!.strength {
                strongest = candidate
            }
        }

        return strongest
    }

    private static func match(
        for definition: CandidateDefinition,
        in evidence: EvidenceAccumulator
    ) -> PassiveBluetoothTransportCandidateMatch? {
        guard evidence.services.contains(definition.serviceUUID) else { return nil }
        let observedCharacteristics = evidence.characteristicsByService[definition.serviceUUID] ?? []
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

    private static func breaksContinuity(
        _ event: PassiveBluetoothCaptureEvent,
        peripheralIdentifier: String
    ) -> Bool {
        switch event {
        case let .connection(observation):
            return observation.state == .disconnected
                && observation.peripheralIdentifier == peripheralIdentifier
        case .interruption:
            return true
        default:
            return false
        }
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