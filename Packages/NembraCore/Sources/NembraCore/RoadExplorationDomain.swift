import Foundation

public enum RoadExplorationDomainError: Error, Equatable, Sendable {
    case invalidDatasetIdentity
    case invalidLicenseMetadata
    case invalidRoadSegment
    case roadSegmentConflict(RoadSegmentID)
    case invalidCoveragePolicy
    case invalidRouteDigest
    case invalidMatcherIdentity
    case invalidSourcePointRange
    case invalidCoverageInterval
    case invalidMatchClaim
    case invalidMatchRun
    case matchRunConflict(UUID)
    case matchRunBindingConflict(existing: UUID, incoming: UUID)
    case aggregateOverflow
}

private func nonemptyRoadValue(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

// MARK: - Versioned road-network authority

/// The provider-neutral identity of one immutable road graph revision.
///
/// Provider selection is intentionally outside this domain. Segment IDs and
/// match runs carry this key so evidence from two graph revisions can never be
/// combined accidentally.
public struct RoadDatasetKey: Codable, Equatable, Hashable, Sendable, Comparable {
    public let providerID: String
    public let regionID: String
    public let graphVersion: String

    private enum CodingKeys: String, CodingKey {
        case providerID
        case regionID
        case graphVersion
    }

    public init(providerID: String, regionID: String, graphVersion: String) throws {
        guard let providerID = nonemptyRoadValue(providerID),
              let regionID = nonemptyRoadValue(regionID),
              let graphVersion = nonemptyRoadValue(graphVersion) else {
            throw RoadExplorationDomainError.invalidDatasetIdentity
        }
        self.providerID = providerID
        self.regionID = regionID
        self.graphVersion = graphVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                providerID: container.decode(String.self, forKey: .providerID),
                regionID: container.decode(String.self, forKey: .regionID),
                graphVersion: container.decode(String.self, forKey: .graphVersion)
            )
        } catch RoadExplorationDomainError.invalidDatasetIdentity {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid road dataset key.")
            )
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.providerID != rhs.providerID { return lhs.providerID < rhs.providerID }
        if lhs.regionID != rhs.regionID { return lhs.regionID < rhs.regionID }
        return lhs.graphVersion < rhs.graphVersion
    }
}

public enum RoadDatasetLicenseReviewState: String, Codable, Equatable, Hashable, Sendable {
    case pending
    case approved
    case rejected
}

/// License and attribution authority for a road graph.
///
/// An approved review record is required before the graph may provide a city
/// denominator or verified coverage. This makes attribution and distribution
/// review a data prerequisite rather than a presentation afterthought.
public struct RoadDatasetLicense: Codable, Equatable, Hashable, Sendable {
    public let licenseIdentifier: String
    public let licenseVersion: String
    public let attributionText: String
    public let attributionURL: URL?
    public let reviewState: RoadDatasetLicenseReviewState
    public let reviewReference: String?

    private enum CodingKeys: String, CodingKey {
        case licenseIdentifier
        case licenseVersion
        case attributionText
        case attributionURL
        case reviewState
        case reviewReference
    }

    public init(
        licenseIdentifier: String,
        licenseVersion: String,
        attributionText: String,
        attributionURL: URL? = nil,
        reviewState: RoadDatasetLicenseReviewState,
        reviewReference: String? = nil
    ) throws {
        guard let licenseIdentifier = nonemptyRoadValue(licenseIdentifier),
              let licenseVersion = nonemptyRoadValue(licenseVersion),
              let attributionText = nonemptyRoadValue(attributionText) else {
            throw RoadExplorationDomainError.invalidLicenseMetadata
        }

        let normalizedReviewReference = reviewReference.flatMap(nonemptyRoadValue)
        if reviewState != .pending, normalizedReviewReference == nil {
            throw RoadExplorationDomainError.invalidLicenseMetadata
        }
        if let attributionURL,
           attributionURL.scheme?.lowercased() != "https" {
            throw RoadExplorationDomainError.invalidLicenseMetadata
        }

        self.licenseIdentifier = licenseIdentifier
        self.licenseVersion = licenseVersion
        self.attributionText = attributionText
        self.attributionURL = attributionURL
        self.reviewState = reviewState
        self.reviewReference = normalizedReviewReference
    }

    public var authorizesCoverage: Bool {
        reviewState == .approved && reviewReference != nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                licenseIdentifier: container.decode(String.self, forKey: .licenseIdentifier),
                licenseVersion: container.decode(String.self, forKey: .licenseVersion),
                attributionText: container.decode(String.self, forKey: .attributionText),
                attributionURL: container.decodeIfPresent(URL.self, forKey: .attributionURL),
                reviewState: container.decode(RoadDatasetLicenseReviewState.self, forKey: .reviewState),
                reviewReference: container.decodeIfPresent(String.self, forKey: .reviewReference)
            )
        } catch RoadExplorationDomainError.invalidLicenseMetadata {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid road dataset license metadata.")
            )
        }
    }
}

public struct RoadDatasetIdentity: Codable, Equatable, Hashable, Sendable {
    public let key: RoadDatasetKey
    public let license: RoadDatasetLicense

    public init(key: RoadDatasetKey, license: RoadDatasetLicense) {
        self.key = key
        self.license = license
    }
}

public struct RoadSegmentID: Codable, Equatable, Hashable, Sendable, Comparable {
    public let datasetKey: RoadDatasetKey
    public let canonicalID: String

    private enum CodingKeys: String, CodingKey {
        case datasetKey
        case canonicalID
    }

    public init(datasetKey: RoadDatasetKey, canonicalID: String) throws {
        guard let canonicalID = nonemptyRoadValue(canonicalID) else {
            throw RoadExplorationDomainError.invalidRoadSegment
        }
        self.datasetKey = datasetKey
        self.canonicalID = canonicalID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                datasetKey: container.decode(RoadDatasetKey.self, forKey: .datasetKey),
                canonicalID: container.decode(String.self, forKey: .canonicalID)
            )
        } catch RoadExplorationDomainError.invalidRoadSegment {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid canonical road segment ID.")
            )
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.datasetKey != rhs.datasetKey { return lhs.datasetKey < rhs.datasetKey }
        return lhs.canonicalID < rhs.canonicalID
    }
}

