import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Expected-red current-spine contract for escaping abort quarantine without weakening
/// recorder/FIFO authority. This is software lifecycle chronology only; it carries no
/// physical ES80 identity, BLE/RF completeness, GATT/Tuya semantics, or telemetry truth.
struct PassiveCoreBluetoothAbortFreshSessionCurrentSpineDiagnosticTests {
    private static func gateSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("PassiveCoreBluetoothObservationBoundaryQueueGate.swift"),
            encoding: .utf8
        )
    }

    private static func reopenBody(_ source: String) throws -> Substring {
        let start = try #require(source.range(of: "mutating func reopenAfterAbortedFreshTargetSession("))
        let end = try #require(
            source.range(
                of: "mutating func resetForNewCaptureSession()",
                range: start.upperBound..<source.endIndex
            )
        )
        return source[start.lowerBound..<end.lowerBound]
    }

    @Test("abort quarantine reopens only from producer-issued real-recorder fresh-session proof")
    func requiresExactAbortAndRecorderAuthority() throws {
        let body = try Self.reopenBody(try Self.gateSource())
        #expect(body.contains("PassiveCoreBluetoothAbortedFreshTargetSession.Receipt"))
        #expect(body.contains("case let .abortQuarantined(abortReceipt)"))
        #expect(body.contains("freshTargetSession.abortedResolution.abortReceipt"))
        #expect(body.contains("abortReceipt"))
        #expect(body.contains("freshTargetSession.recorderIdentity == ObjectIdentifier(installedRecorder)"))
    }

    @Test("abort reopen requires applied global resolution and an unchanged callback tail")
    func requiresAppliedResolvedFrontierAndQuietTail() throws {
        let body = try Self.reopenBody(try Self.gateSource())
        #expect(body.contains("currentResolvedThroughQueueSequence"))
        #expect(body.contains("freshTargetSession.abortedResolution.resolvedThroughQueueSequence"))
        #expect(body.contains("currentLastEnqueuedEventSequence"))
        #expect(body.contains("resolvedThroughQueueSequence"))
    }

    @Test("abort reopen binds exactly the producer-derived fresh target generation before Ready")
    func bindsExactFreshGeneration() throws {
        let body = try Self.reopenBody(try Self.gateSource())
        #expect(body.contains("freshTargetSession.targetSessionGeneration > abortReceipt.abandonedTargetSessionGeneration"))
        #expect(body.contains("requiredReadyTargetSessionGeneration = freshTargetSession.targetSessionGeneration"))
        #expect(body.contains("phase = .awaitingReady"))
        #expect(!body.contains("resetForNewCaptureSession()"))
    }
}
