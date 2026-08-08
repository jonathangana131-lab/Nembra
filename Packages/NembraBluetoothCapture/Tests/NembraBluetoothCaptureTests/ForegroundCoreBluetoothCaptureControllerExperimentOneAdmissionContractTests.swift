import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Source contract for the foreground controller consumer of sealed Experiment One
/// admission. Software ownership/provenance only; no physical identity claim.
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

    @Test("controller consumes the sealed admission exactly once and does not expose it publicly")
    func admissionIsPackageOwnedOneShotAuthority() throws {
        let source = Self.codeOnly(try Self.controllerSource())

        #expect(source.contains("func connectUsingExperimentOneAdmission("))
        #expect(!source.contains("public func connectUsingExperimentOneAdmission("))
        #expect(source.components(separatedBy: "admission.consume()").count - 1 == 1)
        #expect(source.contains("let payload = try admission.consume()"))
    }

    @Test("Experiment One consumer is ES80-context gated and rechecks producer correlation")
    func admissionCannotBlessAnotherVehicleContextOrDetachedTarget() throws {
        let source = Self.codeOnly(try Self.controllerSource())

        #expect(source.contains("vehicleIdentity == VehicleProfile.aovoproES80.identity"))
        #expect(source.contains(".singleRepeatableCandidate(correlatedIdentifier)"))
        #expect(source.contains("correlatedIdentifier == payload.peripheralIdentifier"))
    }

    @Test("Experiment One target comes from consumed full UUID and must exist in the current controller catalog")
    func consumedTargetMustBeFreshlyDiscoveredByThisController() throws {
        let source = Self.codeOnly(try Self.controllerSource())

        #expect(source.contains("peripheralByIdentifier[payload.peripheralIdentifier]"))
        #expect(source.contains("latestDiscoveryByIdentifier[payload.peripheralIdentifier]"))
        #expect(source.contains("targetState.selectTarget(payload.peripheralIdentifier)"))
    }

    @Test("Experiment One publishes the exact run-owned recorder as a genuinely fresh foreground evidence life")
    func exactRunOwnedRecorderIsInstalledAsFreshDurableSession() throws {
        let source = Self.codeOnly(try Self.controllerSource())

        let targetSession = try #require(source.range(of: "acquisitionLedger.beginTargetSession()"))
        let foregroundReset = try #require(
            source.range(of: "foregroundEvidenceIntegrityValid = true", range: targetSession.lowerBound..<source.endIndex)
        )
        let recorderInstall = try #require(
            source.range(of: "recorder = payload.recorder", range: foregroundReset.lowerBound..<source.endIndex)
        )

        #expect(targetSession.lowerBound < foregroundReset.lowerBound)
        #expect(foregroundReset.lowerBound < recorderInstall.lowerBound)
        #expect(!source.contains("beginTargetSessionIfNeeded(for: payload.peripheralIdentifier)"))
        #expect(!source.contains("connect(to: payload.peripheralIdentifier"))

        // The generic research path already owns one recorder constructor. The
        // Experiment One consumer must not add a second constructor to this file.
        #expect(source.components(separatedBy: "PassiveCoreBluetoothCaptureRecorder(").count - 1 == 1)
    }
}
