import Foundation
import Testing
@testable import NembraCore

@Suite("Physical capture transport evidence")
struct PhysicalCaptureTransportEvidenceTests {
    @Test("C7D09A22 preserves exact verified Tuya FD50 transport facts")
    func c7d09a22PreservesTransportFacts() {
        let evidence = PhysicalCaptureTransportEvidence.c7d09a22

        #expect(evidence.provenance == .physicalCapture)
        #expect(evidence.captureID == "C7D09A22-96DA-4E46-9BEF-E36F670ADB0E")
        #expect(evidence.observedPeripheralID == "6815A5F5-4D1E-E004-BAE8-6DF924123907")
        #expect(evidence.advertisedLocalName == "demo")
        #expect(evidence.serviceUUID == "FD50")
        #expect(evidence.writeCharacteristicUUID == "00000001-0000-1001-8001-00805F9B07D0")
        #expect(evidence.notifyCharacteristicUUID == "00000002-0000-1001-8001-00805F9B07D0")
        #expect(evidence.completedScenarioCount == 17)
        #expect(evidence.peripheralInitiatedDisconnectCount == 15)
        #expect(abs(evidence.meanConnectedIntervalSeconds - 29.930) < 0.001)
    }

    @Test("transport-only capture cannot mint telemetry semantics")
    func transportOnlyCaptureCannotMintTelemetry() {
        let evidence = PhysicalCaptureTransportEvidence.c7d09a22

        #expect(evidence.characteristicValueEventCount == 0)
        #expect(evidence.authorizesTelemetrySemantics == false)
        #expect(evidence.isStablePhysicalDeviceIdentity == false)
    }

    @Test("accepted physical ledger remains exportable without becoming decodable authority")
    func acceptedLedgerCanBeEncoded() throws {
        let encoded = try JSONEncoder().encode(PhysicalCaptureTransportEvidence.c7d09a22)
        #expect(!encoded.isEmpty)
    }

    @Test("physical-capture provenance is repository-owned rather than caller-constructible")
    func physicalProvenanceCannotBeForgedByPublicConstructionOrDecoding() throws {
        let source = try readRepositoryFile(
            "Packages/NembraCore/Sources/NembraCore/PhysicalCaptureTransportEvidence.swift"
        )
        let declaration = try section(
            in: source,
            from: "public struct PhysicalCaptureTransportEvidence",
            to: "public extension PhysicalCaptureTransportEvidence"
        )

        #expect(declaration.contains("PhysicalCaptureTransportEvidence: Encodable, Equatable, Sendable"))
        #expect(!declaration.contains("Codable"))
        #expect(!declaration.contains("Decodable"))
        #expect(declaration.contains("private init("))
        #expect(!declaration.contains("public init("))
        #expect(source.contains("static let c7d09a22 = Self("))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
