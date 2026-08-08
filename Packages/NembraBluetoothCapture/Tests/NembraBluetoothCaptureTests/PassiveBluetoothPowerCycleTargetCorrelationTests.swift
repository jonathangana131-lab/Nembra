import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth power-cycle target correlation")
struct PassiveBluetoothPowerCycleTargetCorrelationTests {
    private let baselineA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private let baselineB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!
    private let candidateC = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000003")!
    private let candidateD = UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000004")!

    @Test("exactly one newly selectable full UUID becomes an operator-selection candidate")
    func singleCandidate() throws {
        let baseline = try snapshot(
            sequence: 10,
            candidates: [
                (baselineA, true),
                (baselineB, nil)
            ]
        )
        let poweredOn = try snapshot(
            sequence: 11,
            candidates: [
                (baselineA, true),
                (baselineB, nil),
                (candidateC, true)
            ]
        )

        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            baseline: baseline,
            poweredOn: poweredOn
        )

        #expect(report.baselineWindowSequence.rawValue == 10)
        #expect(report.poweredOnWindowSequence.rawValue == 11)
        #expect(report.baselineObservedIdentifiers == [baselineA, baselineB])
        #expect(report.poweredOnSelectableIdentifiers == [baselineA, baselineB, candidateC])
        #expect(report.newSelectableIdentifiers == [candidateC])
        #expect(report.disposition == .singleNewSelectableCandidate(candidateC))
    }

    @Test("unknown connectability stays selectable instead of being silently discarded")
    func unknownConnectabilityCanRemainCandidate() throws {
        let baseline = try snapshot(sequence: 20, candidates: [(baselineA, true)])
        let poweredOn = try snapshot(
            sequence: 21,
            candidates: [
                (baselineA, true),
                (candidateC, nil)
            ]
        )

        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            baseline: baseline,
            poweredOn: poweredOn
        )

        #expect(report.newSelectableIdentifiers == [candidateC])
        #expect(report.disposition == .singleNewSelectableCandidate(candidateC))
    }

    @Test("explicitly non-connectable arrivals cannot become target candidates")
    func nonConnectableArrivalIsIgnored() throws {
        let baseline = try snapshot(sequence: 30, candidates: [(baselineA, true)])
        let poweredOn = try snapshot(
            sequence: 31,
            candidates: [
                (baselineA, true),
                (candidateC, false)
            ]
        )

        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            baseline: baseline,
            poweredOn: poweredOn
        )

        #expect(report.poweredOnSelectableIdentifiers == [baselineA])
        #expect(report.newSelectableIdentifiers.isEmpty)
        #expect(report.disposition == .noNewSelectableCandidate)
    }

    @Test("a peripheral seen while target is OFF never becomes new only because connectability changed")
    func baselinePresenceOutranksConnectabilityChange() throws {
        let baseline = try snapshot(
            sequence: 40,
            candidates: [
                (baselineA, true),
                (candidateC, false)
            ]
        )
        let poweredOn = try snapshot(
            sequence: 41,
            candidates: [
                (baselineA, true),
                (candidateC, true)
            ]
        )

        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            baseline: baseline,
            poweredOn: poweredOn
        )

        #expect(report.baselineObservedIdentifiers.contains(candidateC))
        #expect(report.poweredOnSelectableIdentifiers.contains(candidateC))
        #expect(report.newSelectableIdentifiers.isEmpty)
        #expect(report.disposition == .noNewSelectableCandidate)
    }

    @Test("multiple new selectable UUIDs fail closed as ambiguous")
    func multipleCandidatesAreAmbiguous() throws {
        let baseline = try snapshot(sequence: 50, candidates: [(baselineA, true)])
        let poweredOn = try snapshot(
            sequence: 51,
            candidates: [
                (baselineA, true),
                (candidateD, true),
                (candidateC, nil)
            ]
        )

        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            baseline: baseline,
            poweredOn: poweredOn
        )

        #expect(report.newSelectableIdentifiers == [candidateC, candidateD])
        #expect(report.disposition == .ambiguousNewSelectableCandidates([candidateC, candidateD]))
    }

    @Test("same or older local window sequence cannot establish an OFF to ON delta")
    func localWindowOrderMustAdvance() throws {
        let baseline = try snapshot(sequence: 60, candidates: [(baselineA, true)])

        for invalidSequence in [60, 59] {
            let poweredOn = try snapshot(
                sequence: UInt64(invalidSequence),
                candidates: [
                    (baselineA, true),
                    (candidateC, true)
                ]
            )
            let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
                baseline: baseline,
                poweredOn: poweredOn
            )

            #expect(report.newSelectableIdentifiers.isEmpty)
            #expect(report.disposition == .invalidObservationWindowOrder)
        }
    }

    @Test("duplicate UUIDs in one snapshot are rejected rather than merged by guess")
    func duplicateSnapshotIdentifiersFailClosed() {
        #expect(throws: PassiveBluetoothCandidateObservationSnapshotError
            .duplicatePeripheralIdentifier(baselineA)) {
            _ = try snapshot(
                sequence: 70,
                candidates: [
                    (baselineA, false),
                    (baselineA, true)
                ]
            )
        }
    }

    @Test("full UUIDs remain distinct even when a shortened UI prefix would collide")
    func shortenedIdentifierCollisionDoesNotCollapseCandidates() throws {
        let first = UUID(uuidString: "12345678-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "12345678-0000-0000-0000-000000000002")!
        let baseline = try snapshot(sequence: 80, candidates: [])
        let poweredOn = try snapshot(
            sequence: 81,
            candidates: [
                (first, true),
                (second, true)
            ]
        )

        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            baseline: baseline,
            poweredOn: poweredOn
        )

        #expect(report.newSelectableIdentifiers == [first, second])
        #expect(report.disposition == .ambiguousNewSelectableCandidates([first, second]))
    }

    @Test("powered-on disappearance or unchanged catalog cannot manufacture a candidate")
    func unchangedOrSmallerCatalogProducesNoCandidate() throws {
        let baseline = try snapshot(
            sequence: 90,
            candidates: [
                (baselineA, true),
                (baselineB, true)
            ]
        )
        let poweredOn = try snapshot(sequence: 91, candidates: [(baselineA, true)])

        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            baseline: baseline,
            poweredOn: poweredOn
        )

        #expect(report.newSelectableIdentifiers.isEmpty)
        #expect(report.disposition == .noNewSelectableCandidate)
    }

    private func snapshot(
        sequence: UInt64,
        candidates: [(UUID, Bool?)]
    ) throws -> PassiveBluetoothCandidateObservationSnapshot {
        try PassiveBluetoothCandidateObservationSnapshot(
            windowSequence: PassiveBluetoothCandidateObservationWindowSequence(rawValue: sequence),
            candidates: candidates.map {
                .init(id: $0.0, isConnectable: $0.1)
            }
        )
    }
}
