import Foundation
import Testing
@testable import NembraBluetoothCapture

extension CaptureSimulatorQAHarnessSourceTests_AuthenticatedFieldCapabilityAppWiring {
    @Test("idle handoff prepares protected transfer custody before first manifest read")
    func idleHandoffPreparesTransferDirectoryBeforeManifestRead() throws {
        let coordinator = try repositorySource(
            "NembraApp/App/NembraCaptureFieldAuthorizationController.swift"
        )
        let handoff = try sourceSlice(
            coordinator,
            from: "func advanceInboxHandoffIfAvailable()",
            through: "func admitOFF1Start()"
        )
        let prepare = try #require(
            handoff.range(of: "prepareAuthorizationTransferDirectory()")
        )
        let consume = try #require(
            handoff.range(of: "prepareSignerRendezvousDocumentFromInbox()")
        )

        #expect(prepare.lowerBound < consume.lowerBound)
        let preparationBoundary = handoff[prepare.lowerBound..<consume.lowerBound]
        #expect(preparationBoundary.contains("catch"))
        #expect(preparationBoundary.contains("session.revoke()"))
    }

    @Test("controller construction does not create transport state")
    func controllerConstructionDoesNotPrepareTransferDirectory() throws {
        let coordinator = try repositorySource(
            "NembraApp/App/NembraCaptureFieldAuthorizationController.swift"
        )
        let initializer = try sourceSlice(
            coordinator,
            from: "init() {",
            through: "init(session: AuthenticatedStationaryCaptureAppSession)"
        )

        #expect(!initializer.contains("prepareAuthorizationTransferDirectory()"))
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
