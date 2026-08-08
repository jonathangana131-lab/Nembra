import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Expected-red integration contract for the V14 physical Experiment One Horizon.
///
/// The package-owned duration gate already owns trusted monotonic authorization,
/// but merely carrying that helper does not enforce the experiment. The live
/// controller finalizer must consume its producer-issued permit immediately before
/// Horizon allocation and must not call `CommittedReadyEpoch.beginHorizon(...)`
/// directly.
///
/// This test intentionally inspects the live controller source because CoreBluetooth
/// is not injected at this boundary. A future behavioral seam may replace this
/// contract, but the authority requirement must remain equivalent.
struct ForegroundCoreBluetoothCaptureControllerHorizonMinimumDurationIntegrationTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent() // NembraBluetoothCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        let controller = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("NembraBluetoothCapture")
            .appendingPathComponent("ForegroundCoreBluetoothCaptureController.swift")
        return try String(contentsOf: controller, encoding: .utf8)
    }

    private static func finalizerSection(in source: String) throws -> Substring {
        let startMarker = "    public func encodedFinalizedObservationHorizonJSON("
        let endMarker = "\n    private func beginTargetSessionIfNeeded("
        let start = try #require(source.range(of: startMarker)?.lowerBound)
        let end = try #require(
            source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound
        )
        return source[start..<end]
    }

    private static func offset(of needle: String, in haystack: Substring) throws -> Int {
        let range = try #require(haystack.range(of: needle))
        return haystack.distance(from: haystack.startIndex, to: range.lowerBound)
    }

    @Test("controller Horizon admission consumes trusted 60-second Experiment One permit")
    func finalizerCannotBypassMinimumObservationDurationAuthority() throws {
        let source = try Self.controllerSource()
        let finalizer = try Self.finalizerSection(in: source)

        let authorization = try Self.offset(
            of: "PassiveCoreBluetoothObservationHorizonMinimumDurationGate",
            in: finalizer
        )
        let authorizeCall = try Self.offset(
            of: "authorizeExperimentOneHorizon(",
            in: finalizer
        )
        let horizonBegin = try Self.offset(of: ".beginHorizon(", in: finalizer)

        #expect(authorization <= authorizeCall)
        #expect(authorizeCall < horizonBegin)
        #expect(!finalizer.contains("committedReadyEpoch.beginHorizon("))
    }
}