public enum RoadSegmentDirectionality: String, Codable, Equatable, Hashable, Sendable {
    case bidirectional
    case canonicalDirectionOnly
    case reverseDirectionOnly
    case unknown
}

public enum RoadAccessEligibilityDisposition: String, Codable, Equatable, Hashable, Sendable {
    case eligible
    case ineligible
    case unknown
}

/// Provider-normalized access truth used by the selected eligibility policy.
public struct RoadAccessEligibility: Codable, Equatable, Hashable, Sendable {
    public let disposition: RoadAccessEligibilityDisposition
    public let rationaleCode: String?

    private enum CodingKeys: String, CodingKey {
        case disposition
        case rationaleCode
    }

    public init(
        disposition: RoadAccessEligibilityDisposition,
        rationaleCode: String? = nil
    ) throws {
        let normalizedRationale = rationaleCode.flatMap(nonemptyRoadValue)
        if disposition != .eligible, normalizedRationale == nil {
            throw RoadExplorationDomainError.invalidRoadSegment
        }
        self.disposition = disposition
        self.rationaleCode = normalizedRationale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                disposition: container.decode(RoadAccessEligibilityDisposition.self, forKey: .disposition),
                rationaleCode: container.decodeIfPresent(String.self, forKey: .rationaleCode)
            )
        } catch RoadExplorationDomainError.invalidRoadSegment {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid road access eligibility.")
            )
        }
    }
}

/// Canonical provider-neutral attributes needed for coverage accounting.
/// Geometry and spatial indexing live behind the provider boundary, not here.
public struct RoadSegmentDefinition: Codable, Equatable, Hashable, Sendable {
    public let id: RoadSegmentID
    public let canonicalLengthMeters: Double
    public let directionality: RoadSegmentDirectionality
    public let classification: String
    public let access: RoadAccessEligibility
    public let areaMembershipIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case canonicalLengthMeters
        case directionality
        case classification
        case access
        case areaMembershipIDs
    }

    public init(
        id: RoadSegmentID,
        canonicalLengthMeters: Double,
        directionality: RoadSegmentDirectionality,
        classification: String,
        access: RoadAccessEligibility,
        areaMembershipIDs: [String] = []
    ) throws {
        guard canonicalLengthMeters.isFinite,
              canonicalLengthMeters > 0,
              let classification = nonemptyRoadValue(classification) else {
            throw RoadExplorationDomainError.invalidRoadSegment
        }

        var memberships = Set<String>()
        for membership in areaMembershipIDs {
            guard let normalized = nonemptyRoadValue(membership) else {
                throw RoadExplorationDomainError.invalidRoadSegment
            }
            memberships.insert(normalized)
        }

        self.id = id
        self.canonicalLengthMeters = canonicalLengthMeters
        self.directionality = directionality
        self.classification = classification
        self.access = access
        self.areaMembershipIDs = memberships.sorted()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                id: container.decode(RoadSegmentID.self, forKey: .id),
                canonicalLengthMeters: container.decode(Double.self, forKey: .canonicalLengthMeters),
                directionality: container.decode(RoadSegmentDirectionality.self, forKey: .directionality),
                classification: container.decode(String.self, forKey: .classification),
                access: container.decode(RoadAccessEligibility.self, forKey: .access),
                areaMembershipIDs: container.decode([String].self, forKey: .areaMembershipIDs)
            )
        } catch RoadExplorationDomainError.invalidRoadSegment {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid canonical road segment.")
            )
        }
    }
}

public struct RoadNetworkCatalog: Sendable {
    public let dataset: RoadDatasetIdentity
    public let segments: [RoadSegmentDefinition]
    public let eligibleTraversableLengthMeters: Double
    public let eligibleSegmentCount: Int

    private let segmentsByID: [RoadSegmentID: RoadSegmentDefinition]

    public init(dataset: RoadDatasetIdentity, segments: [RoadSegmentDefinition]) throws {
        var definitionsByID: [RoadSegmentID: RoadSegmentDefinition] = [:]
        for segment in segments {
            guard segment.id.datasetKey == dataset.key else {
                throw RoadExplorationDomainError.invalidRoadSegment
            }
            if let existing = definitionsByID[segment.id] {
                guard existing == segment else {
                    throw RoadExplorationDomainError.roadSegmentConflict(segment.id)
                }
                continue
            }
            definitionsByID[segment.id] = segment
        }

        let canonicalSegments = definitionsByID.values.sorted { $0.id < $1.id }
        var eligibleLength = 0.0
        var eligibleCount = 0
        for segment in canonicalSegments where segment.access.disposition == .eligible {
            eligibleLength += segment.canonicalLengthMeters
            guard eligibleLength.isFinite else {
                throw RoadExplorationDomainError.aggregateOverflow
            }
            eligibleCount += 1
        }

        self.dataset = dataset
        self.segments = canonicalSegments
        self.eligibleTraversableLengthMeters = eligibleLength
        self.eligibleSegmentCount = eligibleCount
        self.segmentsByID = definitionsByID
    }

    public func segment(for id: RoadSegmentID) -> RoadSegmentDefinition? {
        segmentsByID[id]
    }
}

// MARK: - Coverage and match policy

public enum RoadCoverageDirectionPolicy: String, Codable, Equatable, Hashable, Sendable {
    /// Traversing either direction covers the same canonical road geometry.
    case directionAgnostic
}

public enum RoadCoverageDenominatorPolicy: String, Codable, Equatable, Hashable, Sendable {
    /// Sum canonical length once for each eligible traversable segment.
    case eligibleTraversableLength
}

public struct RoadCoveragePolicy: Codable, Equatable, Hashable, Sendable {
    public let version: String
    public let directionPolicy: RoadCoverageDirectionPolicy
    public let denominatorPolicy: RoadCoverageDenominatorPolicy
    public let minimumAcceptedConfidence: Double
    public let minimumVerifiedClaimLengthMeters: Double

