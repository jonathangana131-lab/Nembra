import Foundation
import Testing

@Suite("Authenticated transport diagnostic physical-truth boundary")
struct AuthenticatedTransportDiagnosticBoundarySourceTests {
    @Test("Shareable authenticated receive evidence retains bytes without promoting scooter semantics")
    func diagnosticProjectionRemainsTransportOnly() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let start = source.range(of: "private static func exportTransportEvidence("),
              let end = source.range(of: "#endif", range: start.upperBound..<source.endIndex) else {
            Issue.record("Authenticated transport export projection was not found")
            throw SourceContractError.sectionMissing
        }

        let projection = source[start.lowerBound..<end.lowerBound]
        #expect(projection.contains("hex: $0.hex"))
        #expect(projection.contains("elapsedSinceSDKConnectionNanoseconds: $0.elapsedSinceSDKConnectionNanoseconds"))
        #expect(projection.contains("hasPayloadStrictlyBeyondHistoricalRejectionHorizon: artifact.hasPayloadStrictlyBeyondHistoricalRejectionHorizon"))
        #expect(projection.contains("authorizesRawFD50CharacteristicCustody: false"))
        #expect(projection.contains("authorizesPhysicalFirstAcceptance: false"))
        #expect(projection.contains("authorizesTelemetrySemantics: false"))
        #expect(projection.contains("authorizesControlWrites: false"))

        // A diagnostics projection must never become a shortcut to control or destructive Tuya APIs.
        #expect(!projection.contains("writeDataPoint"))
        #expect(!projection.contains("publishDps"))
        #expect(!projection.contains("unbind"))
        #expect(!projection.contains("removeDevice"))
        #expect(!projection.contains("resetDevice"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
        return String(decoding: data, as: UTF8.self)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
