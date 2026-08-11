import Foundation
import Testing
@testable import NembraCore

@Suite("Physical capture transport evidence authority")
struct PhysicalCaptureTransportEvidenceAuthoritySourceTests {
    @Test("external callers cannot mint physical provenance through construction or decoding")
    func physicalEvidenceConstructionRemainsModuleOwned() throws {
        let source = try readRepositoryFile(
            "Packages/NembraCore/Sources/NembraCore/PhysicalCaptureTransportEvidence.swift"
        )

        guard let declarationRange = source.range(of: "public struct PhysicalCaptureTransportEvidence:"),
              let declarationEnd = source[declarationRange.upperBound...].firstIndex(of: "{") else {
            Issue.record("PhysicalCaptureTransportEvidence public declaration is missing.")
            return
        }
        let declaration = String(source[declarationRange.lowerBound..<declarationEnd])

        #expect(declaration.contains("Encodable"))
        #expect(!declaration.contains("Decodable"))
        #expect(!declaration.contains("Codable"))

        // The reviewed static ledger is public, but the authority-bearing memberwise
        // constructor must remain module-internal. @testable unit fixtures can still use it.
        #expect(source.contains("public extension PhysicalCaptureTransportEvidence"))
        #expect(source.contains("static let c7d09a22 = Self("))
        #expect(source.contains("\n    init(\n        captureID:"))
        #expect(!source.contains("\n    public init(\n        captureID:"))
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
}
