import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One private research authorization custody")
struct PassiveBluetoothExperimentOneResearchBuildAuthorizationTests {
    @Test("signed-field producer stamps every build-time subject consumed by research admission")
    func producerStampsExactResearchTuple() throws {
        let producer = try repositorySourceFile("scripts/ci/xcode27_signed_field_candidate.sh")

        #expect(producer.contains("BUILD_IDENTIFIER=\"Capture Build V14-${SOURCE_SHA:0:12}\""))
        #expect(producer.contains("FIELD_RECIPE_ID=\"ES80-FINGERPRINT-v1\""))
        #expect(producer.contains("INFOPLIST_KEY_NembraCaptureBuildIdentifier=$BUILD_IDENTIFIER"))
        #expect(producer.contains("INFOPLIST_KEY_NembraCaptureBuildInstanceID=$BUILD_INSTANCE_ID"))
        #expect(producer.contains("INFOPLIST_KEY_NembraCaptureBuildCommitSHA=$SOURCE_SHA"))
        #expect(producer.contains("INFOPLIST_KEY_NembraCaptureFieldRecipe=$FIELD_RECIPE_ID"))
        #expect(producer.contains("-configuration Release"))
        #expect(producer.contains("-destination \"generic/platform=iOS\""))
    }

    @Test("live research authority comes from signed Bundle metadata, not runtime preferences or arguments")
    func liveGateHasNoRuntimeInputAuthorizationSeam() throws {
        let gate = try packageSourceFile(
            "Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneFieldExecutionGate.swift"
        )

        #expect(gate.contains("#if os(iOS) && !targetEnvironment(simulator) && !DEBUG"))
        #expect(gate.contains("Bundle.main.infoDictionary"))
        #expect(gate.contains("researchBuildAdmission(infoDictionary:"))
        #expect(!gate.contains("UserDefaults"))
        #expect(!gate.contains("ProcessInfo"))
        #expect(!gate.contains("CommandLine"))
        #expect(!gate.contains("environment["))
    }

    @Test("canonical app factory requires package-derived research admission before live CoreBluetooth")
    func canonicalFactoryKeepsResearchAuthorityPackageOwned() throws {
        let source = try packageSourceFile(
            "Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneCoordinator+CanonicalES80.swift"
        )
        let zeroFactoryStart = try #require(
            source.range(of: "static func makeAuthorizedES80() throws")?.lowerBound
        )
        let verifiedFactoryStart = try #require(
            source.range(of: "static func makeAuthorizedES80(\n        verifiedAdmission _:")?.lowerBound
        )
        let zeroFactory = source[zeroFactoryStart..<verifiedFactoryStart]

        let admissionGuard = try #require(
            zeroFactory.range(of: "currentResearchBuildAdmission != nil")
        )
        let liveRoute = try #require(
            zeroFactory.range(of: "return try makeResearchFieldCoordinator()")
        )
        #expect(admissionGuard.lowerBound < liveRoute.lowerBound)
        #expect(!zeroFactory.contains("makeLiveES80Coordinator()"))
        #expect(!zeroFactory.contains("UserDefaults"))
        #expect(!zeroFactory.contains("ProcessInfo"))
    }

    private func packageSourceFile(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func repositorySourceFile(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
