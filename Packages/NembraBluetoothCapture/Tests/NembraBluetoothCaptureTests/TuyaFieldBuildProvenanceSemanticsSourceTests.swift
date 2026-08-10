import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field-build provenance semantics")
struct TuyaFieldBuildProvenanceSemanticsSourceTests {
    @Test("self-consistent SHA stamping is exact provenance, not software acceptance authority")
    func buildStampDoesNotMintAcceptanceAuthority() throws {
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")

        #expect(identity.contains("sourceCommitSHA.count == 40"))
        #expect(identity.contains("capture-v14-\\(sourceCommitSHA.prefix(12))"))

        // The app can prove that its embedded label agrees with its embedded Git SHA.
        // It cannot, from those caller-supplied build settings alone, prove that the SHA
        // earned terminal exact-head CI/software acceptance.
        #expect(identity.contains("var hasValidExactGitProvenance: Bool"))
        #expect(!identity.contains("isAuthoritativeFieldBuild"))
    }

    @Test("field UI describes the stamp as provenance rather than authoritative acceptance")
    func fieldUIDoesNotOverstateBuildStampAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("fieldBuildHasValidExactGitProvenance"))
        #expect(!app.contains("fieldBuildIsAuthoritative"))
        #expect(!app.contains("? \"Authoritative ·"))
        #expect(!app.contains(": \"Not authoritative\""))

        // Physical workflow may still fail closed on missing/malformed exact Git
        // provenance; this contract only prevents self-consistency from being
        // mislabeled as the external exact-head acceptance verdict.
        #expect(app.contains("compiled exact field-build provenance"))
    }

    @Test("installer treats the supplied SHA as an expected subject, not a minted acceptance receipt")
    func installerInputRemainsExpectedSubjectOnly() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("NEMBRA_CAPTURE_EXPECTED_SOURCE_SHA"))
        #expect(!installer.contains("NEMBRA_CAPTURE_ACCEPTED_SOURCE_SHA"))
        #expect(installer.contains("SOURCE_SHA=\"$(git rev-parse HEAD"))
        #expect(installer.contains("[[ \"$SOURCE_SHA\" == \"$EXPECTED_SOURCE_SHA\" ]]"))
    }

    @Test("physical installer re-reads the built app stamp before installation")
    func installerVerifiesBuiltPhysicalAppProvenance() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let preinstall = try section(
            in: installer,
            from: "APP=\"$DERIVED/Build/Products/Debug-iphoneos/Nembra Capture.app\"",
            to: "say \"Installing SDK-integrated Capture on $DEVICE_NAME\""
        )
        let body = String(preinstall)

        #expect(body.contains("plutil -extract NembraCaptureBuildIdentifier"))
        #expect(body.contains("plutil -extract NembraCaptureSourceCommitSHA"))
        #expect(body.contains("$BUILD_LABEL"))
        #expect(body.contains("$SOURCE_SHA"))
        #expect(body.contains("die \""))
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