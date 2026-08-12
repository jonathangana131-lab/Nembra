import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth power-cycle observation windows")
struct PassiveBluetoothPowerCycleObservationSessionTests {
    private let scooter = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let stableNeighbor = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let oneOffNeighbor = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    private func candidate(
        _ id: UUID,
        connectable: Bool? = true
    ) -> PassiveBluetoothCandidateObservationSnapshot.Candidate {
        .init(id: id, isConnectable: connectable)
    }

    @Test("four completed windows keep one software authority and replay exact correlation")
    func completesOneRepeatedSeries() throws {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: 10
        )

        let firstOff = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: 100,
            endedAtUptimeNanoseconds: 110,
            candidates: [candidate(stableNeighbor)]
        )
        #expect(firstOff == nil)

        let firstOn = try ledger.completeWindow(
            phase: .firstPoweredOn,
            startedAtUptimeNanoseconds: 200,
            endedAtUptimeNanoseconds: 210,
            candidates: [candidate(stableNeighbor), candidate(scooter)]
        )
        #expect(firstOn == nil)

        let secondOff = try ledger.completeWindow(
            phase: .secondPoweredOff,
            startedAtUptimeNanoseconds: 300,
            endedAtUptimeNanoseconds: 310,
            candidates: [candidate(stableNeighbor)]
        )
        #expect(secondOff == nil)

        let completedSeries = try ledger.completeWindow(
            phase: .secondPoweredOn,
            startedAtUptimeNanoseconds: 400,
            endedAtUptimeNanoseconds: 410,
            candidates: [candidate(stableNeighbor), candidate(scooter)]
        )
        let result = try #require(completedSeries)

        #expect(result.windows.map(\.phase) == PassiveBluetoothPowerCycleObservationPhase.allCases)
        #expect(result.windows.map { $0.windowSequence.rawValue } == [1, 2, 3, 4])
        #expect(result.windows.map(\.observedCandidateCount) == [1, 2, 1, 2])
        #expect(result.observationSnapshots.count == 4)
        #expect(result.observationSnapshots.map { $0.windowSequence.rawValue } == [1, 2, 3, 4])
        #expect(result.observationSnapshots[0].candidates == [candidate(stableNeighbor)])
        #expect(result.observationSnapshots[1].candidates == [
            candidate(scooter),
            candidate(stableNeighbor)
        ].sorted { $0.id.uuidString < $1.id.uuidString })
        #expect(result.observationSnapshots[2].candidates == [candidate(stableNeighbor)])
        #expect(result.observationSnapshots[3].candidates == [
            candidate(scooter),
            candidate(stableNeighbor)
        ].sorted { $0.id.uuidString < $1.id.uuidString })
        #expect(Set(result.correlation.observationSeriesIdentities).count == 1)
        #expect(result.correlation.disposition == .singleRepeatableCandidate(scooter))

        let replayed = PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: result.observationSnapshots[0],
            firstOn: result.observationSnapshots[1],
            secondOff: result.observationSnapshots[2],
            secondOn: result.observationSnapshots[3]
        )
        #expect(replayed == result.correlation)
    }

    @Test("one-off arrival cannot become repeated target evidence")
    func oneOffArrivalDoesNotPass() throws {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: 1
        )

        _ = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: 10,
            endedAtUptimeNanoseconds: 11,
            candidates: []
        )
        _ = try ledger.completeWindow(
            phase: .firstPoweredOn,
            startedAtUptimeNanoseconds: 20,
            endedAtUptimeNanoseconds: 21,
            candidates: [candidate(scooter), candidate(oneOffNeighbor)]
        )
        _ = try ledger.completeWindow(
            phase: .secondPoweredOff,
            startedAtUptimeNanoseconds: 30,
            endedAtUptimeNanoseconds: 31,
            candidates: []
        )
        let completedSeries = try ledger.completeWindow(
            phase: .secondPoweredOn,
            startedAtUptimeNanoseconds: 40,
            endedAtUptimeNanoseconds: 41,
            candidates: [candidate(scooter)]
        )
        let result = try #require(completedSeries)

        #expect(result.correlation.repeatableCandidateIdentifiers == [scooter])
        #expect(result.correlation.disposition == .singleRepeatableCandidate(scooter))
    }

    @Test("candidate seen while expected off stays ineligible")
    func offWindowPresenceFailsClosed() throws {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: 1
        )

        _ = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: 10,
            endedAtUptimeNanoseconds: 11,
            candidates: []
        )
        _ = try ledger.completeWindow(
            phase: .firstPoweredOn,
            startedAtUptimeNanoseconds: 20,
            endedAtUptimeNanoseconds: 21,
            candidates: [candidate(scooter)]
        )
        _ = try ledger.completeWindow(
            phase: .secondPoweredOff,
            startedAtUptimeNanoseconds: 30,
            endedAtUptimeNanoseconds: 31,
            candidates: [candidate(scooter)]
        )
        let completedSeries = try ledger.completeWindow(
            phase: .secondPoweredOn,
            startedAtUptimeNanoseconds: 40,
            endedAtUptimeNanoseconds: 41,
            candidates: [candidate(scooter)]
        )
        let result = try #require(completedSeries)

        #expect(result.correlation.repeatableCandidateIdentifiers.isEmpty)
        #expect(result.correlation.disposition == .noRepeatableCandidate)
    }

    @Test("too-short window fails without consuming phase or authority sequence")
    func minimumDurationFailureIsAtomic() throws {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: 10
        )

        #expect(throws: PassiveBluetoothPowerCycleObservationSessionError.minimumWindowDurationNotReached) {
            try ledger.completeWindow(
                phase: .firstPoweredOff,
                startedAtUptimeNanoseconds: 100,
                endedAtUptimeNanoseconds: 109,
                candidates: [candidate(stableNeighbor)]
            )
        }

        #expect(ledger.nextPhase == .firstPoweredOff)
        #expect(ledger.completedSnapshots.isEmpty)
        #expect(ledger.completedReceipts.isEmpty)

        _ = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: 100,
            endedAtUptimeNanoseconds: 110,
            candidates: [candidate(stableNeighbor)]
        )
        #expect(ledger.completedReceipts.map { $0.windowSequence.rawValue } == [1])
    }

    @Test("backwards local receipt clock fails without mutation")
    func backwardsClockFailureIsAtomic() throws {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: 1
        )

        #expect(throws: PassiveBluetoothPowerCycleObservationSessionError.nonMonotonicWindowClock) {
            try ledger.completeWindow(
                phase: .firstPoweredOff,
                startedAtUptimeNanoseconds: 200,
                endedAtUptimeNanoseconds: 199,
                candidates: []
            )
        }

        #expect(ledger.nextPhase == .firstPoweredOff)
        #expect(ledger.completedSnapshots.isEmpty)
    }

    @Test("explicit non-connectable ON candidate remains excluded by canonical correlation")
    func nonConnectableCandidateDoesNotPass() throws {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(
            minimumWindowDurationNanoseconds: 1
        )

        _ = try ledger.completeWindow(
            phase: .firstPoweredOff,
            startedAtUptimeNanoseconds: 1,
            endedAtUptimeNanoseconds: 2,
            candidates: []
        )
        _ = try ledger.completeWindow(
            phase: .firstPoweredOn,
            startedAtUptimeNanoseconds: 3,
            endedAtUptimeNanoseconds: 4,
            candidates: [candidate(scooter, connectable: false)]
        )
        _ = try ledger.completeWindow(
            phase: .secondPoweredOff,
            startedAtUptimeNanoseconds: 5,
            endedAtUptimeNanoseconds: 6,
            candidates: []
        )
        let completedSeries = try ledger.completeWindow(
            phase: .secondPoweredOn,
            startedAtUptimeNanoseconds: 7,
            endedAtUptimeNanoseconds: 8,
            candidates: [candidate(scooter)]
        )
        let result = try #require(completedSeries)

        #expect(result.correlation.disposition == .noRepeatableCandidate)
    }

    @Test("connectability merge never erases stronger negative evidence")
    func connectabilityMergeIsEvidenceMonotonic() {
        #expect(PassiveBluetoothPowerCycleConnectabilityMerge.merged(current: nil, incoming: nil) == nil)
        #expect(PassiveBluetoothPowerCycleConnectabilityMerge.merged(current: nil, incoming: true) == true)
        #expect(PassiveBluetoothPowerCycleConnectabilityMerge.merged(current: true, incoming: nil) == true)
        #expect(PassiveBluetoothPowerCycleConnectabilityMerge.merged(current: true, incoming: true) == true)
        #expect(PassiveBluetoothPowerCycleConnectabilityMerge.merged(current: false, incoming: nil) == false)
        #expect(PassiveBluetoothPowerCycleConnectabilityMerge.merged(current: false, incoming: true) == false)
        #expect(PassiveBluetoothPowerCycleConnectabilityMerge.merged(current: true, incoming: false) == false)
        #expect(PassiveBluetoothPowerCycleConnectabilityMerge.merged(current: nil, incoming: false) == false)
        #expect(PassiveBluetoothPowerCycleConnectabilityMerge.merged(current: false, incoming: false) == false)
    }

    @Test("callback admission requires powered-on active scan and a started receipt window")
    func scanLivenessFailsClosed() {
        #expect(PassiveBluetoothPowerCycleScanLiveness.isLive(
            isPoweredOn: true,
            isScanning: true,
            hasStartedReceiptWindow: true
        ))
        #expect(!PassiveBluetoothPowerCycleScanLiveness.isLive(
            isPoweredOn: false,
            isScanning: true,
            hasStartedReceiptWindow: true
        ))
        #expect(!PassiveBluetoothPowerCycleScanLiveness.isLive(
            isPoweredOn: true,
            isScanning: false,
            hasStartedReceiptWindow: true
        ))
        #expect(!PassiveBluetoothPowerCycleScanLiveness.isLive(
            isPoweredOn: true,
            isScanning: true,
            hasStartedReceiptWindow: false
        ))
    }

    @Test("explicit abandonment invalidates an incomplete series even without active transport")
    @MainActor
    func abandonmentWithoutActiveTransportInvalidatesSeries() throws {
        let session = try PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 1)

        session.abandonCurrentWindow()

        #expect(session.progress?.isSeriesInvalidated == true)
        #expect(throws: PassiveBluetoothPowerCycleObservationSessionError.seriesInvalidated) {
            try session.startCurrentWindow()
        }
    }

    @Test("public session policy rejects zero and non-finite observation windows")
    @MainActor
    func invalidPolicyRejectsBeforeCreatingCoreBluetoothTransport() {
        #expect(throws: PassiveBluetoothPowerCycleObservationSessionError.invalidMinimumWindowDuration) {
            try PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 0)
        }
        #expect(throws: PassiveBluetoothPowerCycleObservationSessionError.invalidMinimumWindowDuration) {
            try PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: .infinity)
        }
        #expect(throws: PassiveBluetoothPowerCycleObservationSessionError.invalidMinimumWindowDuration) {
            try PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: .nan)
        }
    }
}
