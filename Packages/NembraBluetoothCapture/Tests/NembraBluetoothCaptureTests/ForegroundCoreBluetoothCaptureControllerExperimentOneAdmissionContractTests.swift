import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Source-level ownership contract for the first controller consumer of the sealed
/// Experiment One admission. Software provenance only; no physical ES80 claim.
struct ForegroundCoreBluetoothCaptureControllerExperimentOneAdmissionContractTests {
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

    private static func codeOnly(_ source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    @Test("controller consumes sealed Experiment One admission exactly once without public app authority")
    func admissionIsPackageOwnedOneShotAuthority() throws {
        let source = Self.codeOnly(try Self.controllerSource())
        #expect(source.contains("func connectUsingExperimentOneAdmission("))
        #expect(!source.contains("public func connectUsingExperimentOneAdmission("))
        #expect(source.components(separatedBy: "admission.consume()").count - 1 == 1)
        #expect(source.contains("let payload = try admission.consume()"))
    }

    @Test("consumed full UUID must exist in this controller's current catalog")
    func consumedTargetMustBeFreshlyDiscoveredByThisController() throws {
        let source = Self.codeOnly(try Self.controllerSource())
        #expect(source.contains("peripheralByIdentifier[payload.peripheralIdentifier]"))
        #expect(source.contains("latestDiscoveryByIdentifier[payload.peripheralIdentifier]"))
        #expect(source.contains("targetState.selectTarget(payload.peripheralIdentifier)"))
    }

    @Test("Experiment One installs the exact run-owned recorder without generic recorder creation")
    func exactRunOwnedRecorderIsInstalled() throws {
        let source = Self.codeOnly(try Self.controllerSource())
        #expect(source.contains("recorder = payload.recorder"))
        #expect(!source.contains("beginTargetSessionIfNeeded(for: payload.peripheralIdentifier)"))
        #expect(!source.contains("connect(to: payload.peripheralIdentifier"))
        #expect(source.components(separatedBy: "PassiveCoreBluetoothCaptureRecorder(").count - 1 == 1)
    }

    @Test("sealed admission cannot be spliced into an existing durable target session")
    func existingTargetSessionFailsBeforeAdmissionConsumption() throws {
        let source = Self.codeOnly(try Self.controllerSource())
        guard let start = source.range(of: "func connectUsingExperimentOneAdmission("),
              let end = source.range(of: "public func cancelActiveConnection()", range: start.upperBound..<source.endIndex) else {
            Issue.record("could not isolate Experiment One consumer body")
            return
        }
        let body = String(source[start.lowerBound..<end.lowerBound])
        let sessionGuard = try #require(body.range(of: "guard recorder == nil"))
        let consumption = try #require(body.range(of: "let payload = try admission.consume()"))
        #expect(sessionGuard.lowerBound < consumption.lowerBound)
    }
}
