import Foundation
import Testing

@Suite("Experiment One recoverable rediscovery admission")
struct ForegroundCoreBluetoothCaptureControllerExperimentOneRecoverableRediscoveryTests {
    private static func controllerMethodSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent() // NembraBluetoothCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        let source = try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("ForegroundCoreBluetoothCaptureController.swift"),
            encoding: .utf8
        )

        let start = try #require(source.range(of: "func connectUsingExperimentOneAdmission("))
        let end = try #require(source.range(
            of: "public func cancelActiveConnection()",
            range: start.lowerBound..<source.endIndex
        ))
        return String(source[start.lowerBound..<end.lowerBound])
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

    @Test("recoverable target staging completes before the sealed one-shot admission is consumed")
    func rediscoveryMissDoesNotBurnExperimentOneAdmission() throws {
        let method = Self.codeOnly(try Self.controllerMethodSource())

        let catalog = try #require(method.range(of: "peripheralByIdentifier["))
        let discovery = try #require(method.range(of: "latestDiscoveryByIdentifier["))
        let attempt = try #require(method.range(of: "targetState.validateCanBeginAttempt("))
        let advertisement = try #require(method.range(of: "latestAdvertisementByIdentifier["))
        let freshness = try #require(method.range(of: "receivedAtUptimeNanoseconds > preview.issuedAtUptimeNanoseconds"))
        let consume = try #require(method.range(of: "admission.consume()"))
        let publication = try #require(method.range(of: "recorder = payload.recorder"))

        // A missing/not-yet-fresh current controller observation is a recoverable
        // staging state. It must not consume the only handoff before the rider can
        // keep scanning and retry with the same completed OFF1/ON1/OFF2/ON2 run.
        #expect(catalog.lowerBound < consume.lowerBound)
        #expect(discovery.lowerBound < consume.lowerBound)
        #expect(attempt.lowerBound < consume.lowerBound)
        #expect(advertisement.lowerBound < consume.lowerBound)
        #expect(freshness.lowerBound < consume.lowerBound)
        #expect(!method.contains("receivedAtUptimeNanoseconds >= preview.issuedAtUptimeNanoseconds"))

        // Equality is intentionally recoverable/fail-closed: sharing one monotonic clock tick
        // with issuance cannot prove that the callback receipt happened afterward.

        // Consumption remains the irreversible ownership handoff and therefore
        // must still precede publication of the exact run-owned recorder.
        #expect(consume.lowerBound < publication.lowerBound)
    }
}