    private enum CodingKeys: String, CodingKey {
        case version
        case directionPolicy
        case denominatorPolicy
        case minimumAcceptedConfidence
        case minimumVerifiedClaimLengthMeters
    }

    public init(
        version: String,
        directionPolicy: RoadCoverageDirectionPolicy = .directionAgnostic,
        denominatorPolicy: RoadCoverageDenominatorPolicy = .eligibleTraversableLength,
        minimumAcceptedConfidence: Double,
        minimumVerifiedClaimLengthMeters: Double = 0
    ) throws {
        guard let version = nonemptyRoadValue(version),
              minimumAcceptedConfidence.isFinite,
              (0 ... 1).contains(minimumAcceptedConfidence),
              minimumVerifiedClaimLengthMeters.isFinite,
              minimumVerifiedClaimLengthMeters >= 0 else {
            throw RoadExplorationDomainError.invalidCoveragePolicy
        }
        self.version = version
        self.directionPolicy = directionPolicy
        self.denominatorPolicy = denominatorPolicy
        self.minimumAcceptedConfidence = minimumAcceptedConfidence
        self.minimumVerifiedClaimLengthMeters = minimumVerifiedClaimLengthMeters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                version: container.decode(String.self, forKey: .version),
                directionPolicy: container.decode(RoadCoverageDirectionPolicy.self, forKey: .directionPolicy),
                denominatorPolicy: container.decode(RoadCoverageDenominatorPolicy.self, forKey: .denominatorPolicy),
                minimumAcceptedConfidence: container.decode(Double.self, forKey: .minimumAcceptedConfidence),
                minimumVerifiedClaimLengthMeters: container.decode(Double.self, forKey: .minimumVerifiedClaimLengthMeters)
            )
        } catch RoadExplorationDomainError.invalidCoveragePolicy {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid road coverage policy.")
            )
        }
    }
}

public struct RoadMatcherIdentity: Codable, Equatable, Hashable, Sendable {
    public let matcherID: String
    public let version: String

    private enum CodingKeys: String, CodingKey {
        case matcherID
        case version
    }

    public init(matcherID: String, version: String) throws {
        guard let matcherID = nonemptyRoadValue(matcherID),
              let version = nonemptyRoadValue(version) else {
            throw RoadExplorationDomainError.invalidMatcherIdentity
        }
        self.matcherID = matcherID
        self.version = version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                matcherID: container.decode(String.self, forKey: .matcherID),
                version: container.decode(String.self, forKey: .version)
            )
        } catch RoadExplorationDomainError.invalidMatcherIdentity {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid road matcher identity.")
            )
        }
    }
}

// MARK: - Immutable route and match evidence

public enum RoadRouteDigestAlgorithm: String, Codable, Equatable, Hashable, Sendable {
    case sha256
}

/// Digest of the immutable accepted raw route bytes supplied to a matcher.
public struct RoadRouteDigest: Codable, Equatable, Hashable, Sendable {
    public let algorithm: RoadRouteDigestAlgorithm
    public let lowercaseHexValue: String

    private enum CodingKeys: String, CodingKey {
        case algorithm
        case lowercaseHexValue
    }

    public init(algorithm: RoadRouteDigestAlgorithm = .sha256, hexValue: String) throws {
        let normalized = hexValue.lowercased()
        let isHex = normalized.utf8.allSatisfy {
            (48 ... 57).contains($0) || (97 ... 102).contains($0)
        }
        guard normalized.utf8.count == 64, isHex else {
            throw RoadExplorationDomainError.invalidRouteDigest
        }
        self.algorithm = algorithm
        self.lowercaseHexValue = normalized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                algorithm: container.decode(RoadRouteDigestAlgorithm.self, forKey: .algorithm),
                hexValue: container.decode(String.self, forKey: .lowercaseHexValue)
            )
        } catch RoadExplorationDomainError.invalidRouteDigest {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid immutable route digest.")
            )
        }
    }
}

public struct RoadSourcePointRange: Codable, Equatable, Hashable, Sendable {
    public let firstIndex: UInt64
    public let lastIndex: UInt64

    private enum CodingKeys: String, CodingKey {
        case firstIndex
        case lastIndex
    }

    public init(firstIndex: UInt64, lastIndex: UInt64) throws {
        guard firstIndex <= lastIndex else {
            throw RoadExplorationDomainError.invalidSourcePointRange
        }
        self.firstIndex = firstIndex
        self.lastIndex = lastIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                firstIndex: container.decode(UInt64.self, forKey: .firstIndex),
                lastIndex: container.decode(UInt64.self, forKey: .lastIndex)
            )
        } catch RoadExplorationDomainError.invalidSourcePointRange {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid source point range.")
            )
        }
    }
}

/// A fractional interval in the segment's canonical geometry orientation.
/// Reverse travel is normalized into this same orientation by the matcher.
public struct RoadCoverageInterval: Codable, Equatable, Hashable, Sendable {
    public let lowerBound: Double
    public let upperBound: Double

    private enum CodingKeys: String, CodingKey {
        case lowerBound
        case upperBound
    }

    public init(lowerBound: Double, upperBound: Double) throws {
        guard lowerBound.isFinite,
              upperBound.isFinite,
              lowerBound >= 0,
              upperBound <= 1,
              lowerBound < upperBound else {
            throw RoadExplorationDomainError.invalidCoverageInterval
        }
        self.lowerBound = lowerBound == 0 ? 0 : lowerBound
        self.upperBound = upperBound == 1 ? 1 : upperBound
    }

