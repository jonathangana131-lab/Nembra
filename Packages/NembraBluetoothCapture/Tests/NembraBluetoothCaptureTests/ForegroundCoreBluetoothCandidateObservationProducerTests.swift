import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Foreground CoreBluetooth candidate observation producer state")
struct ForegroundCoreBluetoothCandidateObservationProducerTests {
    private let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let third = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private let seriesIdentity = PassiveBluetoothCandidateObservationSeriesIdentity(
        rawValue: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    )

    @Test("successful issued windows retain one opaque series identity and strictly advance")
    func seriesSequenceAdvancesInsideOneAuthority() throws {
        var state = PassiveCoreBluetoothCandidateObservationSeriesState(
            identity: seriesIdentity
        )

        let firstWindow = try state.issueWindow()
        let secondWindow = try state.issueWindow()
        let thirdWindow = try state.issueWindow()

        #expect(firstWindow.identity == seriesIdentity)
        #expect(secondWindow.identity == seriesIdentity)
        #expect(thirdWindow.identity == seriesIdentity)
        #expect(firstWindow.sequence.rawValue == 1)
        #expect(secondWindow.sequence.rawValue == 2)
        #expect(thirdWindow.sequence.rawValue == 3)
    }

    @Test("invalidating a series permanently blocks later window issuance")
    func invalidatedSeriesCannotResume() throws {
        var state = PassiveCoreBluetoothCandidateObservationSeriesState(
            identity: seriesIdentity
        )
        _ = try state.issueWindow()
        state.invalidate()

        #expect(throws: PassiveCoreBluetoothCandidateObservationSeriesState.StateError.invalidated) {
            _ = try state.issueWindow()
        }
        #expect(state.isInvalidated)
    }

    @Test("sequence exhaustion fails closed instead of wrapping into an older chronology")
    func sequenceOverflowFailsClosed() {
        var state = PassiveCoreBluetoothCandidateObservationSeriesState(
            identity: seriesIdentity,
            nextSequenceRawValue: UInt64.max
        )

        #expect(throws: PassiveCoreBluetoothCandidateObservationSeriesState.StateError.sequenceExhausted) {
            _ = try state.issueWindow()
        }
        #expect(state.nextSequenceRawValue == UInt64.max)
    }

    @Test("missing connectability can be upgraded by explicit true without inventing other metadata")
    func trueConnectabilityOutranksUnknown() {
        var catalog = PassiveCoreBluetoothCandidateObservationCatalog()
        catalog.observe(identifier: first, isConnectable: nil)
        catalog.observe(identifier: first, isConnectable: true)

        #expect(catalog.candidates.count == 1)
        #expect(catalog.candidates[0].id == first)
        #expect(catalog.candidates[0].isConnectable == true)
    }

    @Test("any explicit non-connectable observation dominates later positive metadata")
    func explicitFalseConnectabilityFailsClosed() {
        var catalog = PassiveCoreBluetoothCandidateObservationCatalog()
        catalog.observe(identifier: first, isConnectable: true)
        catalog.observe(identifier: first, isConnectable: false)
        catalog.observe(identifier: first, isConnectable: true)

        #expect(catalog.candidates.count == 1)
        #expect(catalog.candidates[0].isConnectable == false)
    }

    @Test("missing metadata remains unknown when no explicit observation exists")
    func unknownConnectabilityRemainsUnknown() {
        var catalog = PassiveCoreBluetoothCandidateObservationCatalog()
        catalog.observe(identifier: first, isConnectable: nil)
        catalog.observe(identifier: first, isConnectable: nil)

        #expect(catalog.candidates.count == 1)
        #expect(catalog.candidates[0].isConnectable == nil)
    }

    @Test("candidate catalog remains deterministic regardless callback order")
    func catalogOrderingIsDeterministic() {
        var forward = PassiveCoreBluetoothCandidateObservationCatalog()
        forward.observe(identifier: third, isConnectable: nil)
        forward.observe(identifier: first, isConnectable: true)
        forward.observe(identifier: second, isConnectable: false)

        var reverse = PassiveCoreBluetoothCandidateObservationCatalog()
        reverse.observe(identifier: second, isConnectable: false)
        reverse.observe(identifier: first, isConnectable: true)
        reverse.observe(identifier: third, isConnectable: nil)

        #expect(forward == reverse)
        #expect(forward.candidates.map(\.id) == [first, second, third])
    }

    @Test("producer-issued series metadata composes with repeated power-cycle correlation")
    func issuedWindowsComposeWithCorrelationReducer() throws {
        var state = PassiveCoreBluetoothCandidateObservationSeriesState(
            identity: seriesIdentity
        )

        let firstOff = try state.issueWindow()
        let firstOn = try state.issueWindow()
        let secondOff = try state.issueWindow()
        let secondOn = try state.issueWindow()

        let report = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: try snapshot(issued: firstOff, candidates: [(first, true)]),
            firstOn: try snapshot(issued: firstOn, candidates: [(first, true), (third, nil)]),
            secondOff: try snapshot(issued: secondOff, candidates: [(first, true)]),
            secondOn: try snapshot(issued: secondOn, candidates: [(first, true), (third, true)])
        )

        #expect(report.observationSeriesIdentities == Array(repeating: seriesIdentity, count: 4))
        #expect(report.repeatableCandidateIdentifiers == [third])
        #expect(report.disposition == .singleRepeatableCandidate(third))
    }

    private func snapshot(
        issued: PassiveCoreBluetoothCandidateObservationSeriesState.IssuedWindow,
        candidates: [(UUID, Bool?)]
    ) throws -> PassiveBluetoothCandidateObservationSnapshot {
        try PassiveBluetoothCandidateObservationSnapshot(
            observationSeriesIdentity: issued.identity,
            windowSequence: issued.sequence,
            candidates: candidates.map {
                .init(id: $0.0, isConnectable: $0.1)
            }
        )
    }
}
