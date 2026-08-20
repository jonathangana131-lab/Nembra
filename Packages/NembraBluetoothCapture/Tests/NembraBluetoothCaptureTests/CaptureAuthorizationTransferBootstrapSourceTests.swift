import Foundation
import Testing
@testable import NembraBluetoothCapture

extension CaptureSimulatorQAHarnessSourceTests_AuthenticatedFieldCapabilityAppWiring {
    @Test("controller bootstrap creates only transfer custody before authority-gated handoff")
    func controllerBootstrapIsNonAuthorizing() throws {
        let coordinator = try repositorySource(
            "NembraApp/App/NembraCaptureFieldAuthorizationController.swift"
        )
        let initializer = try sourceSlice(
            coordinator,
            from: "init() {",
            through: "init(session: AuthenticatedStationaryCaptureAppSession)"
        )

        #expect(initializer.contains("prepareAuthorizationTransferDirectory()"))
        #expect(!initializer.contains("takeInstallManifest()"))
        #expect(!initializer.contains("prepareSignerRendezvousDocumentFromInbox()"))
        #expect(!initializer.contains("authorizeFromInbox()"))
        #expect(!initializer.contains("acceptEnvelope"))
        #expect(!initializer.contains("admitOFF1Start()"))
    }

    @Test("authority-gated handoff consumes subjects but does not own directory bootstrap")
    func handoffConsumesOnlyAfterIndependentBootstrap() throws {
        let coordinator = try repositorySource(
            "NembraApp/App/NembraCaptureFieldAuthorizationController.swift"
        )
        let handoff = try sourceSlice(
            coordinator,
            from: "func advanceInboxHandoffIfAvailable()",
            through: "func admitOFF1Start()"
        )

        #expect(!handoff.contains("prepareAuthorizationTransferDirectory()"))
        #expect(handoff.contains("transferDirectoryPreparationError"))
        #expect(handoff.contains("session.revoke()"))
        #expect(handoff.contains("prepareSignerRendezvousDocumentFromInbox()"))
        #expect(handoff.contains("authorizeFromInbox()"))
    }

    private func sourceSlice(
        _ source: String,
        from startMarker: String,
        through endMarker: String
    ) throws -> String {
        let start = try #require(source.range(of: startMarker))
        let end = try #require(
            source.range(of: endMarker, range: start.upperBound..<source.endIndex)
        )
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func repositorySource(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