    public var normalizedLength: Double {
        upperBound - lowerBound
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                lowerBound: container.decode(Double.self, forKey: .lowerBound),
                upperBound: container.decode(Double.self, forKey: .upperBound)
            )
        } catch RoadExplorationDomainError.invalidCoverageInterval {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid normalized road interval.")
            )
        }
    }

    /// Canonical deterministic union. Overlapping and touching intervals merge.
    public static func normalizedUnion(_ intervals: [Self]) throws -> [Self] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted {
            if $0.lowerBound != $1.lowerBound { return $0.lowerBound < $1.lowerBound }
            return $0.upperBound < $1.upperBound
        }
        var result: [Self] = []
        result.reserveCapacity(sorted.count)
        var current = sorted[0]
        for next in sorted.dropFirst() {
            if next.lowerBound <= current.upperBound {
                current = try Self(
                    lowerBound: current.lowerBound,
                    upperBound: max(current.upperBound, next.upperBound)
                )
            } else {
                result.append(current)
                current = next
            }
        }
        result.append(current)
        return result
    }

    /// Returns the portions of `intervals` not already present in `coveredBy`.
    /// This is used to create a one-shot discovery delta without treating a
    /// render animation as durable road evidence.
    public static func subtracting(
        _ intervals: [Self],
        coveredBy existingIntervals: [Self]
    ) throws -> [Self] {
        var remaining = try normalizedUnion(intervals)
        let existing = try normalizedUnion(existingIntervals)
        guard !remaining.isEmpty, !existing.isEmpty else { return remaining }

        for covered in existing {
            var nextRemaining: [Self] = []
            for candidate in remaining {
                if covered.upperBound <= candidate.lowerBound
                    || covered.lowerBound >= candidate.upperBound {
                    nextRemaining.append(candidate)
                    continue
                }
                if covered.lowerBound > candidate.lowerBound {
                    nextRemaining.append(
                        try Self(
                            lowerBound: candidate.lowerBound,
                            upperBound: min(covered.lowerBound, candidate.upperBound)
                        )
                    )
                }
                if covered.upperBound < candidate.upperBound {
                    nextRemaining.append(
                        try Self(
                            lowerBound: max(covered.upperBound, candidate.lowerBound),
                            upperBound: candidate.upperBound
                        )
                    )
                }
            }
            remaining = nextRemaining
            if remaining.isEmpty { break }
        }
        return try normalizedUnion(remaining)
    }
}

public enum RoadMatchDisposition: String, Codable, Equatable, Hashable, Sendable {
    case matched
    case unmatched
    case uncertain
}

public enum RoadMatchAmbiguity: String, Codable, Equatable, Hashable, Sendable {
    case none
    case parallelRoads
    case dividedCarriageway
    case intersection
    case multipleCandidates
    case insufficientGeometry
}

public enum RoadTraversalDirectionEvidence: String, Codable, Equatable, Hashable, Sendable {
    case canonical
    case reverse
    case mixed
    case unknown
}

public enum RoadRideEvidenceStatus: String, Codable, Equatable, Hashable, Sendable {
    case independentlyVerifiedRiding
    case unverified
    case conflicting
}

/// One matcher claim tied to exact raw-route point indices.
///
/// Ambiguous and uncertain claims deliberately preserve their candidate data
/// for later reprocessing, but the projection never promotes them to coverage.
public struct RoadMatchClaim: Codable, Equatable, Hashable, Sendable {
    public let sourcePointRange: RoadSourcePointRange
    public let disposition: RoadMatchDisposition
    public let segmentID: RoadSegmentID?
    public let confidence: Double
    public let ambiguity: RoadMatchAmbiguity
    public let directionEvidence: RoadTraversalDirectionEvidence
    public let rideEvidenceStatus: RoadRideEvidenceStatus
    public let coveredIntervals: [RoadCoverageInterval]

    private enum CodingKeys: String, CodingKey {
        case sourcePointRange
        case disposition
        case segmentID
        case confidence
        case ambiguity
        case directionEvidence
        case rideEvidenceStatus
        case coveredIntervals
    }

    public init(
        sourcePointRange: RoadSourcePointRange,
        disposition: RoadMatchDisposition,
        segmentID: RoadSegmentID?,
        confidence: Double,
        ambiguity: RoadMatchAmbiguity,
        directionEvidence: RoadTraversalDirectionEvidence,
        rideEvidenceStatus: RoadRideEvidenceStatus,
        coveredIntervals: [RoadCoverageInterval]
    ) throws {
        guard confidence.isFinite, (0 ... 1).contains(confidence) else {
            throw RoadExplorationDomainError.invalidMatchClaim
        }
        let canonicalIntervals = try RoadCoverageInterval.normalizedUnion(coveredIntervals)
        switch disposition {
        case .matched:
            guard segmentID != nil, !canonicalIntervals.isEmpty else {
                throw RoadExplorationDomainError.invalidMatchClaim
            }
        case .unmatched:
            guard segmentID == nil,
                  canonicalIntervals.isEmpty,
                  ambiguity == .none,
                  directionEvidence == .unknown else {
                throw RoadExplorationDomainError.invalidMatchClaim
            }
        case .uncertain:
            if segmentID == nil, !canonicalIntervals.isEmpty {
                throw RoadExplorationDomainError.invalidMatchClaim
            }
        }

        self.sourcePointRange = sourcePointRange
        self.disposition = disposition
        self.segmentID = segmentID
        self.confidence = confidence
        self.ambiguity = ambiguity
        self.directionEvidence = directionEvidence
        self.rideEvidenceStatus = rideEvidenceStatus
        self.coveredIntervals = canonicalIntervals
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                sourcePointRange: container.decode(RoadSourcePointRange.self, forKey: .sourcePointRange),
                disposition: container.decode(RoadMatchDisposition.self, forKey: .disposition),
                segmentID: container.decodeIfPresent(RoadSegmentID.self, forKey: .segmentID),
                confidence: container.decode(Double.self, forKey: .confidence),
                ambiguity: container.decode(RoadMatchAmbiguity.self, forKey: .ambiguity),
                directionEvidence: container.decode(RoadTraversalDirectionEvidence.self, forKey: .directionEvidence),
                rideEvidenceStatus: container.decode(RoadRideEvidenceStatus.self, forKey: .rideEvidenceStatus),
                coveredIntervals: container.decode([RoadCoverageInterval].self, forKey: .coveredIntervals)
            )
        } catch RoadExplorationDomainError.invalidCoverageInterval,
                RoadExplorationDomainError.invalidMatchClaim {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid road match claim.")
            )
        }
    }
}

