import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Foreground controller trusted Horizon minimum-duration integration")
struct ForegroundCoreBluetoothCaptureControllerHorizonMinimumDurationIntegrationTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let controller = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("NembraBluetoothCapture")
            .appendingPathComponent("ForegroundCoreBluetoothCaptureController.swift")
        return try String(contentsOf: controller, encoding: .utf8)
    }

    private static func finalizationMethod(in source: String) throws -> Substring {
        let start = try #require(
            source.range(of: "    public func encodedFinalizedObservationHorizonJSON(")?.lowerBound
        )
        let end = try #require(
            source.range(
                of: "    private func beginTargetSessionIfNeeded",
                range: start..<source.endIndex
            )?.lowerBound
        )
        return source[start..<end]
    }

    private static func offset(of needle: String, in haystack: Substring) throws -> Int {
        let range = try #require(haystack.range(of: needle))
        return haystack.distance(from: haystack.startIndex, to: range.lowerBound)
    }

    @Test("physical Experiment One obtains the producer-owned 60 second permit before Horizon mutation")
    func finalizationConsumesTrustedMinimumDurationPermit() throws {
        let source = try Self.controllerSource()
        let method = try Self.finalizationMethod(in: source)

        let authorizeOffset = try Self.offset(
            of: "PassiveCoreBluetoothObservationHorizonMinimumDurationGate.authorizeExperimentOneHorizon(",
            in: method
        )
        let permitMutationOffset = try Self.offset(
            of: "horizonPermit.beginHorizon(",
            in: method
        )
        let firstAwaitOffset = try Self.offset(
            of: "await flushPendingEvents(through:",
            in: method
        )

        #expect(authorizeOffset < permitMutationOffset)
        #expect(permitMutationOffset < firstAwaitOffset)
        #expect(!method.contains("committedReadyEpoch.beginHorizon("))
    }

    @Test("descriptive duration status cannot substitute for the mutation permit")
    func finalizationDoesNotPromoteDescriptiveStatus() throws {
        let source = try Self.controllerSource()
        let method = try Self.finalizationMethod(in: source)

        #expect(!method.contains("PassiveCoreBluetoothObservationHorizonMinimumDurationGate.evaluate("))
        #expect(!method.contains("PassiveCoreBluetoothObservationHorizonMinimumDurationGate.currentExperimentOneStatus("))
        #expect(method.contains("authorizeExperimentOneHorizon"))
        #expect(method.contains("horizonPermit.beginHorizon("))
    }
}
