import Foundation
import Testing

@Suite("Smart Life transparent field session source contract")
struct SmartLifeTransparentFieldSessionSourceTests {
    @Test("field session arms only from an authenticated package snapshot")
    func authenticatedArmBoundaryIsExplicit() throws {
        let source = try readRepositoryFile("NembraApp/App/SmartLifeTransparentFieldSession.swift")

        #expect(source.contains("armAfterAuthenticatedLocalBLE"))
        #expect(source.contains("connectionToken: Generation"))
        #expect(source.contains("expectedDeviceID: String"))
        #expect(source.contains("authenticatedPreflightSnapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot"))
        #expect(source.contains("authenticatedPreflightSnapshot.authenticationState == .authenticated"))
        #expect(source.contains("authenticatedPreflightSnapshot.authenticationMethod == .smartLifeAppSDK"))
        #expect(source.contains("authenticatedPreflightSnapshot.connectionGeneration == connectionToken.diagnosticGeneration"))
        #expect(source.contains("trimmingCharacters(in: .whitespacesAndNewlines)"))
        #expect(source.contains("armAndInstallAfterSmartLifeAuthentication"))
    }

    @Test("field session exposes coherent exact-generation evidence")
    func exactGenerationEvidenceBoundaryIsExplicit() throws {
        let source = try readRepositoryFile("NembraApp/App/SmartLifeTransparentFieldSession.swift")

        #expect(source.contains("fieldAttemptEvidence(for connectionToken: Generation)"))
        #expect(source.contains("lease.fieldAttemptEvidence(for: connectionToken)"))
        #expect(source.contains("diagnosticSnapshot(for: connectionToken)"))
        #expect(source.contains("terminalLifecycleDidOccur(for: connectionToken)"))
    }

    @Test("field session has no mutation or invented semantic authority")
    func remainsReadOnlyAndSemanticFree() throws {
        let source = try readRepositoryFile("NembraApp/App/SmartLifeTransparentFieldSession.swift")
        let forbidden = [
            "publishDps",
            "publishDps:",
            "sendTransparent",
            "writeValue",
            "resetFactory",
            "removeDevice",
            ".unbind(",
            "setSpeed",
            "setBattery",
            "setMode",
            "setLight",
            "setBrake",
            "setPower"
        ]

        for token in forbidden {
            #expect(!source.contains(token))
        }

        #expect(source.contains("authorizesRawFD50CharacteristicCustody: Bool { false }"))
        #expect(source.contains("authorizesPhysicalFirstAcceptance: Bool { false }"))
        #expect(source.contains("authorizesStationaryMapping: Bool { false }"))
        #expect(source.contains("authorizesTelemetrySemantics: Bool { false }"))
        #expect(source.contains("authorizesControlWrites: Bool { false }"))
        #expect(source.contains("authorizesPairingResetOrUnbind: Bool { false }"))
    }

    @Test("persisted raw receive diagnostics deny every higher authority")
    func receiveDiagnosticProjectionIsExplicitlyNonAuthoritative() throws {
        let source = try readRepositoryFile("NembraApp/App/SmartLifeTransparentFieldSession.swift")
        let start = try #require(source.range(of: "private struct ReceiveDiagnosticProjection"))
        let end = try #require(source.range(of: "private let preflight", range: start.upperBound..<source.endIndex))
        let projection = String(source[start.lowerBound..<end.lowerBound])

        #expect(projection.contains("authorizesRawFD50CharacteristicCustody: Bool"))
        #expect(projection.contains("authorizesPhysicalFirstAcceptance: Bool"))
        #expect(projection.contains("authorizesStationaryMapping: Bool"))
        #expect(projection.contains("authorizesTelemetrySemantics: Bool"))
        #expect(projection.contains("authorizesControlWrites: Bool"))
        #expect(projection.contains("authorizesPairingResetOrUnbind: Bool"))

        let initializerStart = try #require(source.range(of: "let projection = ReceiveDiagnosticProjection("))
        let initializerEnd = try #require(source.range(of: "let data = try encoder.encode(projection)", range: initializerStart.upperBound..<source.endIndex))
        let initializer = String(source[initializerStart.lowerBound..<initializerEnd.lowerBound])
        #expect(initializer.contains("authorizesStationaryMapping: false"))
        #expect(initializer.contains("authorizesPairingResetOrUnbind: false"))
    }

    private func readRepositoryFile(_ path: String) throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = testsDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }
}