public struct RoadMatchRunBinding: Codable, Equatable, Hashable, Sendable {
    public let rawRouteDigest: RoadRouteDigest
    public let datasetKey: RoadDatasetKey
    public let matcher: RoadMatcherIdentity
    public let coveragePolicyVersion: String

    private enum CodingKeys: String, CodingKey {
        case rawRouteDigest
        case datasetKey
        case matcher
        case coveragePolicyVersion
    }

    public init(
        rawRouteDigest: RoadRouteDigest,
        datasetKey: RoadDatasetKey,
        matcher: RoadMatcherIdentity,
        coveragePolicyVersion: String
    ) throws {
        guard let coveragePolicyVersion = nonemptyRoadValue(coveragePolicyVersion) else {
            throw RoadExplorationDomainError.invalidMatchRun
        }
        self.rawRouteDigest = rawRouteDigest
        self.datasetKey = datasetKey
        self.matcher = matcher
        self.coveragePolicyVersion = coveragePolicyVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                rawRouteDigest: container.decode(RoadRouteDigest.self, forKey: .rawRouteDigest),
                datasetKey: container.decode(RoadDatasetKey.self, forKey: .datasetKey),
                matcher: container.decode(RoadMatcherIdentity.self, forKey: .matcher),
                coveragePolicyVersion: container.decode(String.self, forKey: .coveragePolicyVersion)
            )
        } catch RoadExplorationDomainError.invalidMatchRun {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid road match binding.")
            )
        }
    }
}

/// Stable run identity plus every authority input that determines its output.
public struct RoadMatchRunID: Codable, Equatable, Hashable, Sendable {
    public let runUUID: UUID
    public let binding: RoadMatchRunBinding

    public init(runUUID: UUID, binding: RoadMatchRunBinding) {
        self.runUUID = runUUID
        self.binding = binding
    }
}

public struct RoadMatchRun: Codable, Equatable, Sendable {
    public let id: RoadMatchRunID
    public let rideID: UUID
    public let claims: [RoadMatchClaim]

    private enum CodingKeys: String, CodingKey {
        case id
        case rideID
        case claims
    }

    public init(id: RoadMatchRunID, rideID: UUID, claims: [RoadMatchClaim]) throws {
        guard !claims.isEmpty,
              claims.allSatisfy({ claim in
                  claim.segmentID == nil || claim.segmentID?.datasetKey == id.binding.datasetKey
              }) else {
            throw RoadExplorationDomainError.invalidMatchRun
        }
        self.id = id
        self.rideID = rideID
        self.claims = claims.sorted(by: Self.claimPrecedes)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                id: container.decode(RoadMatchRunID.self, forKey: .id),
                rideID: container.decode(UUID.self, forKey: .rideID),
                claims: container.decode([RoadMatchClaim].self, forKey: .claims)
            )
        } catch RoadExplorationDomainError.invalidMatchRun {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid road match run.")
            )
        }
    }

    private static func claimPrecedes(_ lhs: RoadMatchClaim, _ rhs: RoadMatchClaim) -> Bool {
        if lhs.sourcePointRange.firstIndex != rhs.sourcePointRange.firstIndex {
            return lhs.sourcePointRange.firstIndex < rhs.sourcePointRange.firstIndex
        }
        if lhs.sourcePointRange.lastIndex != rhs.sourcePointRange.lastIndex {
            return lhs.sourcePointRange.lastIndex < rhs.sourcePointRange.lastIndex
        }
        if lhs.disposition.rawValue != rhs.disposition.rawValue {
            return lhs.disposition.rawValue < rhs.disposition.rawValue
        }
        let lhsSegment = lhs.segmentID?.canonicalID ?? ""
        let rhsSegment = rhs.segmentID?.canonicalID ?? ""
        if lhsSegment != rhsSegment { return lhsSegment < rhsSegment }
        if lhs.confidence != rhs.confidence { return lhs.confidence < rhs.confidence }
        if lhs.ambiguity.rawValue != rhs.ambiguity.rawValue {
            return lhs.ambiguity.rawValue < rhs.ambiguity.rawValue
        }
        if lhs.directionEvidence.rawValue != rhs.directionEvidence.rawValue {
            return lhs.directionEvidence.rawValue < rhs.directionEvidence.rawValue
        }
        if lhs.rideEvidenceStatus.rawValue != rhs.rideEvidenceStatus.rawValue {
            return lhs.rideEvidenceStatus.rawValue < rhs.rideEvidenceStatus.rawValue
        }
        for (left, right) in zip(lhs.coveredIntervals, rhs.coveredIntervals) {
            if left.lowerBound != right.lowerBound { return left.lowerBound < right.lowerBound }
            if left.upperBound != right.upperBound { return left.upperBound < right.upperBound }
        }
        return lhs.coveredIntervals.count < rhs.coveredIntervals.count
    }
}

// MARK: - Deterministic coverage ledger

public enum RoadMatchRunAcceptance: Equatable, Sendable {
    case inserted
    case replayedNoOp
}

/// Presentation-neutral delta for a newly verified portion of a road.
/// A UI may briefly emphasize this event, but the event itself contains no
/// color, animation duration, haptic, or dashboard-layout instruction.
public struct RoadDiscoveryEvent: Codable, Equatable, Sendable {
    public let matchRunUUID: UUID
    public let rideID: UUID
    public let segmentID: RoadSegmentID
    public let newlyVerifiedIntervals: [RoadCoverageInterval]
    public let newlyVerifiedLengthMeters: Double
}

public struct RoadMatchRunApplication: Equatable, Sendable {
    public let acceptance: RoadMatchRunAcceptance
    public let discoveryEvents: [RoadDiscoveryEvent]
}

public enum RoadCoverageReprocessingReason: String, Codable, Equatable, Hashable, Sendable {
    case datasetChanged
    case matcherChanged
    case policyChanged
}

public struct RoadCoverageReprocessingState: Codable, Equatable, Sendable {
    public let unresolvedOutdatedRunCount: Int
    public let reasons: [RoadCoverageReprocessingReason]

    public var isRequired: Bool {
        unresolvedOutdatedRunCount > 0
    }
}

