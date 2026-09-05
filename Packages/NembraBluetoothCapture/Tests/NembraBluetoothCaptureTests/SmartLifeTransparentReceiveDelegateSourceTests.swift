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

    @Test("lease uses the actual package live-preflight API and exact token fence")
    func leaseMatchesLivePreflightAPI() throws {
        let source = try readRepositoryFile("NembraApp/App/SmartLifeTransparentReceiveDelegate.swift")

        #expect(source.contains("typealias Generation = TuyaReadOnlyConnectionToken"))
        #expect(source.contains("await preflight.arm("))
        #expect(source.contains("expectedDeviceID: expectedDeviceID"))
        #expect(source.contains("authenticatedPreflightSnapshot: authenticatedPreflightSnapshot"))
        #expect(source.contains("await preflight.retire(connectionToken: connectionToken)"))
        #expect(source.contains("generation?.diagnosticGeneration == connectionToken.diagnosticGeneration"))

        // These names belonged to an earlier design sketch and are not package APIs.
        #expect(!source.contains("AuthenticatedConnectionGeneration"))
        #expect(!source.contains("armAfterSmartLifeAuthentication"))
        #expect(!source.contains("terminalLifecycleDidOccur(for: armedGeneration)"))
    }

    @Test("lease never steals or stale-clears the process-global manager delegate")
    func leaseOwnsDelegateSlotFailClosed() throws {
        let source = try readRepositoryFile("NembraApp/App/SmartLifeTransparentReceiveDelegate.swift")

        #expect(source.contains("manager.delegate == nil || ownsManagerDelegateSlot"))
        #expect(source.contains("if ownsManagerDelegateSlot"))
        #expect(source.contains("manager.delegate = nil"))
        #expect(source.contains("(installedDelegate as AnyObject) === receiveDelegate"))
    }

    @Test("live evidence reads are fenced to the exact leased generation and owned delegate slot")
    func liveEvidenceReadsAreGenerationFenced() throws {
        let source = try readRepositoryFile("NembraApp/App/SmartLifeTransparentReceiveDelegate.swift")

        #expect(source.contains("func fieldAttemptEvidence(for connectionToken: Generation) async -> FieldAttemptEvidence?"))
        #expect(source.contains("func diagnosticSnapshot("))
        #expect(source.contains("generation?.diagnosticGeneration == connectionToken.diagnosticGeneration"))
        #expect(source.contains("ownsManagerDelegateSlot else"))
        #expect(source.contains("return await preflight.fieldAttemptEvidence()"))
        #expect(source.contains("return await preflight.diagnosticSnapshot()"))
    }

    @Test("live evidence surface cannot upgrade documented transport into scooter meaning or control")
    func liveEvidenceDoesNotMintSemanticAuthority() throws {
        let source = try readRepositoryFile("NembraApp/App/SmartLifeTransparentReceiveDelegate.swift")

        #expect(source.contains("FieldAttemptEvidence"))
        #expect(source.contains("raw FD50 characteristic custody"))
        #expect(source.contains("scooter DP semantics"))

        for forbidden in [
            "publishDps",
            "sendTransparentData",
            "resetFactory",
            "removeDevice",
            "unbind",
            "speedDP",
            "batteryDP",
            "modeDP",
            "lightDP",
            "brakeDP",
            "powerDP",
        ] {
            #expect(!source.contains(forbidden))
        }
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
