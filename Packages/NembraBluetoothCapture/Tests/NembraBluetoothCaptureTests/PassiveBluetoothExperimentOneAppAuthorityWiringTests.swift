import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One app authority wiring")
struct PassiveBluetoothExperimentOneAppAuthorityWiringTests {
    private static func appSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("App")
                .appendingPathComponent("NembraApp.swift"),
            encoding: .utf8
        )
    }

    @Test("research launch and fresh restart keep zero-argument construction fail-closed")
    func appKeepsLegacyConstructionFailClosed() throws {
        let source = try Self.appSource()
        let factory = "PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80()"
        let factoryCount = source.components(separatedBy: factory).count - 1

        #expect(factoryCount == 2)
        #expect(!source.contains("try? PassiveBluetoothExperimentOneCoordinator()"))
        #expect(!source.contains("try PassiveBluetoothExperimentOneCoordinator()"))
        #expect(source.contains("onFreshExperimentRequested: makeFreshExperimentCoordinator"))
        #expect(source.contains("selectedChargerState = nil"))
        #expect(source.contains("disconnectedDeclarationAccepted = false"))
    }

    @Test("private research path requires package admission plus a deliberate app action")
    func privateResearchPathIsExplicitAndAdmissionBearing() throws {
        let source = try Self.appSource()

        #expect(source.contains("onPrivateResearchAuthorizationAccepted: activatePrivateResearch"))
        #expect(source.contains("privateResearchAdmission: admission"))
        #expect(source.contains("privateResearchAdmission: privateResearchAdmission"))
        #expect(source.contains("Authorize stationary research capture"))
        #expect(source.contains("es80.capture.private-research-authorize"))
        #expect(source.contains("PassiveBluetoothExperimentOneFieldExecutionGate.admit("))
        #expect(source.contains("privateResearchAuthorization: privateResearchAuthorization"))
    }

    @Test("locked build identity measurement stays off MainActor and exposes a truthful pending state")
    func buildIdentityHashingRemainsOffMainActor() throws {
        let source = try Self.appSource()
        let viewStart = try #require(
            source.range(of: "private struct ES80ExperimentOneFieldNoGoView: View")?.lowerBound
        )
        let view = source[viewStart...]

        let bodyStart = try #require(view.range(of: "    var body: some View {")?.lowerBound)
        let preBody = view[..<bodyStart]
        #expect(!preBody.contains("PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()"))

        #expect(view.contains("@State private var runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity?"))
        #expect(view.contains("@State private var runtimeBuildIdentityCheckFinished = false"))
        #expect(view.contains("Capture build identity checking"))
        #expect(view.contains("Text(\"Checking…\")"))
        #expect(view.contains(".task { await loadRuntimeBuildIdentity() }"))

        let loaderStart = try #require(view.range(of: "    private func loadRuntimeBuildIdentity() async {")?.lowerBound)
        let loader = view[loaderStart...]
        let detached = try #require(loader.range(of: "Task.detached(priority: .utility)"))
        let reader = try #require(
            loader.range(of: "PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()")
        )
        let privateAuthorization = try #require(
            loader.range(of: "PassiveBluetoothCapturePrivateResearchAuthorizationReader.currentApplication(")
        )
        let cancellation = try #require(loader.range(of: "guard !Task.isCancelled else { return }"))
        let publish = try #require(loader.range(of: "runtimeBuildIdentity = result.0"))

        #expect(detached.lowerBound < reader.lowerBound)
        #expect(reader.lowerBound < privateAuthorization.lowerBound)
        #expect(privateAuthorization.lowerBound < cancellation.lowerBound)
        #expect(cancellation.lowerBound < publish.lowerBound)
    }
}
