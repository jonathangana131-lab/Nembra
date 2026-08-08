import Foundation
import Testing

@Suite("Experiment One recoverable rediscovery admission")
struct ForegroundCoreBluetoothCaptureControllerExperimentOneRecoverableRediscoveryTests {
    private static func controllerMethodSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift"), encoding: .utf8)
        let start = try #require(source.range(of: "func connectUsingExperimentOneAdmission("))
        let end = try #require(source.range(of: "public func cancelActiveConnection()", range: start.lowerBound..<source.endIndex))
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private static func runSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent("Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneRun.swift"), encoding: .utf8)
    }

    @Test("recoverable staging precedes one-shot consumption with strict post-handoff chronology")
    func rediscoveryMissDoesNotBurnAdmission() throws {
        let method = try Self.controllerMethodSource()
        let preview = try #require(method.range(of: "previewForControllerStaging()"))
        let catalog = try #require(method.range(of: "peripheralByIdentifier[preview.peripheralIdentifier]"))
        let discovery = try #require(method.range(of: "latestDiscoveryByIdentifier[preview.peripheralIdentifier]"))
        let attempt = try #require(method.range(of: "targetState.validateCanBeginAttempt(for: preview.peripheralIdentifier)"))
        let advertisement = try #require(method.range(of: "latestAdvertisementByIdentifier[preview.peripheralIdentifier]"))
        let freshness = try #require(method.range(of: "receivedAtUptimeNanoseconds > preview.issuedAtUptimeNanoseconds"))
        let consume = try #require(method.range(of: "admission.consume()"))
        let rebind = try #require(method.range(of: "payload.admissionIdentity == preview.admissionIdentity"))
        let publication = try #require(method.range(of: "recorder = payload.recorder"))
        #expect(preview.lowerBound < catalog.lowerBound)
        #expect(catalog.lowerBound < consume.lowerBound)
        #expect(discovery.lowerBound < consume.lowerBound)
        #expect(attempt.lowerBound < consume.lowerBound)
        #expect(advertisement.lowerBound < consume.lowerBound)
        #expect(freshness.lowerBound < consume.lowerBound)
        #expect(consume.lowerBound < rebind.lowerBound)
        #expect(rebind.lowerBound < publication.lowerBound)
        #expect(method.components(separatedBy: "admission.consume()").count - 1 == 1)
        #expect(!method.contains("receivedAtUptimeNanoseconds >= preview.issuedAtUptimeNanoseconds"))
    }

    @Test("staging preview carries no recorder or raw evidence and is producer constructed")
    func previewSurfaceIsNarrow() throws {
        let source = try Self.runSource()
        let start = try #require(source.range(of: "struct StagingPreview: Equatable, Sendable"))
        let end = try #require(source.range(of: "struct Payload", range: start.upperBound..<source.endIndex))
        let preview = String(source[start.lowerBound..<end.lowerBound])
        #expect(preview.contains("let admissionIdentity: UUID"))
        #expect(preview.contains("let peripheralIdentifier: UUID"))
        #expect(preview.contains("let issuedAtUptimeNanoseconds: UInt64"))
        #expect(preview.contains("fileprivate init("))
        #expect(!preview.contains("recorder"))
        #expect(!preview.contains("powerCycleEvidence"))
        #expect(source.contains("func previewForControllerStaging() throws -> StagingPreview"))
    }
}
