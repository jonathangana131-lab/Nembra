import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Smart Life documented transparent receive bridge")
struct SmartLifeTransparentReceiveDelegateSourceTests {
    @Test("bridge forwards only documented device-to-app bytes into package custody")
    func bridgeIsReadOnlyAndSemanticsFree() throws {
        let source = try readRepositoryFile("NembraApp/App/SmartLifeTransparentReceiveDelegate.swift")

        #expect(source.contains("ThingSmartBLEManagerDelegate"))
        #expect(source.contains("func bleReceiveTransparentData(_ data: Data!, devId: String!)"))
        #expect(source.contains("preflight.receiveDocumentedSmartLifeCallback(payload: data, deviceID: devId)"))

        for forbidden in [
            "publishDps",
            "publishDpsWith",
            "sendTransparentData",
            "resetFactory",
            "removeDevice",
            "unbind",
            "deleteDevice",
        ] {
            #expect(!source.contains(forbidden))
        }

        for inventedSemantic in ["speedDP", "batteryDP", "modeDP", "lightDP", "brakeDP", "powerDP"] {
            #expect(!source.contains(inventedSemantic))
        }
    }

    @Test("bridge leaves exact device and generation admission inside package preflight")
    func bridgeDoesNotInventIdentityOrGeneration() throws {
        let source = try readRepositoryFile("NembraApp/App/SmartLifeTransparentReceiveDelegate.swift")

        #expect(!source.contains("?? \"demo\""))
        #expect(!source.contains("6815A5F5-4D1E-E004-BAE8-6DF924123907"))
        #expect(!source.contains("C7D09A22" + "DocumentedTransparentReceiveIngress"))
        #expect(source.contains("C7D09A22DocumentedTransparentLivePreflight"))
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
