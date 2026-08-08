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

    private static func codeOnly(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            guard let comment = line.range(of: "//") else { return String(line) }
            return String(line[..<comment.lowerBound])
        }.joined(separator: "\n")
    }

    @Test("recoverable target staging completes before the sealed one-shot admission is consumed")
    func rediscoveryMissDoesNotBurnExperimentOneAdmission() throws {
        let method = Self.codeOnly(try Self.controllerMethodSource())
        let preview = try #require(method.range(of: "admission.targetPreview"))
        let catalog = try #require(method.range(of: "peripheralByIdentifier["))
        let discovery = try #require(method.range(of: "latestDiscoveryByIdentifier["))
        let attempt = try #require(method.range(of: "targetState.validateCanBeginAttempt("))
        let advertisement = try #require(method.range(of: "latestAdvertisementByIdentifier["))
        let freshness = try #require(method.range(of: "receivedAtUptimeNanoseconds >="))
        let consume = try #require(method.range(of: "admission.consume()"))
        let binding = try #require(method.range(of: "payload.admissionIdentity == preview.admissionIdentity"))
        let publication = try #require(method.range(of: "recorder = payload.recorder"))
        #expect(preview.lowerBound < catalog.lowerBound)
        #expect(catalog.lowerBound < consume.lowerBound)
        #expect(discovery.lowerBound < consume.lowerBound)
        #expect(attempt.lowerBound < consume.lowerBound)
        #expect(advertisement.lowerBound < consume.lowerBound)
        #expect(freshness.lowerBound < consume.lowerBound)
        #expect(consume.lowerBound < binding.lowerBound)
        #expect(binding.lowerBound < publication.lowerBound)
    }
}
