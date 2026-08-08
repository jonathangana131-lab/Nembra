import Foundation
import Testing
@testable import NembraBluetoothCapture

struct ForegroundCoreBluetoothCaptureControllerExperimentOneAdmissionContractTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent("Sources").appendingPathComponent("NembraBluetoothCapture").appendingPathComponent("ForegroundCoreBluetoothCaptureController.swift"), encoding: .utf8)
    }

    private static func codeOnly(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            guard let comment = line.range(of: "//") else { return String(line) }
            return String(line[..<comment.lowerBound])
        }.joined(separator: "\n")
    }

    @Test("controller consumes the sealed admission exactly once and does not expose it publicly")
    func admissionIsPackageOwnedOneShotAuthority() throws {
        let source = Self.codeOnly(try Self.controllerSource())
        #expect(source.contains("func connectUsingExperimentOneAdmission("))
        #expect(!source.contains("public func connectUsingExperimentOneAdmission("))
        #expect(source.components(separatedBy: "admission.consume()").count - 1 == 1)
        #expect(source.contains("let payload = try admission.consume()"))
        #expect(source.contains("let preview = try admission.previewForControllerStaging()"))
    }

    @Test("Experiment One target comes from the staged full UUID and consumed authority must match it")
    func consumedTargetMustBeFreshlyDiscoveredByThisController() throws {
        let source = Self.codeOnly(try Self.controllerSource())
        #expect(source.contains("peripheralByIdentifier[preview.peripheralIdentifier]"))
        #expect(source.contains("latestDiscoveryByIdentifier[preview.peripheralIdentifier]"))
        #expect(source.contains("payload.peripheralIdentifier == preview.peripheralIdentifier"))
        #expect(source.contains("payload.admissionIdentity == preview.admissionIdentity"))
        #expect(source.contains("targetState.selectTarget(payload.peripheralIdentifier)"))
    }

    @Test("Experiment One installs the exact run-owned recorder instead of invoking generic target-session recorder creation")
    func exactRunOwnedRecorderIsInstalled() throws {
        let source = Self.codeOnly(try Self.controllerSource())
        #expect(source.contains("recorder = payload.recorder"))
        #expect(!source.contains("beginTargetSessionIfNeeded(for: payload.peripheralIdentifier)"))
        #expect(!source.contains("connect(to: payload.peripheralIdentifier"))
        #expect(source.components(separatedBy: "PassiveCoreBluetoothCaptureRecorder(").count - 1 == 1)
    }
}
