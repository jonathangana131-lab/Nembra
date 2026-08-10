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

    @Test("field launch and fresh restart use only exact-running-build research authorization")
    func appUsesResearchAuthorizedFactoryForBothProductionConstructionSites() throws {
        let source = try Self.appSource()
        let researchFactory = "makeResearchAuthorizedES80ForCurrentApplication()"

        #expect(source.components(separatedBy: researchFactory).count - 1 == 2)
        #expect(!source.contains("PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80()"))
        #expect(!source.contains("verifiedAdmission:"))
        #expect(!source.contains("PassiveBluetoothCaptureFieldAuthorizationVerifier"))
        #expect(!source.contains("UserDefaults"))
        #expect(source.contains("onFreshExperimentRequested: makeFreshExperimentCoordinator"))
        #expect(source.contains("selectedChargerState = nil"))
        #expect(source.contains("disconnectedDeclarationAccepted = false"))
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
        let cancellation = try #require(loader.range(of: "guard !Task.isCancelled else { return }"))
        let publish = try #require(loader.range(of: "runtimeBuildIdentity = identity"))

        #expect(detached.lowerBound < reader.lowerBound)
        #expect(reader.lowerBound < cancellation.lowerBound)
        #expect(cancellation.lowerBound < publish.lowerBound)
    }
}
