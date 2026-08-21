import Foundation
import Testing
@testable import NembraCore

@Suite("Navigation recent destinations persistence")
struct NavigationRecentDestinationsTests {
    @Test("Legacy raw arrays migrate to the canonical versioned archive")
    func legacyArrayMigrates() throws {
        let legacy = """
        [{"id":"legacy-id","name":"  Waterfront Park  ","address":"  100 Main St  ","latitude":45.62,"longitude":-122.67}]
        """

        let loaded = NavigationRecentDestinationsPersistence.load(json: legacy)

        #expect(loaded.requiresRewrite)
        #expect(loaded.destinations.count == 1)
        #expect(loaded.destinations[0].name == "Waterfront Park")
        #expect(loaded.destinations[0].address == "100 Main St")
        #expect(loaded.canonicalJSON.contains("\"schemaVersion\":1"))

        let canonical = NavigationRecentDestinationsPersistence.load(json: loaded.canonicalJSON)
        #expect(!canonical.requiresRewrite)
        #expect(canonical.destinations == loaded.destinations)
    }

    @Test("Corrupt oversized and unknown-version archives fail closed")
    func invalidArchivesFailClosed() {
        let malformed = NavigationRecentDestinationsPersistence.load(json: "{not-json")
        #expect(malformed.destinations.isEmpty)
        #expect(malformed.canonicalJSON.isEmpty)
        #expect(malformed.requiresRewrite)

        let oversized = NavigationRecentDestinationsPersistence.load(
            json: String(
                repeating: "x",
                count: NavigationRecentDestinationsPersistence.maximumEncodedBytes + 1
            )
        )
        #expect(oversized.destinations.isEmpty)
        #expect(oversized.canonicalJSON.isEmpty)
        #expect(oversized.requiresRewrite)

        let future = NavigationRecentDestinationsPersistence.load(
            json: "{\"schemaVersion\":2,\"destinations\":[]}"
        )
        #expect(future.destinations.isEmpty)
        #expect(future.canonicalJSON.isEmpty)
        #expect(future.requiresRewrite)
    }

    @Test("Load validates fields and drops invalid records without losing valid history")
    func invalidRecordsAreDropped() throws {
        let legacy = """
        [
          {"name":"  Valid place  ","address":"   ","latitude":45.5,"longitude":-122.6},
          {"name":"Impossible latitude","address":null,"latitude":95,"longitude":-122.6},
          {"name":"   ","address":null,"latitude":45.6,"longitude":-122.7}
        ]
        """

        let loaded = NavigationRecentDestinationsPersistence.load(json: legacy)

        #expect(loaded.destinations.count == 1)
        #expect(loaded.destinations[0].name == "Valid place")
        #expect(loaded.destinations[0].address == nil)
        #expect(loaded.requiresRewrite)
    }

    @Test("Canonical history is deduplicated and bounded to six destinations")
    func historyIsDeduplicatedAndBounded() throws {
        var records: [NavigationRecentDestinationRecord] = []
        for index in 0..<8 {
            let record = try #require(
                NavigationRecentDestinationRecord(
                    name: "Place \(index)",
                    address: nil,
                    latitude: 45.0 + Double(index) / 100,
                    longitude: -122.0
                )
            )
            records.append(record)
        }

        records.insert(records[0], at: 1)
        let encoded = NavigationRecentDestinationsPersistence.encode(records)
        let loaded = NavigationRecentDestinationsPersistence.load(json: encoded)

        #expect(loaded.destinations.count == NavigationRecentDestinationsPersistence.maximumDestinationCount)
        #expect(Set(loaded.destinations.map(\.id)).count == loaded.destinations.count)
        #expect(loaded.destinations.first?.name == "Place 0")
        #expect(!loaded.requiresRewrite)
    }

    @Test("Promotion moves an existing coordinate to the front without duplicating it")
    func promotionIsStable() throws {
        let first = try #require(
            NavigationRecentDestinationRecord(
                name: "First",
                address: nil,
                latitude: 45.60,
                longitude: -122.60
            )
        )
        let second = try #require(
            NavigationRecentDestinationRecord(
                name: "Second",
                address: "Old address",
                latitude: 45.61,
                longitude: -122.61
            )
        )
        let refreshedSecond = try #require(
            NavigationRecentDestinationRecord(
                name: "Second updated",
                address: "New address",
                latitude: 45.61,
                longitude: -122.61
            )
        )

        let promoted = NavigationRecentDestinationsPersistence.promoting(
            refreshedSecond,
            in: [first, second]
        )

        #expect(promoted.count == 2)
        #expect(promoted[0] == refreshedSecond)
        #expect(promoted[1] == first)
    }

    @Test("Empty history has one stable empty representation")
    func emptyHistoryIsStable() {
        let loaded = NavigationRecentDestinationsPersistence.load(json: "")
        #expect(loaded.destinations.isEmpty)
        #expect(loaded.canonicalJSON.isEmpty)
        #expect(!loaded.requiresRewrite)
        #expect(NavigationRecentDestinationsPersistence.encode([]).isEmpty)
    }
}
