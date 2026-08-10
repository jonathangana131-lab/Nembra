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

        let authorityCard = try section(
            in: app,
            from: "private var authorityCard: some View",
            to: "private var discoveryCard: some View"
        )

        #expect(authorityCard.contains("LabeledContent(\"Field build\""))
        #expect(authorityCard.contains("test.fieldBuildIsAuthoritative"))

        guard let fieldRow = authorityCard.range(of: "LabeledContent(\"Field build\"") else {
            Issue.record("Field-build row is missing from the primary authority card.")
            return
        }
        let rowTail = String(authorityCard[fieldRow.lowerBound...].prefix(420))
        #expect(!rowTail.contains("accountIdentityLeaseIsAuthorized && test.sdkDeviceMembershipVerified"))
        #expect(!rowTail.contains("sdkDeviceMembershipVerified && test.accountIdentityLeaseIsAuthorized"))
    }

    @Test("OFF1 correlation affordance and NO-GO banner fail closed on non-authoritative build provenance")
    func physicalAffordancesConsumeBuildAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        let authorityCard = try section(
            in: app,
            from: "private var authorityCard: some View",
            to: "private var discoveryCard: some View"
        )
        #expect(authorityCard.contains("!test.fieldBuildIsAuthoritative"))

        let discoveryCard = try section(
            in: app,
            from: "private var discoveryCard: some View",
            to: "private func authenticationCard"
        )
        #expect(discoveryCard.contains("Button(\"Start OFF1 correlation\")"))
        #expect(discoveryCard.contains("!test.fieldBuildIsAuthoritative"))
    }

    @Test("runtime correlation-start guard remains defense in depth")
    func runtimeGuardIsPreserved() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let startBaseline = try section(
            in: app,
            from: "func startBaseline()",
            to: "private func beginCorrelationSeries"
        )

        #expect(startBaseline.contains("buildIdentity.isAuthoritativeFieldBuild"))
        #expect(startBaseline.contains("field_build_identity_unavailable"))
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
