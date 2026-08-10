import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application evidence custody")
struct TuyaApplicationEvidenceCustodySourceTests {
    @Test("verified account UID is redacted before accepted application event custody")
    func accountUIDCannotEnterApplicationEvent() throws {
        let source = try entrypointSource()
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))
        let prepareExport = String(try section(
            in: source,
            from: "func prepareExport()",
            to: "private func abandonPackageCorrelation()"
        ))

        #expect(prepareExport.contains("No account UID"))
        #expect(receiver.contains("guard let verifiedAccountUID = membershipAccountUID"))
        #expect(receiver.contains("accountIdentityLeaseIsAuthorized"))
        #expect(receiver.contains("TuyaApplicationUpdateSecretSanitizer.redactingAccountUID("))
        #expect(receiver.contains("verifiedAccountUID: verifiedAccountUID"))
        #expect(source.contains("<redacted-account-uid>"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update.merging(["))
    }

    @Test("Nembra generation provenance wins SDK application-key collisions")
    func trustedGenerationWinsReservedCollision() throws {
        let source = try entrypointSource()
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(receiver.contains("\"generation\": String(token.diagnosticGeneration)"))
        #expect(receiver.contains(") { _, trusted in trusted })"))
        #expect(!receiver.contains(") { current, _ in current })"))
    }

    @Test("generic uid keys remain legitimate device evidence")
    func genericUIDKeyIsNotBlanketSecret() throws {
        let sanitizer = try readRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaApplicationUpdateSecretSanitizer.swift"
        )
        #expect(!sanitizer.contains("\"uid\","))
        #expect(!sanitizer.contains("\"uid\"\n"))
        #expect(sanitizer.contains("redactingAccountUID"))
    }

    private func entrypointSource() throws -> String {
        try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
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

    private enum SourceContractError: Error { case sectionMissing }
}