public struct RoadRejectedMatchCounts: Codable, Equatable, Sendable {
    public let unmatched: Int
    public let uncertain: Int
    public let ambiguous: Int
    public let belowConfidenceThreshold: Int
    public let rideNotIndependentlyVerified: Int
    public let ineligibleOrUnknownSegment: Int
    public let belowMinimumLength: Int

    public var total: Int {
        unmatched
            + uncertain
            + ambiguous
            + belowConfidenceThreshold
            + rideNotIndependentlyVerified
            + ineligibleOrUnknownSegment
            + belowMinimumLength
    }
}

public struct RoadSegmentCoverage: Codable, Equatable, Sendable {
    public let segmentID: RoadSegmentID
    public let coveredIntervals: [RoadCoverageInterval]
    public let verifiedCoveredLengthMeters: Double
    public let contributingRideIDs: [UUID]
}

public enum RoadSegmentExplorationState: String, Codable, Equatable, Sendable {
    case ineligibleOrUnknown
    case eligibleUnexplored
    case partiallyVerified
    case fullyVerified
}

public enum RoadCoverageEvidenceState: String, Codable, Equatable, Sendable {
    case noEvidence
    case verified
    case partial
    case outdated
    case unavailable
}

public enum RoadCoverageUnavailableReason: String, Codable, Equatable, Sendable {
    case licenseReviewPending
    case licenseReviewRejected
    case noEligibleRoads
}

/// Text semantics that remain meaningful without the grey/gold visual encoding.
public struct RoadCoverageAccessibilitySummary: Codable, Equatable, Sendable {
    public let accessibilityLabel: String
    public let accessibilityValue: String
    public let accessibilityHint: String?
}

public struct RoadCoverageAggregate: Codable, Equatable, Sendable {
    public let datasetKey: RoadDatasetKey
    public let matcher: RoadMatcherIdentity
    public let coveragePolicyVersion: String
    public let evidenceState: RoadCoverageEvidenceState
    public let unavailableReason: RoadCoverageUnavailableReason?
    public let verifiedCoveredLengthMeters: Double
    public let eligibleLengthMeters: Double?
    public let progressFraction: Double?
    public let coveredSegmentCount: Int
    public let eligibleSegmentCount: Int
    public let verifiedClaimCount: Int
    public let contributingRideCount: Int
    public let rejectedMatches: RoadRejectedMatchCounts
    public let segmentCoverage: [RoadSegmentCoverage]
    public let reprocessing: RoadCoverageReprocessingState
    public let requiredAttribution: String
    public let accessibilitySummary: RoadCoverageAccessibilitySummary

    /// Allows a spatial adapter to classify only its currently visible road
    /// segments, avoiding a whole-city SwiftUI projection on every map frame.
    public func explorationState(for segment: RoadSegmentDefinition) -> RoadSegmentExplorationState {
        guard segment.id.datasetKey == datasetKey,
              segment.access.disposition == .eligible,
              eligibleLengthMeters != nil else {
            return .ineligibleOrUnknown
        }
        guard let coverage = segmentCoverage.first(where: { $0.segmentID == segment.id }) else {
            return .eligibleUnexplored
        }
        let normalizedLength = coverage.coveredIntervals.reduce(0.0) {
            $0 + $1.normalizedLength
        }
        return normalizedLength >= 1 ? .fullyVerified : .partiallyVerified
    }
}

private struct RideRouteEvidenceKey: Hashable {
    let rideID: UUID
    let digest: RoadRouteDigest
}

private struct MutableRejectedMatchCounts {
    var unmatched = 0
    var uncertain = 0
    var ambiguous = 0
    var belowConfidenceThreshold = 0
    var rideNotIndependentlyVerified = 0
    var ineligibleOrUnknownSegment = 0
    var belowMinimumLength = 0

    var frozen: RoadRejectedMatchCounts {
        RoadRejectedMatchCounts(
            unmatched: unmatched,
            uncertain: uncertain,
            ambiguous: ambiguous,
            belowConfidenceThreshold: belowConfidenceThreshold,
            rideNotIndependentlyVerified: rideNotIndependentlyVerified,
            ineligibleOrUnknownSegment: ineligibleOrUnknownSegment,
            belowMinimumLength: belowMinimumLength
        )
    }
}

public struct RoadCoverageLedger: Sendable {
    public let catalog: RoadNetworkCatalog
    public let policy: RoadCoveragePolicy
    public let currentMatcher: RoadMatcherIdentity

    private var runsByUUID: [UUID: RoadMatchRun]

    public init(
        catalog: RoadNetworkCatalog,
        policy: RoadCoveragePolicy,
        currentMatcher: RoadMatcherIdentity
    ) {
        self.catalog = catalog
        self.policy = policy
        self.currentMatcher = currentMatcher
        self.runsByUUID = [:]
    }

    public var retainedRunCount: Int {
        runsByUUID.count
    }

    /// Accepts exact or semantic replay idempotently and rejects any conflicting
    /// output for the same immutable input binding before mutating the ledger.
    public mutating func accept(_ run: RoadMatchRun) throws -> RoadMatchRunAcceptance {
        if let existing = runsByUUID[run.id.runUUID] {
            guard existing == run else {
                throw RoadExplorationDomainError.matchRunConflict(run.id.runUUID)
            }
            return .replayedNoOp
        }

        if let existing = runsByUUID.values.first(where: {
            $0.rideID == run.rideID && $0.id.binding == run.id.binding
        }) {
            guard existing.claims == run.claims else {
                throw RoadExplorationDomainError.matchRunBindingConflict(
                    existing: existing.id.runUUID,
                    incoming: run.id.runUUID
                )
            }
            return .replayedNoOp
        }

        runsByUUID[run.id.runUUID] = run
        return .inserted
    }

