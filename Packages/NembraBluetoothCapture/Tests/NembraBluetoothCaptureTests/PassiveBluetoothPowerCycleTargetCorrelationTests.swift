import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth power-cycle target correlation")
struct PassiveBluetoothPowerCycleTargetCorrelationTests {
    private let neighborA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private let neighborB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!
    private let candidateC = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000003")!
    private let candidateD = UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000004")!
    private let defaultSeries = PassiveBluetoothCandidateObservationSeriesIdentity(
        rawValue: UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000001")!
    )
    private let foreignSeries = PassiveBluetoothCandidateObservationSeriesIdentity(
        rawValue: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000002")!
    )

    @Test("same full UUID repeating OFF ON pattern twice becomes operator-selection candidate")
    func repeatedCandidate() throws {
        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: try snapshot(sequence: 10, candidates: [(neighborA, true)]),
            firstOn: try snapshot(sequence: 11, candidates: [(neighborA, true), (candidateC, true)]),
            secondOff: try snapshot(sequence: 12, candidates: [(neighborA, true)]),
            secondOn: try snapshot(sequence: 13, candidates: [(neighborA, true), (candidateC, true)])
        )

        #expect(report.observationSeriesIdentities == Array(repeating: defaultSeries, count: 4))
        #expect(report.firstOffWindowSequence.rawValue == 10)
        #expect(report.firstOnWindowSequence.rawValue == 11)
        #expect(report.secondOffWindowSequence.rawValue == 12)
        #expect(report.secondOnWindowSequence.rawValue == 13)
        #expect(report.firstCycleNewSelectableIdentifiers == [candidateC])
        #expect(report.secondCycleNewSelectableIdentifiers == [candidateC])
        #expect(report.repeatableCandidateIdentifiers == [candidateC])
        #expect(report.disposition == .singleRepeatableCandidate(candidateC))
    }

    @Test("snapshots from different producer lifetimes fail before chronology or candidate math")
    func mixedObservationAuthorityFailsClosed() throws {
        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: try snapshot(sequence: 20, candidates: []),
            firstOn: try snapshot(sequence: 21, candidates: [(candidateC, true)]),
            secondOff: try snapshot(series: foreignSeries, sequence: 22, candidates: []),
            secondOn: try snapshot(series: foreignSeries, sequence: 23, candidates: [(candidateC, true)])
        )

        #expect(report.observationSeriesIdentities == [
            defaultSeries,
            defaultSeries,
            foreignSeries,
            foreignSeries
        ])
        #expect(report.firstOffObservedIdentifiers.isEmpty)
        #expect(report.secondOffObservedIdentifiers.isEmpty)
        #expect(report.firstOnSelectableIdentifiers.isEmpty)
        #expect(report.secondOnSelectableIdentifiers.isEmpty)
        #expect(report.firstCycleNewSelectableIdentifiers.isEmpty)
        #expect(report.secondCycleNewSelectableIdentifiers.isEmpty)
        #expect(report.repeatableCandidateIdentifiers.isEmpty)
        #expect(report.disposition == .invalidObservationAuthority)
    }

    @Test("one foreign middle window invalidates an otherwise repeatable candidate")
    func oneForeignWindowInvalidatesExperiment() throws {
        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: try snapshot(sequence: 30, candidates: []),
            firstOn: try snapshot(series: foreignSeries, sequence: 31, candidates: [(candidateC, true)]),
            secondOff: try snapshot(sequence: 32, candidates: []),
            secondOn: try snapshot(sequence: 33, candidates: [(candidateC, true)])
        )

        #expect(report.disposition == .invalidObservationAuthority)
        #expect(report.repeatableCandidateIdentifiers.isEmpty)
    }

    @Test("one-off arrival in only first ON window cannot establish correlation")
    func oneOffArrivalFailsClosed() throws {
        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: try snapshot(sequence: 40, candidates: [(neighborA, true)]),
            firstOn: try snapshot(sequence: 41, candidates: [(neighborA, true), (candidateC, true)]),
            secondOff: try snapshot(sequence: 42, candidates: [(neighborA, true)]),
            secondOn: try snapshot(sequence: 43, candidates: [(neighborA, true)])
        )

        #expect(report.firstCycleNewSelectableIdentifiers == [candidateC])
        #expect(report.secondCycleNewSelectableIdentifiers.isEmpty)
        #expect(report.repeatableCandidateIdentifiers.isEmpty)
        #expect(report.disposition == .noRepeatableCandidate)
    }

    @Test("candidate present in second OFF catalog cannot pass even if selectable in both ON windows")
    func secondOffPresenceBreaksPattern() throws {
        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: try snapshot(sequence: 50, candidates: [(neighborA, true)]),
            firstOn: try snapshot(sequence: 51, candidates: [(neighborA, true), (candidateC, true)]),
            secondOff: try snapshot(sequence: 52, candidates: [(neighborA, true), (candidateC, false)]),
            secondOn: try snapshot(sequence: 53, candidates: [(neighborA, true), (candidateC, true)])
        )

        #expect(report.firstCycleNewSelectableIdentifiers == [candidateC])
        #expect(report.secondOffObservedIdentifiers.contains(candidateC))
        #expect(report.secondCycleNewSelectableIdentifiers.isEmpty)
        #expect(report.repeatableCandidateIdentifiers.isEmpty)
        #expect(report.disposition == .noRepeatableCandidate)
    }

    @Test("stable neighbor cannot outrank one repeated OFF ON correlated candidate")
    func stableNeighborDoesNotCompete() throws {
        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: try snapshot(sequence: 60, candidates: [(neighborA, nil)]),
            firstOn: try snapshot(sequence: 61, candidates: [(neighborA, true), (candidateC, nil)]),
            secondOff: try snapshot(sequence: 62, candidates: [(neighborA, true)]),
            secondOn: try snapshot(sequence: 63, candidates: [(neighborA, true), (candidateC, true)])
        )

        #expect(report.repeatableCandidateIdentifiers == [candidateC])
        #expect(report.disposition == .singleRepeatableCandidate(candidateC))
    }

    @Test("two UUIDs repeating the full pattern remain ambiguous")
    func repeatedCandidatesRemainAmbiguous() throws {
        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: try snapshot(sequence: 70, candidates: [(neighborA, true)]),
            firstOn: try snapshot(
                sequence: 71,
                candidates: [(neighborA, true), (candidateD, true), (candidateC, nil)]
            ),
            secondOff: try snapshot(sequence: 72, candidates: [(neighborA, true)]),
            secondOn: try snapshot(
                sequence: 73,
                candidates: [(neighborA, true), (candidateC, true), (candidateD, nil)]
            )
        )

        #expect(report.repeatableCandidateIdentifiers == [candidateC, candidateD])
        #expect(report.disposition == .ambiguousRepeatableCandidates([candidateC, candidateD]))
    }

    @Test("different UUID in each ON window never gets guessed or merged")
    func identifierChangeCannotBeMerged() throws {
        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: try snapshot(sequence: 80, candidates: [(neighborA, true)]),
            firstOn: try snapshot(sequence: 81, candidates: [(neighborA, true), (candidateC, true)]),
            secondOff: try snapshot(sequence: 82, candidates: [(neighborA, true)]),
            secondOn: try snapshot(sequence: 83, candidates: [(neighborA, true), (candidateD, true)])
        )

        #expect(report.firstCycleNewSelectableIdentifiers == [candidateC])
        #expect(report.secondCycleNewSelectableIdentifiers == [candidateD])
        #expect(report.repeatableCandidateIdentifiers.isEmpty)
        #expect(report.disposition == .noRepeatableCandidate)
    }

    @Test("non-increasing local chronology anywhere in four-window chain fails closed")
    func localWindowChronologyMustStrictlyIncrease() throws {
        let invalidSequences: [(UInt64, UInt64, UInt64, UInt64)] = [
            (90, 90, 91, 92),
            (90, 92, 91, 93),
            (90, 91, 93, 92)
        ]

        for sequences in invalidSequences {
            let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
                firstOff: try snapshot(sequence: sequences.0, candidates: []),
                firstOn: try snapshot(sequence: sequences.1, candidates: [(candidateC, true)]),
                secondOff: try snapshot(sequence: sequences.2, candidates: []),
                secondOn: try snapshot(sequence: sequences.3, candidates: [(candidateC, true)])
            )

            #expect(report.firstCycleNewSelectableIdentifiers.isEmpty)
            #expect(report.secondCycleNewSelectableIdentifiers.isEmpty)
            #expect(report.repeatableCandidateIdentifiers.isEmpty)
            #expect(report.disposition == .invalidObservationWindowOrder)
        }
    }

    @Test("authority mismatch outranks locally invalid chronology")
    func authorityMismatchPrecedesChronology() throws {
        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: try snapshot(sequence: 100, candidates: []),
            firstOn: try snapshot(sequence: 101, candidates: [(candidateC, true)]),
            secondOff: try snapshot(series: foreignSeries, sequence: 99, candidates: []),
            secondOn: try snapshot(series: foreignSeries, sequence: 102, candidates: [(candidateC, true)])
        )

        #expect(report.disposition == .invalidObservationAuthority)
        #expect(report.repeatableCandidateIdentifiers.isEmpty)
    }

    @Test("unknown connectability can remain selectable but explicit false cannot complete repetition")
    func connectabilityPolicyRemainsConservative() throws {
        let unknownAllowed = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: try snapshot(sequence: 110, candidates: []),
            firstOn: try snapshot(sequence: 111, candidates: [(candidateC, nil)]),
            secondOff: try snapshot(sequence: 112, candidates: []),
            secondOn: try snapshot(sequence: 113, candidates: [(candidateC, nil)])
        )
        #expect(unknownAllowed.disposition == .singleRepeatableCandidate(candidateC))

        let explicitFalseBreaks = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: try snapshot(sequence: 114, candidates: []),
            firstOn: try snapshot(sequence: 115, candidates: [(candidateC, true)]),
            secondOff: try snapshot(sequence: 116, candidates: []),
            secondOn: try snapshot(sequence: 117, candidates: [(candidateC, false)])
        )
        #expect(explicitFalseBreaks.secondOnSelectableIdentifiers.isEmpty)
        #expect(explicitFalseBreaks.disposition == .noRepeatableCandidate)
    }

    @Test("baseline presence always outranks later connectability changes")
    func offPresenceOutranksConnectabilityChange() throws {
        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: try snapshot(sequence: 120, candidates: [(candidateC, false)]),
            firstOn: try snapshot(sequence: 121, candidates: [(candidateC, true)]),
            secondOff: try snapshot(sequence: 122, candidates: [(candidateC, nil)]),
            secondOn: try snapshot(sequence: 123, candidates: [(candidateC, true)])
        )

        #expect(report.firstOffObservedIdentifiers == [candidateC])
        #expect(report.secondOffObservedIdentifiers == [candidateC])
        #expect(report.repeatableCandidateIdentifiers.isEmpty)
        #expect(report.disposition == .noRepeatableCandidate)
    }

    @Test("duplicate UUIDs in one observation snapshot are rejected rather than merged by guess")
    func duplicateSnapshotIdentifiersFailClosed() {
        #expect(throws: PassiveBluetoothCandidateObservationSnapshotError
            .duplicatePeripheralIdentifier(neighborA)) {
            _ = try snapshot(
                sequence: 130,
                candidates: [
                    (neighborA, false),
                    (neighborA, true)
                ]
            )
        }
    }

    @Test("full UUID collisions in shortened UI prefix remain separate repeated candidates")
    func shortenedIdentifierCollisionDoesNotCollapseCandidates() throws {
        let first = UUID(uuidString: "12345678-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "12345678-0000-0000-0000-000000000002")!
        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: try snapshot(sequence: 140, candidates: []),
            firstOn: try snapshot(sequence: 141, candidates: [(first, true), (second, true)]),
            secondOff: try snapshot(sequence: 142, candidates: []),
            secondOn: try snapshot(sequence: 143, candidates: [(second, true), (first, true)])
        )

        #expect(report.repeatableCandidateIdentifiers == [first, second])
        #expect(report.disposition == .ambiguousRepeatableCandidates([first, second]))
    }

    @Test("disappearing stable OFF neighbor cannot manufacture positive evidence")
    func disappearingNeighborDoesNotMatter() throws {
        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: try snapshot(sequence: 150, candidates: [(neighborA, true), (neighborB, true)]),
            firstOn: try snapshot(sequence: 151, candidates: [(neighborA, true)]),
            secondOff: try snapshot(sequence: 152, candidates: [(neighborA, true), (neighborB, true)]),
            secondOn: try snapshot(sequence: 153, candidates: [(neighborA, true)])
        )

        #expect(report.repeatableCandidateIdentifiers.isEmpty)
        #expect(report.disposition == .noRepeatableCandidate)
    }

    private func snapshot(
        series: PassiveBluetoothCandidateObservationSeriesIdentity? = nil,
        sequence: UInt64,
        candidates: [(UUID, Bool?)]
    ) throws -> PassiveBluetoothCandidateObservationSnapshot {
        try PassiveBluetoothCandidateObservationSnapshot(
            observationSeriesIdentity: series ?? defaultSeries,
            windowSequence: PassiveBluetoothCandidateObservationWindowSequence(rawValue: sequence),
            candidates: candidates.map {
                .init(id: $0.0, isConnectable: $0.1)
            }
        )
    }
}
