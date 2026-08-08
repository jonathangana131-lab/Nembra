import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Source contract for the first controller consumer of the sealed Experiment One admission.
/// Software ownership/provenance only; no physical claim.
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

    @Test("controller previews sealed admission, then consumes it exactly once without public exposure")
    func admissionIsPackageOwnedOneShotAuthority() throws {
        let source = Self.codeOnly(try Self.controllerSource())

        #expect(source.contains("func connectUsingExperimentOneAdmission("))
        #expect(source.range(of: "public func connectUsingExperimentOneAdmission(") == nil)
        #expect(source.components(separatedBy: "admission.previewForControllerStaging()").count - 1 == 1)
        #expect(source.components(separatedBy: "admission.consume()").count - 1 == 1)
        #expect(source.contains("let preview = try admission.previewForControllerStaging()"))
        #expect(source.contains("let payload = try admission.consume()"))
    }

    @Test("Experiment One staging target comes from previewed full UUID, then consumed payload must match exactly")
    func consumedTargetMustBeFreshlyDiscoveredByThisController() throws {
        let source = Self.codeOnly(try Self.controllerSource())
        let start = try #require(source.range(of: "func connectUsingExperimentOneAdmission("))
        let end = try #require(
            source.range(
                of: "public func cancelActiveConnection()",
                range: start.upperBound..<source.endIndex
            )
        )
        let body = source[start.lowerBound..<end.lowerBound]

        let peripheralLookup = try #require(body.range(of: "peripheralByIdentifier[preview.peripheralIdentifier]"))
        let discoveryLookup = try #require(body.range(of: "latestDiscoveryByIdentifier[preview.peripheralIdentifier]"))
        let consume = try #require(body.range(of: "let payload = try admission.consume()"))
        let identityMatch = try #require(body.range(of: "payload.peripheralIdentifier == preview.peripheralIdentifier"))
        let selectTarget = try #require(body.range(of: "targetState.selectTarget(payload.peripheralIdentifier)"))

        #expect(peripheralLookup.lowerBound < consume.lowerBound)
        #expect(discoveryLookup.lowerBound < consume.lowerBound)
        #expect(consume.lowerBound < identityMatch.lowerBound)
        #expect(identityMatch.lowerBound < selectTarget.lowerBound)
    }

    @Test("Experiment One installs the exact run-owned recorder instead of invoking generic target-session recorder creation")
    func exactRunOwnedRecorderIsInstalled() throws {
        let source = Self.codeOnly(try Self.controllerSource())

        #expect(source.contains("recorder = payload.recorder"))
        #expect(source.range(of: "beginTargetSessionIfNeeded(for: payload.peripheralIdentifier)") == nil)
        #expect(source.range(of: "connect(to: payload.peripheralIdentifier") == nil)

        // The generic research path already owns one recorder constructor. The
        // Experiment One consumer must not add a second constructor to this file.
        #expect(source.components(separatedBy: "PassiveCoreBluetoothCaptureRecorder(").count - 1 == 1)
    }
}
