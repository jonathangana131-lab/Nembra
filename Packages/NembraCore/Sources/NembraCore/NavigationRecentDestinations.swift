import Foundation

/// A locally persisted destination selected from the navigation provider.
///
/// This is provider/location history only. It never carries scooter telemetry,
/// route-measurement evidence, or physical vehicle authority.
public struct NavigationRecentDestinationRecord: Identifiable, Equatable, Sendable {
    public static let maximumNameLength = 160
    public static let maximumAddressLength = 512

    public let name: String
    public let address: String?
    public let latitude: Double
    public let longitude: Double

    public var id: String {
        let latitudeKey = Int64((latitude * 100_000).rounded())
        let longitudeKey = Int64((longitude * 100_000).rounded())
        return "\(latitudeKey):\(longitudeKey)"
    }

    public init?(
        name: String,
        address: String?,
        latitude: Double,
        longitude: Double
    ) {
        guard latitude.isFinite,
              longitude.isFinite,
              (-90.0...90.0).contains(latitude),
              (-180.0...180.0).contains(longitude) else {
            return nil
        }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty,
              normalizedName.count <= Self.maximumNameLength else {
            return nil
        }

        let normalizedAddress: String?
        if let address {
            let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count <= Self.maximumAddressLength else { return nil }
            normalizedAddress = trimmed.isEmpty ? nil : trimmed
        } else {
            normalizedAddress = nil
        }

        self.name = normalizedName
        self.address = normalizedAddress
        self.latitude = latitude == 0 ? 0 : latitude
        self.longitude = longitude == 0 ? 0 : longitude
    }
}

public struct NavigationRecentDestinationsLoad: Equatable, Sendable {
    public let destinations: [NavigationRecentDestinationRecord]
    public let canonicalJSON: String
    public let requiresRewrite: Bool

    public init(
        destinations: [NavigationRecentDestinationRecord],
        canonicalJSON: String,
        requiresRewrite: Bool
    ) {
        self.destinations = destinations
        self.canonicalJSON = canonicalJSON
        self.requiresRewrite = requiresRewrite
    }
}

/// Versioned, bounded persistence for Navigation's on-device recent places.
///
/// The first shipped Navigation surface stored a raw JSON array in AppStorage.
/// `load(json:)` intentionally accepts that legacy shape, sanitizes it, and emits
/// one canonical versioned representation so installed users migrate in place.
/// Corrupt, oversized, or unknown-version input fails closed to an empty history.
public enum NavigationRecentDestinationsPersistence {
    public static let schemaVersion = 1
    public static let maximumDestinationCount = 6
    public static let maximumEncodedBytes = 32 * 1_024

    public static func load(json: String) -> NavigationRecentDestinationsLoad {
        guard !json.isEmpty else {
            return NavigationRecentDestinationsLoad(
                destinations: [],
                canonicalJSON: "",
                requiresRewrite: false
            )
        }

        guard json.utf8.count <= maximumEncodedBytes,
              let data = json.data(using: .utf8) else {
            return invalidLoad()
        }

        let decoder = JSONDecoder()
        let payloads: [Payload]

        if let archive = try? decoder.decode(Archive.self, from: data) {
            guard archive.schemaVersion == schemaVersion else {
                return invalidLoad()
            }
            payloads = archive.destinations
        } else if let legacy = try? decoder.decode([Payload].self, from: data) {
            payloads = legacy
        } else {
            return invalidLoad()
        }

        let normalized = normalize(
            payloads.compactMap { payload in
                NavigationRecentDestinationRecord(
                    name: payload.name,
                    address: payload.address,
                    latitude: payload.latitude,
                    longitude: payload.longitude
                )
            }
        )
        let canonicalJSON = encode(normalized)

        return NavigationRecentDestinationsLoad(
            destinations: normalized,
            canonicalJSON: canonicalJSON,
            requiresRewrite: canonicalJSON != json
        )
    }

    public static func encode(_ destinations: [NavigationRecentDestinationRecord]) -> String {
        let normalized = normalize(destinations)
        guard !normalized.isEmpty else { return "" }

        let archive = Archive(
            schemaVersion: schemaVersion,
            destinations: normalized.map(Payload.init)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let data = try? encoder.encode(archive),
              data.count <= maximumEncodedBytes,
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }

    public static func promoting(
        _ destination: NavigationRecentDestinationRecord,
        in existing: [NavigationRecentDestinationRecord]
    ) -> [NavigationRecentDestinationRecord] {
        var result = existing.filter { $0.id != destination.id }
        result.insert(destination, at: 0)
        return normalize(result)
    }

    private static func normalize(
        _ destinations: [NavigationRecentDestinationRecord]
    ) -> [NavigationRecentDestinationRecord] {
        var seen = Set<String>()
        var result: [NavigationRecentDestinationRecord] = []
        result.reserveCapacity(min(destinations.count, maximumDestinationCount))

        for destination in destinations {
            guard seen.insert(destination.id).inserted else { continue }
            result.append(destination)
            if result.count == maximumDestinationCount { break }
        }
        return result
    }

    private static func invalidLoad() -> NavigationRecentDestinationsLoad {
        NavigationRecentDestinationsLoad(
            destinations: [],
            canonicalJSON: "",
            requiresRewrite: true
        )
    }

    private struct Archive: Codable {
        let schemaVersion: Int
        let destinations: [Payload]
    }

    /// Deliberately omits the old persisted `id`. JSONDecoder ignores that legacy
    /// key and identity is recomputed from validated coordinates on every load.
    private struct Payload: Codable {
        let name: String
        let address: String?
        let latitude: Double
        let longitude: Double

        init(_ destination: NavigationRecentDestinationRecord) {
            name = destination.name
            address = destination.address
            latitude = destination.latitude
            longitude = destination.longitude
        }
    }
}
