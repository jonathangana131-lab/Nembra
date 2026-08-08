import Foundation
import Testing

@Suite("Experiment One recoverable rediscovery admission")
struct ForegroundCoreBluetoothCaptureControllerExperimentOneRecoverableRediscoveryTests {
    private static func source(named filename: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent("Sources").appendingPathComponent("NembraBluetoothCapture").appendingPathComponent(filename), encoding: .utf8)
    }

    private static func controllerMethodSource() throws -> String {
        let source = try source(named: "ForegroundCoreBluetoothCaptureController.swift")
        let start = try #require(source.range(of: "func connectUsingExperimentOneAdmission("))
        let end = try #require(source.range(of: "public func cancelActiveConnection()", range: start.lowerBound..<source.endIndex))
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private static func codeOnly(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            guard let comment = line.range(of: "//") else { return String(line) }
            return String(line[..<comment.lowerBound])
        }.joined(separator: "\n")
    }

    @Test("recoverable target staging completes before the sealed one-shot admission is consumed")
    func rediscoveryMissDoesNotBurnExperimentOneAdmission() throws {
        let method = Self.codeOnly(try Self.controllerMethodSource())
        let preview = try #require(method.range(of: "admission.previewForControllerStaging()"))
        let catalog = try #require(method.range(of: "peripheralByIdentifier[preview.peripheralIdentifier]"))
        let discovery = try #require(method.range(of: "latestDiscoveryByIdentifier[preview.peripheralIdentifier]"))
        let attempt = try #require(method.range(of: "targetState.validateCanBeginAttempt(for: preview.peripheralIdentifier)"))
        let advertisement = try #require(method.range(of: "latestAdvertisementByIdentifier[preview.peripheralIdentifier]"))
        let freshness = try #require(method.range(of: "receivedAtUptimeNanoseconds > preview.issuedAtUptimeNanoseconds"))
        let consume = try #require(method.range(of: "admission.consume()"))
        let publication = try #require(method.range(of: "recorder = payload.recorder"))

        #expect(preview.lowerBound < catalog.lowerBound)
        #expect(catalog.lowerBound < consume.lowerBound)
        #expect(discovery.lowerBound < consume.lowerBound)
        #expect(attempt.lowerBound < consume.lowerBound)
        #expect(advertisement.lowerBound < consume.lowerBound)
        #expect(freshness.lowerBound < consume.lowerBound)
        #expect(consume.lowerBound < publication.lowerBound)
    }

    @Test("consumed payload must match the producer-owned staging preview")
    func consumedPayloadMatchesPreviewBeforePublication() throws {
        let method = Self.codeOnly(try Self.controllerMethodSource())
        let consume = try #require(method.range(of: "let payload = try admission.consume()"))
        let identity = try #require(method.range(of: "payload.admissionIdentity == preview.admissionIdentity"))
        let target = try #require(method.range(of: "payload.peripheralIdentifier == preview.peripheralIdentifier"))
        let clock = try #require(method.range(of: "payload.issuedAtUptimeNanoseconds == preview.issuedAtUptimeNanoseconds"))
        let publication = try #require(method.range(of: "recorder = payload.recorder"))
        #expect(consume.lowerBound < identity.lowerBound)
        #expect(identity.lowerBound < publication.lowerBound)
        #expect(target.lowerBound < publication.lowerBound)
        #expect(clock.lowerBound < publication.lowerBound)
    }

    @Test("staging preview stays package-internal and producer-constructed")
    func previewAuthoritySurfaceIsSealed() throws {
        let source = try Self.source(named: "PassiveBluetoothExperimentOneRun.swift")
        #expect(source.contains("struct StagingPreview: Equatable, Sendable"))
        #expect(source.contains("fileprivate init(payload: Payload)"))
        #expect(source.contains("func previewForControllerStaging() throws -> StagingPreview"))
        #expect(!source.contains("public struct StagingPreview"))
        #expect(!source.contains("public func previewForControllerStaging"))
    }
}
