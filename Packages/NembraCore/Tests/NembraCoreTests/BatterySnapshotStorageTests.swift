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

    @Test("re-saving unchanged evidence cannot refresh observation chronology")
    func unchangedEvidenceDoesNotBecomeNewer() throws {
        let suiteName = "BatterySnapshotStorageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storage = UserDefaultsRetainedBatterySnapshotStorage(defaults: defaults)

        let firstObservedAt = Date(timeIntervalSince1970: 1_700_002_000)
        let first = try #require(
            RetainedBatterySnapshot(
                percent: 72,
                authority: .measured,
                observedAt: firstObservedAt,
                retainedAt: firstObservedAt.addingTimeInterval(1)
            )
        )
        let repeated = try #require(
            RetainedBatterySnapshot(
                percent: 72,
                authority: .measured,
                observedAt: firstObservedAt.addingTimeInterval(120),
                retainedAt: firstObservedAt.addingTimeInterval(121)
            )
        )

        try storage.save(first)
        try storage.save(repeated)

        #expect(try storage.load() == first)
    }

    @Test("older delayed evidence cannot roll retained battery backward")
    func olderEvidenceCannotOverwriteNewerSnapshot() throws {
        let suiteName = "BatterySnapshotStorageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storage = UserDefaultsRetainedBatterySnapshotStorage(defaults: defaults)

        let newerObservedAt = Date(timeIntervalSince1970: 1_700_003_000)
        let newer = try #require(
            RetainedBatterySnapshot(
                percent: 54,
                authority: .measured,
                observedAt: newerObservedAt,
                retainedAt: newerObservedAt
            )
        )
        let delayedOlder = try #require(
            RetainedBatterySnapshot(
                percent: 61,
                authority: .estimated,
                observedAt: newerObservedAt.addingTimeInterval(-30),
                retainedAt: newerObservedAt.addingTimeInterval(-20)
            )
        )

        try storage.save(newer)
        try storage.save(delayedOlder)

        #expect(try storage.load() == newer)
    }

    @Test("newer materially different evidence replaces retained snapshot")
    func newerDifferentEvidenceAdvancesSnapshot() throws {
        let suiteName = "BatterySnapshotStorageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storage = UserDefaultsRetainedBatterySnapshotStorage(defaults: defaults)

        let firstObservedAt = Date(timeIntervalSince1970: 1_700_004_000)
        let first = try #require(
            RetainedBatterySnapshot(
                percent: 80,
                authority: .estimated,
                observedAt: firstObservedAt,
                retainedAt: firstObservedAt
            )
        )
        let newer = try #require(
            RetainedBatterySnapshot(
                percent: 79,
                authority: .measured,
                observedAt: firstObservedAt.addingTimeInterval(10),
                retainedAt: firstObservedAt.addingTimeInterval(11)
            )
        )

        try storage.save(first)
        try storage.save(newer)

        #expect(try storage.load() == newer)
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