    /// Atomically accepts a match run and derives only the newly verified
    /// canonical intervals. Exact replay cannot emit the discovery twice.
    public mutating func acceptProjectingDiscoveries(
        _ run: RoadMatchRun
    ) throws -> RoadMatchRunApplication {
        let before = try aggregate()
        let acceptance = try accept(run)
        guard acceptance == .inserted else {
            return RoadMatchRunApplication(acceptance: acceptance, discoveryEvents: [])
        }
        let after = try aggregate()
        guard after.evidenceState != .unavailable else {
            return RoadMatchRunApplication(acceptance: acceptance, discoveryEvents: [])
        }

        let beforeBySegment = Dictionary(
            uniqueKeysWithValues: before.segmentCoverage.map { ($0.segmentID, $0) }
        )
        var events: [RoadDiscoveryEvent] = []
        for coverage in after.segmentCoverage {
            let previouslyCovered = beforeBySegment[coverage.segmentID]?.coveredIntervals ?? []
            let newlyVerified = try RoadCoverageInterval.subtracting(
                coverage.coveredIntervals,
                coveredBy: previouslyCovered
            )
            guard !newlyVerified.isEmpty,
                  let segment = catalog.segment(for: coverage.segmentID) else {
                continue
            }
            let length = newlyVerified.reduce(0.0) {
                $0 + ($1.normalizedLength * segment.canonicalLengthMeters)
            }
            guard length.isFinite else {
                throw RoadExplorationDomainError.aggregateOverflow
            }
            events.append(
                RoadDiscoveryEvent(
                    matchRunUUID: run.id.runUUID,
                    rideID: run.rideID,
                    segmentID: coverage.segmentID,
                    newlyVerifiedIntervals: newlyVerified,
                    newlyVerifiedLengthMeters: length
                )
            )
        }
        return RoadMatchRunApplication(
            acceptance: acceptance,
            discoveryEvents: events.sorted { $0.segmentID < $1.segmentID }
        )
    }

    /// Privacy deletion is followed by projection from remaining immutable
    /// runs, so coverage shared with other rides is retained without counters.
    @discardableResult
    public mutating func deleteRide(_ rideID: UUID) -> Int {
        let removedIDs = runsByUUID.values
            .filter { $0.rideID == rideID }
            .map(\.id.runUUID)
        for runID in removedIDs {
            runsByUUID.removeValue(forKey: runID)
        }
        return removedIDs.count
    }

    public func aggregate() throws -> RoadCoverageAggregate {
        let license = catalog.dataset.license
        guard license.authorizesCoverage else {
            let reason: RoadCoverageUnavailableReason = license.reviewState == .rejected
                ? .licenseReviewRejected
                : .licenseReviewPending
            return unavailableAggregate(reason: reason)
        }
        guard catalog.eligibleTraversableLengthMeters > 0 else {
            return unavailableAggregate(reason: .noEligibleRoads)
        }

        let allRuns = runsByUUID.values.sorted { $0.id.runUUID.uuidString < $1.id.runUUID.uuidString }
        let currentRuns = allRuns.filter(isCurrent)
        let currentEvidenceKeys = Set(currentRuns.map {
            RideRouteEvidenceKey(rideID: $0.rideID, digest: $0.id.binding.rawRouteDigest)
        })

        var reprocessingReasons = Set<RoadCoverageReprocessingReason>()
        var outdatedRunCount = 0
        for run in allRuns where !isCurrent(run) {
            let evidenceKey = RideRouteEvidenceKey(
                rideID: run.rideID,
                digest: run.id.binding.rawRouteDigest
            )
            guard !currentEvidenceKeys.contains(evidenceKey) else { continue }
            outdatedRunCount += 1
            if run.id.binding.datasetKey != catalog.dataset.key {
                reprocessingReasons.insert(.datasetChanged)
            }
            if run.id.binding.matcher != currentMatcher {
                reprocessingReasons.insert(.matcherChanged)
            }
            if run.id.binding.coveragePolicyVersion != policy.version {
                reprocessingReasons.insert(.policyChanged)
            }
        }

        var intervalsBySegment: [RoadSegmentID: [RoadCoverageInterval]] = [:]
        var ridesBySegment: [RoadSegmentID: Set<UUID>] = [:]
        var rejected = MutableRejectedMatchCounts()
        var verifiedClaimCount = 0

        for run in currentRuns {
            for claim in run.claims {
                guard claim.disposition != .unmatched else {
                    rejected.unmatched += 1
                    continue
                }
                guard claim.disposition == .matched else {
                    rejected.uncertain += 1
                    continue
                }
                guard claim.ambiguity == .none else {
                    rejected.ambiguous += 1
                    continue
                }
                guard claim.confidence >= policy.minimumAcceptedConfidence else {
                    rejected.belowConfidenceThreshold += 1
                    continue
                }
                guard claim.rideEvidenceStatus == .independentlyVerifiedRiding else {
                    rejected.rideNotIndependentlyVerified += 1
                    continue
                }
                guard let segmentID = claim.segmentID,
                      let segment = catalog.segment(for: segmentID),
                      segment.access.disposition == .eligible else {
                    rejected.ineligibleOrUnknownSegment += 1
                    continue
                }

                let claimLength = claim.coveredIntervals.reduce(0.0) {
                    $0 + ($1.normalizedLength * segment.canonicalLengthMeters)
                }
                guard claimLength.isFinite else {
                    throw RoadExplorationDomainError.aggregateOverflow
                }
                guard claimLength >= policy.minimumVerifiedClaimLengthMeters else {
                    rejected.belowMinimumLength += 1
                    continue
                }

                intervalsBySegment[segmentID, default: []].append(contentsOf: claim.coveredIntervals)
                ridesBySegment[segmentID, default: []].insert(run.rideID)
                verifiedClaimCount += 1
            }
        }

        var segmentCoverage: [RoadSegmentCoverage] = []
        var verifiedLength = 0.0
        var contributingRides = Set<UUID>()
        for segmentID in intervalsBySegment.keys.sorted() {
            guard let segment = catalog.segment(for: segmentID) else { continue }
            let intervals = try RoadCoverageInterval.normalizedUnion(intervalsBySegment[segmentID] ?? [])
            let coveredLength = intervals.reduce(0.0) {
                $0 + ($1.normalizedLength * segment.canonicalLengthMeters)
            }
            verifiedLength += coveredLength
            guard coveredLength.isFinite, verifiedLength.isFinite else {
                throw RoadExplorationDomainError.aggregateOverflow
            }
            let rideIDs = (ridesBySegment[segmentID] ?? []).sorted {
                $0.uuidString < $1.uuidString
            }
            contributingRides.formUnion(rideIDs)
            segmentCoverage.append(
                RoadSegmentCoverage(
                    segmentID: segmentID,
                    coveredIntervals: intervals,
                    verifiedCoveredLengthMeters: coveredLength,
                    contributingRideIDs: rideIDs
                )
            )
        }

        let denominator = catalog.eligibleTraversableLengthMeters
        let progress = min(max(verifiedLength / denominator, 0), 1)
        let frozenRejected = rejected.frozen
        let reprocessing = RoadCoverageReprocessingState(
            unresolvedOutdatedRunCount: outdatedRunCount,
            reasons: reprocessingReasons.sorted { $0.rawValue < $1.rawValue }
        )

        let evidenceState: RoadCoverageEvidenceState
        if reprocessing.isRequired {
            evidenceState = .outdated
        } else if currentRuns.isEmpty {
            evidenceState = .noEvidence
        } else if frozenRejected.total > 0 {
            evidenceState = .partial
        } else {
            evidenceState = .verified
        }

        let summary = Self.accessibilitySummary(
            state: evidenceState,
            unavailableReason: nil,
            coveredMeters: verifiedLength,
            eligibleMeters: denominator,
            progressFraction: progress,
            rejectedCount: frozenRejected.total,
            outdatedRunCount: outdatedRunCount
        )

        return RoadCoverageAggregate(
            datasetKey: catalog.dataset.key,
            matcher: currentMatcher,
            coveragePolicyVersion: policy.version,
            evidenceState: evidenceState,
            unavailableReason: nil,
            verifiedCoveredLengthMeters: verifiedLength,
            eligibleLengthMeters: denominator,
            progressFraction: progress,
            coveredSegmentCount: segmentCoverage.count,
            eligibleSegmentCount: catalog.eligibleSegmentCount,
            verifiedClaimCount: verifiedClaimCount,
            contributingRideCount: contributingRides.count,
            rejectedMatches: frozenRejected,
            segmentCoverage: segmentCoverage,
            reprocessing: reprocessing,
            requiredAttribution: license.attributionText,
            accessibilitySummary: summary
        )
    }

