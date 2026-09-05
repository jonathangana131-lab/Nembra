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
            "unbind",
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
