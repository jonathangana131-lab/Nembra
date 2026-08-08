import Foundation
import Testing

@Suite("Experiment One recoverable rediscovery admission")
struct ForegroundCoreBluetoothCaptureControllerExperimentOneRecoverableRediscoveryTests {
    private static func source(named filename: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent(filename),
            encoding: .utf8
        )
    }

    private static func controllerMethodSource() throws -> String {
        let source = try Self.source(named: "ForegroundCoreBluetoothCaptureController.swift")
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
        let freshness = try #require(method.range(of: "receivedAtUptimeNanoseconds >="))
        let consume = try #require(method.range(of: "admission.consume()"))
        let publication = try #require(method.range(of: "recorder = payload.recorder"))

        #expect(catalog.lowerBound < consume.lowerBound)
        #expect(discovery.lowerBound < consume.lowerBound)
        #expect(attempt.lowerBound < consume.lowerBound)
        #expect(advertisement.lowerBound < consume.lowerBound)
        #expect(freshness.lowerBound < consume.lowerBound)
        #expect(consume.lowerBound < publication.lowerBound)
    }

    @Test("read-only preview is producer-owned and consumed payload rebinds exact preview identity")
    func previewCannotSubstituteAnotherAdmission() throws {
        let run = Self.codeOnly(try Self.source(named: "PassiveBluetoothExperimentOneRun.swift"))
        let method = Self.codeOnly(try Self.controllerMethodSource())

        #expect(run.contains("structStagingPreview:Equatable,Sendable"))
        #expect(run.contains("fileprivateinit(admissionIdentity:UUID,peripheralIdentifier:UUID,issuedAtUptimeNanoseconds:UInt64)"))
        #expect(run.contains("funcstagingPreview()->StagingPreview"))
        #expect(!run.contains("publicfuncstagingPreview"))

        let preview = try #require(method.range(of: "letpreview=admission.stagingPreview()"))
        let consume = try #require(method.range(of: "letpayload=tryadmission.consume()"))
        let bindIdentity = try #require(method.range(of: "payload.admissionIdentity==preview.admissionIdentity"))
        let bindTarget = try #require(method.range(of: "payload.peripheralIdentifier==preview.peripheralIdentifier"))
        let bindClock = try #require(method.range(of: "payload.issuedAtUptimeNanoseconds==preview.issuedAtUptimeNanoseconds"))
        let publication = try #require(method.range(of: "recorder=payload.recorder"))

        #expect(preview.lowerBound < consume.lowerBound)
        #expect(consume.lowerBound < bindIdentity.lowerBound)
        #expect(bindIdentity.lowerBound < publication.lowerBound)
        #expect(bindTarget.lowerBound < publication.lowerBound)
        #expect(bindClock.lowerBound < publication.lowerBound)
    }
}