    private func isCurrent(_ run: RoadMatchRun) -> Bool {
        run.id.binding.datasetKey == catalog.dataset.key
            && run.id.binding.matcher == currentMatcher
            && run.id.binding.coveragePolicyVersion == policy.version
    }

    private func unavailableAggregate(reason: RoadCoverageUnavailableReason) -> RoadCoverageAggregate {
        let emptyRejected = MutableRejectedMatchCounts().frozen
        let summary = Self.accessibilitySummary(
            state: .unavailable,
            unavailableReason: reason,
            coveredMeters: 0,
            eligibleMeters: nil,
            progressFraction: nil,
            rejectedCount: 0,
            outdatedRunCount: 0
        )
        return RoadCoverageAggregate(
            datasetKey: catalog.dataset.key,
            matcher: currentMatcher,
            coveragePolicyVersion: policy.version,
            evidenceState: .unavailable,
            unavailableReason: reason,
            verifiedCoveredLengthMeters: 0,
            eligibleLengthMeters: nil,
            progressFraction: nil,
            coveredSegmentCount: 0,
            eligibleSegmentCount: 0,
            verifiedClaimCount: 0,
            contributingRideCount: 0,
            rejectedMatches: emptyRejected,
            segmentCoverage: [],
            reprocessing: RoadCoverageReprocessingState(unresolvedOutdatedRunCount: 0, reasons: []),
            requiredAttribution: catalog.dataset.license.attributionText,
            accessibilitySummary: summary
        )
    }

    private static func accessibilitySummary(
        state: RoadCoverageEvidenceState,
        unavailableReason: RoadCoverageUnavailableReason?,
        coveredMeters: Double,
        eligibleMeters: Double?,
        progressFraction: Double?,
        rejectedCount: Int,
        outdatedRunCount: Int
    ) -> RoadCoverageAccessibilitySummary {
        let label = "Road exploration coverage"
        if state == .unavailable {
            let value: String
            switch unavailableReason {
            case .licenseReviewPending:
                value = "Coverage unavailable. Road data license review is pending."
            case .licenseReviewRejected:
                value = "Coverage unavailable. This road dataset is not authorized."
            case .noEligibleRoads:
                value = "Coverage unavailable. No eligible traversable roads are in this dataset."
            case nil:
                value = "Coverage unavailable."
            }
            return RoadCoverageAccessibilitySummary(
                accessibilityLabel: label,
                accessibilityValue: value,
                accessibilityHint: "Coverage is based on verified route evidence, not map color alone."
            )
        }

        let coveredKilometers = formatKilometers(coveredMeters)
        let eligibleKilometers = formatKilometers(eligibleMeters ?? 0)
        let percent = Int(((progressFraction ?? 0) * 100).rounded())
        var value = "\(coveredKilometers) of \(eligibleKilometers) kilometers verified, \(percent) percent."
        var hint: String?
        switch state {
        case .noEvidence:
            value = "No verified roads yet. " + value
            hint = "Only eligible roads matched from independently verified rides count."
        case .verified:
            hint = "Coverage uses verified road intervals and is not inferred from route previews."
        case .partial:
            value += " \(rejectedCount) route portions are unmatched or unverified."
            hint = "The verified distance is a lower bound; uncertain portions do not count."
        case .outdated:
            value += " \(outdatedRunCount) rides require reprocessing for current road data or policy."
            hint = "Outdated matches do not count until reprocessed."
        case .unavailable:
            break
        }
        return RoadCoverageAccessibilitySummary(
            accessibilityLabel: label,
            accessibilityValue: value,
            accessibilityHint: hint
        )
    }

    private static func formatKilometers(_ meters: Double) -> String {
        String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            meters / 1_000
        )
    }
}
