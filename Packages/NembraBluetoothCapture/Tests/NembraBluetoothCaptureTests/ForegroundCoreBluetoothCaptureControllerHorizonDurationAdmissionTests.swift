import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Controller composition contract for Experiment One's producer-issued 60 s
/// monotonic Ready -> Horizon permit. Software procedure authority only.
struct ForegroundCoreBluetoothCaptureControllerHorizonDurationAdmissionTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("ForegroundCoreBluetoothCaptureController.swift"),
            encoding: .utf8
        )
    }

    @Test("finalizer obtains trusted duration permit before Horizon allocation")
    func finalizerConsumesDurationPermitBeforeHorizon() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "    public func encodedFinalizedObservationHorizonJSON(")?.lowerBound)
        let end = try #require(source.range(of: "    private func beginTargetSessionIfNeeded", range: start..<source.endIndex)?.lowerBound)
        let section = source[start..<end]

        let authorize = try #require(section.range(of: "authorizeExperimentOneHorizon(for: committedReadyEpoch)")?.lowerBound)
        let begin = try #require(section.range(of: "durationPermit.beginHorizon(")?.lowerBound)
        #expect(section.distance(from: section.startIndex, to: authorize) < section.distance(from: section.startIndex, to: begin))
        #expect(!section.contains("committedReadyEpoch.beginHorizon("))
    }

    @Test("product finalization eligibility consults the monotonic duration status")
    func canFinalizeDoesNotAdvertiseEarlyHorizon() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "    public var canFinalizeObservationHorizon: Bool {")?.lowerBound)
        let end = try #require(source.range(of: "    private let vehicleIdentity", range: start..<source.endIndex)?.lowerBound)
        let section = source[start..<end]

        #expect(section.contains("PassiveCoreBluetoothObservationHorizonMinimumDurationGate"))
        #expect(section.contains("currentExperimentOneStatus(for: committedReadyEpoch)"))
        #expect(section.contains("case .eligible"))
    }
}