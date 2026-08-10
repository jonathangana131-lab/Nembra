import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field-build presentation authority")
struct TuyaFieldBuildPresentationAuthoritySourceTests {
    @Test("field-build row is backed by compiled build provenance, not Tuya account authority")
    func fieldBuildRowUsesBuildIdentityAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("var fieldBuildIsAuthoritative: Bool"))
        #expect(app.contains("buildIdentity.isAuthoritativeFieldBuild"))
        let card = try section(in: app, from: "private var authorityCard: some View", to: "private var discoveryCard: some View")
        #expect(card.contains("LabeledContent(\"Field build\""))
        #expect(card.contains("test.fieldBuildIsAuthoritative"))
        #expect(card.contains("!test.fieldBuildIsAuthoritative"))
    }

    @Test("OFF-baseline affordance fails closed on non-authoritative build provenance")
    func physicalAffordanceConsumesBuildAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let card = try section(in: app, from: "private var discoveryCard: some View", to: "private func authenticationCard")
        #expect(card.contains("Button(\"Start scooter-OFF baseline\")"))
        #expect(card.contains("!test.fieldBuildIsAuthoritative"))
        let start = try section(in: app, from: "func startBaseline()", to: "private func beginBaselineScan")
        #expect(start.contains("buildIdentity.isAuthoritativeFieldBuild"))
        #expect(start.contains("field_build_identity_unavailable"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }
    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
