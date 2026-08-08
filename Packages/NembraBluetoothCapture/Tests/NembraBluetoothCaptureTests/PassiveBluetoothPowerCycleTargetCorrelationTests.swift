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
            epoch: 10,
            candidates: [
                (baselineA, true),
                (baselineB, nil)
            ]
        )
        let poweredOn = try snapshot(
            epoch: 11,
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

        #expect(report.baselineEpoch.rawValue == 10)
        #expect(report.poweredOnEpoch.rawValue == 11)
        #expect(report.baselineObservedIdentifiers == [baselineA, baselineB])
        #expect(report.poweredOnSelectableIdentifiers == [baselineA, baselineB, candidateC])
        #expect(report.newSelectableIdentifiers == [candidateC])
        #expect(report.disposition == .singleNewSelectableCandidate(candidateC))
    }

    @Test("unknown connectability stays selectable instead of being silently discarded")
    func unknownConnectabilityCanRemainCandidate() throws {
        let baseline = try snapshot(epoch: 20, candidates: [(baselineA, true)])
        let poweredOn = try snapshot(
            epoch: 21,
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
        let baseline = try snapshot(epoch: 30, candidates: [(baselineA, true)])
        let poweredOn = try snapshot(
            epoch: 31,
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
            epoch: 40,
            candidates: [
                (baselineA, true),
                (candidateC, false)
            ]
        )
        let poweredOn = try snapshot(
            epoch: 41,
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
        let baseline = try snapshot(epoch: 50, candidates: [(baselineA, true)])
        let poweredOn = try snapshot(
            epoch: 51,
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

    @Test("same or older scan epoch cannot establish an OFF to ON delta")
    func epochOrderMustAdvance() throws {
        let baseline = try snapshot(epoch: 60, candidates: [(baselineA, true)])

        for invalidEpoch in [60, 59] {
            let poweredOn = try snapshot(
                epoch: UInt64(invalidEpoch),
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
            #expect(report.disposition == .invalidScanEpochOrder)
        }
    }

    @Test("duplicate UUIDs in one snapshot are rejected rather than merged by guess")
    func duplicateSnapshotIdentifiersFailClosed() {
        #expect(throws: PassiveBluetoothCandidateScanSnapshotError
            .duplicatePeripheralIdentifier(baselineA)) {
            _ = try snapshot(
                epoch: 70,
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
        let baseline = try snapshot(epoch: 80, candidates: [])
        let poweredOn = try snapshot(
            epoch: 81,
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
            epoch: 90,
            candidates: [
                (baselineA, true),
                (baselineB, true)
            ]
        )
        let poweredOn = try snapshot(epoch: 91, candidates: [(baselineA, true)])

        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            baseline: baseline,
            poweredOn: poweredOn
        )

        #expect(report.newSelectableIdentifiers.isEmpty)
        #expect(report.disposition == .noNewSelectableCandidate)
    }

    private func snapshot(
        epoch: UInt64,
        candidates: [(UUID, Bool?)]
    ) throws -> PassiveBluetoothCandidateScanSnapshot {
        try PassiveBluetoothCandidateScanSnapshot(
            epoch: PassiveBluetoothCandidateScanEpoch(rawValue: epoch),
            candidates: candidates.map {
                .init(id: $0.0, isConnectable: $0.1)
            }
        )
    }
}
