import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya accepted application-event provenance")
struct TuyaApplicationEventMetadataPrecedenceSourceTests {
    @Test("trusted generation is constructed before suspension and cannot be forged by SDK details")
    func trustedGenerationWinsReservedCollision() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        let custody = try #require(receiver.range(
            of: "guard let eventDetails = TuyaApplicationEventCustody.admittedDetails("
        ))
        let generation = try #require(receiver.range(
            of: "connectionGeneration: String(token.diagnosticGeneration)"
        ))
        let firstAwait = try #require(receiver.range(of: "try await sessionLedger.recordApplicationUpdate"))
        let log = try #require(receiver.range(of: "log(\"tuya_application_update\", eventDetails)"))

        #expect(custody.lowerBound <= generation.lowerBound)
        #expect(generation.lowerBound < firstAwait.lowerBound)
        #expect(firstAwait.lowerBound < log.lowerBound)
        #expect(!receiver.contains("eventDetails[\"generation\"]"))
        #expect(!receiver.contains("update.merging(["))
        #expect(!receiver.contains("redactedApplicationEventDetails"))
    }

    @Test("application generation collisions remain opaque evidence under a non-authoritative namespace")
    func packageCustodyNamespacesApplicationGeneration() throws {
        let custody = try readRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaApplicationEventCustody.swift"
        )

        #expect(custody.contains("return normalized == \"generation\" ? \"application.generation\" : key"))
        #expect(custody.contains("admitted[\"generation\"] = generation"))
        #expect(custody.contains("insertPreservingCollision("))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            throw Error.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private enum Error: Swift.Error { case sectionMissing }
}
