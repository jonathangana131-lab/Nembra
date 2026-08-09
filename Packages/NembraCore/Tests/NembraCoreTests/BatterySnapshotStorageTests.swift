import Foundation
import Testing
@testable import NembraCore

@Suite("Retained battery snapshot storage")
struct BatterySnapshotStorageTests {
    @Test("in-memory storage preserves value, authority, and chronology")
    func inMemoryRoundTripPreservesTruth() throws {
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let retainedAt = observedAt.addingTimeInterval(12)
        let snapshot = try #require(
            RetainedBatterySnapshot(
                percent: 63,
                authority: .estimated,
                observedAt: observedAt,
                retainedAt: retainedAt
            )
        )
        let storage = InMemoryRetainedBatterySnapshotStorage()

        try storage.save(snapshot)
        let loaded = try storage.load()

        #expect(loaded == snapshot)
        #expect(loaded?.authority == .estimated)
        #expect(loaded?.observedAt == observedAt)
        #expect(loaded?.retainedAt == retainedAt)
    }

    @Test("clear removes retained evidence")
    func clearRemovesSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let snapshot = try #require(
            RetainedBatterySnapshot(
                percent: 41,
                authority: .displayOnly,
                observedAt: now,
                retainedAt: now
            )
        )
        let storage = InMemoryRetainedBatterySnapshotStorage(snapshot: snapshot)

        try storage.clear()

        #expect(try storage.load() == nil)
    }

    @Test("UserDefaults storage round-trips exact validated payload")
    func userDefaultsRoundTrip() throws {
        let suiteName = "BatterySnapshotStorageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let observedAt = Date(timeIntervalSince1970: 1_700_001_000)
        let retainedAt = observedAt.addingTimeInterval(3)
        let snapshot = try #require(
            RetainedBatterySnapshot(
                percent: 88,
                authority: .measured,
                observedAt: observedAt,
                retainedAt: retainedAt
            )
        )
        let storage = UserDefaultsRetainedBatterySnapshotStorage(defaults: defaults)

        try storage.save(snapshot)
        let loaded = try storage.load()

        #expect(loaded == snapshot)
        #expect(loaded?.authority == .measured)
    }

    @Test("corrupt retained bytes fail closed")
    func corruptPayloadThrows() throws {
        let suiteName = "BatterySnapshotStorageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: UserDefaultsRetainedBatterySnapshotStorage.defaultKey)
        let storage = UserDefaultsRetainedBatterySnapshotStorage(defaults: defaults)

        #expect(throws: (any Error).self) {
            _ = try storage.load()
        }
    }
}
