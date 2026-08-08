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

    @Test("controller consumes the sealed admission exactly once and does not expose it publicly")
    func admissionIsPackageOwnedOneShotAuthority() throws {
        let source = Self.codeOnly(try Self.controllerSource())

        #expect(source.contains("func connectUsingExperimentOneAdmission("))
        #expect(!source.contains("public func connectUsingExperimentOneAdmission("))
        #expect(source.components(separatedBy: "admission.consume()").count - 1 == 1)
        #expect(source.contains("let payload = try admission.consume()"))
    }

    @Test("Experiment One target is staged from sealed full UUID and must be freshly observed before consumption")
    func stagedTargetMustBeFreshlyDiscoveredByThisController() throws {
        let source = Self.codeOnly(try Self.controllerSource())

        let preview = try #require(source.range(of: "let preview = try admission.previewForControllerStaging()"))
        let peripheral = try #require(source.range(of: "peripheralByIdentifier[preview.peripheralIdentifier]"))
        let discovery = try #require(source.range(of: "latestDiscoveryByIdentifier[preview.peripheralIdentifier]"))
        let advertisement = try #require(source.range(of: "latestAdvertisementByIdentifier[preview.peripheralIdentifier]"))
        let freshness = try #require(source.range(of: "latestAdvertisement.receivedAtUptimeNanoseconds > preview.issuedAtUptimeNanoseconds"))
        let consume = try #require(source.range(of: "let payload = try admission.consume()"))
        let select = try #require(source.range(of: "targetState.selectTarget(payload.peripheralIdentifier)"))

        #expect(preview.lowerBound < peripheral.lowerBound)
        #expect(peripheral.lowerBound < discovery.lowerBound)
        #expect(discovery.lowerBound < advertisement.lowerBound)
        #expect(advertisement.lowerBound < freshness.lowerBound)
        #expect(freshness.lowerBound < consume.lowerBound)
        #expect(consume.lowerBound < select.lowerBound)
    }

    @Test("Experiment One installs the exact run-owned recorder instead of invoking generic target-session recorder creation")
    func exactRunOwnedRecorderIsInstalled() throws {
        let source = Self.codeOnly(try Self.controllerSource())

        #expect(source.contains("recorder = payload.recorder"))
        #expect(!source.contains("beginTargetSessionIfNeeded(for: payload.peripheralIdentifier)"))
        #expect(!source.contains("connect(to: payload.peripheralIdentifier"))

        // The generic research path already owns one recorder constructor. The
        // Experiment One consumer must not add a second constructor to this file.
        #expect(source.components(separatedBy: "PassiveCoreBluetoothCaptureRecorder(").count - 1 == 1)
    }
}
