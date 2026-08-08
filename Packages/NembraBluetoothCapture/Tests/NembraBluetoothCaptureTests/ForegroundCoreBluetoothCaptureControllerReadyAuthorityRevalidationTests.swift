import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Foreground CoreBluetooth Ready authority revalidation")
struct ForegroundCoreBluetoothCaptureControllerReadyAuthorityRevalidationTests {
    private static func readySection() throws -> Substring {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("ForegroundCoreBluetoothCaptureController.swift"),
            encoding: .utf8
        )
        let start = try #require(
            source.range(of: "    private func beginFiniteAcquisitionReadyBoundaryIfNeeded()")?.lowerBound
        )
        let end = try #require(
            source.range(of: "    private func requireForegroundEvidenceIntegrity()", range: start..<source.endIndex)?.lowerBound
        )
        return source[start..<end]
    }

    @Test("Ready revalidates exact admission authority after drain and before recorder attempt")
    func validatesAuthorityInsidePreAttemptRecoveryWindow() throws {
        let section = try Self.readySection()
        let drain = try #require(
            section.range(of: "await self.flushPendingEvents(through: admission.queueCutoff)")?.lowerBound
        )
        let foreground = try #require(
            section.range(of: "try self.requireForegroundEvidenceIntegrity()", range: drain..<section.endIndex)?.lowerBound
        )
        let health = try #require(
            section.range(of: "try self.ensureCaptureHealthy()", range: foreground..<section.endIndex)?.lowerBound
        )
        let authority = try #require(
            section.range(of: "try self.validateBoundaryAuthority(admission.authority)", range: health..<section.endIndex)?.lowerBound
        )
        let abandonment = try #require(
            section.range(of: "let abandonment = try admission.abandonBeforeRecorderAttempt()", range: authority..<section.endIndex)?.lowerBound
        )
        let quarantine = try #require(
            section.range(of: "abortReadyBeforeRecorderAttempt(", range: abandonment..<section.endIndex)?.lowerBound
        )
        let recorderAttempt = try #require(
            section.range(of: ".recordBoundaryWithMutationOutcome(on: recorder)", range: quarantine..<section.endIndex)?.lowerBound
        )

        #expect(drain < foreground)
        #expect(foreground < health)
        #expect(health < authority)
        #expect(authority < abandonment)
        #expect(abandonment < quarantine)
        #expect(quarantine < recorderAttempt)
    }

    @Test("no actor suspension exists between exact Ready authority validation and recorder attempt")
    func noAwaitAfterAuthorityValidation() throws {
        let section = try Self.readySection()
        let authority = try #require(
            section.range(of: "try self.validateBoundaryAuthority(admission.authority)")?.upperBound
        )
        let recorderAttempt = try #require(
            section.range(of: ".recordBoundaryWithMutationOutcome(on: recorder)", range: authority..<section.endIndex)?.lowerBound
        )
        #expect(!section[authority..<recorderAttempt].contains("await "))
    }
}
