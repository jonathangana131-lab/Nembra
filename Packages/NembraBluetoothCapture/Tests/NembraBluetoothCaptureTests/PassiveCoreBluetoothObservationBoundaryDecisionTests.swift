import Dispatch
import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth observation-boundary decision")
struct PassiveCoreBluetoothObservationBoundaryDecisionTests {
    private let authority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    @Test("captures queue prefix, authority, and trusted local clocks in one MainActor decision")
    func capturesDecisionAuthorityAndClocks() async throws {
        let beforeUptime = DispatchTime.now().uptimeNanoseconds

        let decision = try await MainActor.run {
            try PassiveCoreBluetoothObservationBoundaryDecision.capture(
                kind: .finiteAcquisitionReady,
                queueCutoff: 12,
                processedThrough: 9,
                authority: authority
            )
        }

        let afterUptime = DispatchTime.now().uptimeNanoseconds

        #expect(decision.queueKind == .finiteAcquisitionReady)
        #expect(decision.observationBoundaryKind == .finiteAcquisitionReady)
        #expect(decision.queueCutoff == 12)
        #expect(decision.processedThrough == 9)
        #expect(decision.authority == authority)
        #expect(decision.observedAtUptimeNanoseconds >= beforeUptime)
        #expect(decision.observedAtUptimeNanoseconds <= afterUptime)
        #expect(decision.observedAtDate.timeIntervalSinceReferenceDate.isFinite)
    }

    @Test("records the exact pre-await decision clocks through the recorder actor hop")
    func recordsExactDecisionClocksWithoutResampling() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let decision = try await MainActor.run {
            try PassiveCoreBluetoothObservationBoundaryDecision.capture(
                kind: .finiteAcquisitionReady,
                queueCutoff: 0,
                processedThrough: 0,
                authority: authority
            )
        }

        try await decision.recordBoundary(on: recorder)

        let session = await recorder.snapshot()
        let boundary = try #require(session.observationBoundaries.first)
        #expect(session.observationBoundaries.count == 1)
        #expect(boundary.kind == .finiteAcquisitionReady)
        #expect(boundary.recordSequenceWatermark == 0)
        #expect(boundary.observedAtUptimeNanoseconds == decision.observedAtUptimeNanoseconds)
        #expect(boundary.observedAtDate == decision.observedAtDate)
    }

    @Test("maps horizon intent mechanically into the durable observation vocabulary")
    func mapsHorizonKind() async throws {
        let decision = try await MainActor.run {
            try PassiveCoreBluetoothObservationBoundaryDecision.capture(
                kind: .observationHorizon,
                queueCutoff: 15,
                processedThrough: 15,
                authority: authority
            )
        }

        #expect(decision.queueKind == .observationHorizon)
        #expect(decision.observationBoundaryKind == .observationHorizon)
        #expect(decision.queueCutoff == 15)
        #expect(decision.processedThrough == 15)
    }

    @Test("rejects a processed recorder frontier beyond the synchronous queue cutoff")
    func rejectsProcessedFrontierBeyondCutoff() async {
        do {
            _ = try await MainActor.run {
                try PassiveCoreBluetoothObservationBoundaryDecision.capture(
                    kind: .observationHorizon,
                    queueCutoff: 14,
                    processedThrough: 15,
                    authority: authority
                )
            }
            Issue.record("A boundary decision cannot place its FIFO cutoff behind recorder-completed evidence.")
        } catch let error as PassiveCoreBluetoothObservationBoundaryDecision.StateError {
            #expect(error == .processedFrontierBeyondCutoff)
        } catch {
            Issue.record("Unexpected boundary-decision error: \(error)")
        }
    }

    @Test("allows a quiet horizon with no new raw callback beyond the processed prefix")
    func allowsQuietHorizonAtProcessedPrefix() async throws {
        let decision = try await MainActor.run {
            try PassiveCoreBluetoothObservationBoundaryDecision.capture(
                kind: .observationHorizon,
                queueCutoff: 8,
                processedThrough: 8,
                authority: authority
            )
        }

        #expect(decision.queueCutoff == decision.processedThrough)
        #expect(decision.observationBoundaryKind == .observationHorizon)
    }
}
