import Foundation
import Testing
@testable import NembraCore

@Suite("Retained battery persistence")
struct BatteryPersistenceTests {
    @Test("round trip preserves authority instead of promoting retained data")
    func roundTripPreservesAuthority() throws {
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let retainedAt = observedAt.addingTimeInterval(12)
        let snapshot = try #require(RetainedBatterySnapshot(
            percent: 73,
            authority: .displayOnly,
            observedAt: observedAt,
            retainedAt: retainedAt
        ))

        let data = try RetainedBatterySnapshotCodec.encode(snapshot)
        let decoded = try RetainedBatterySnapshotCodec.decode(data)

        #expect(decoded == snapshot)
        #expect(decoded.authority == .displayOnly)
        #expect(decoded.percent == 73)
    }

    @Test("estimated battery remains estimated after persistence")
    func estimatedAuthoritySurvivesPersistence() throws {
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = try #require(RetainedBatterySnapshot(
            percent: 61,
            authority: .estimated,
            observedAt: observedAt,
            retainedAt: observedAt
        ))

        let decoded = try RetainedBatterySnapshotCodec.decode(
            RetainedBatterySnapshotCodec.encode(snapshot)
        )

        #expect(decoded.authority == .estimated)
    }

    @Test("restoring a retained snapshot preserves original observation truth")
    func restorePreservesObservationTruth() throws {
        let observedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let retainedAt = observedAt.addingTimeInterval(900)
        let snapshot = try #require(RetainedBatterySnapshot(
            percent: 58,
            authority: .estimated,
            observedAt: observedAt,
            retainedAt: retainedAt
        ))

        let restored = try #require(snapshot.authoritativeObservation)

        #expect(restored.percent == 58)
        #expect(restored.authority == .estimated)
        #expect(restored.observedAt == observedAt)
        #expect(restored.observedAt != retainedAt)
        #expect(restored.physicalMeasurement == nil)
        #expect(restored.rangeEligible(currentness: .retained) == nil)
    }

    @Test("invalid percentage and chronology fail closed")
    func invalidInputsFailClosed() {
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(RetainedBatterySnapshot(
            percent: -1,
            authority: .displayOnly,
            observedAt: observedAt,
            retainedAt: observedAt
        ) == nil)
        #expect(RetainedBatterySnapshot(
            percent: 101,
            authority: .displayOnly,
            observedAt: observedAt,
            retainedAt: observedAt
        ) == nil)
        #expect(RetainedBatterySnapshot(
            percent: 50,
            authority: .displayOnly,
            observedAt: observedAt,
            retainedAt: observedAt.addingTimeInterval(-1)
        ) == nil)
    }

    @Test("age is chronology only and does not mutate authority")
    func ageDoesNotChangeAuthority() throws {
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = try #require(RetainedBatterySnapshot(
            percent: 48,
            authority: .measured,
            observedAt: observedAt,
            retainedAt: observedAt
        ))

        #expect(snapshot.age(at: observedAt.addingTimeInterval(90)) == 90)
        #expect(snapshot.age(at: observedAt.addingTimeInterval(-1)) == nil)
        #expect(snapshot.authority == .measured)
    }

    @Test("decoder rejects unsupported schema")
    func rejectsUnsupportedSchema() throws {
        let json = """
        {
          "schemaVersion": 999,
          "percent": 50,
          "authority": "displayOnly",
          "observedAt": -978307200,
          "retainedAt": -978307200
        }
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try RetainedBatterySnapshotCodec.decode(json)
        }
    }
}
