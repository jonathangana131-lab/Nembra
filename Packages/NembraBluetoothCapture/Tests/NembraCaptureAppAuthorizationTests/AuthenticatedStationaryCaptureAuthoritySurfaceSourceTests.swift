import Foundation
import Testing
@testable import NembraBluetoothCapture
@testable import NembraCaptureAppAuthorization

@Suite("Authenticated stationary authorization surface")
struct AuthenticatedStationaryCaptureAuthoritySurfaceSourceTests {
    @Test("raw current-application verifier authority is package-only")
    func rawCurrentApplicationVerifierIsNotAnAppCallableBypass() throws {
        let verifier = try source(
            "Sources/NembraBluetoothCapture/AuthenticatedStationaryCaptureFieldAuthorization.swift"
        )

        #expect(verifier.contains("package static func makeCurrentApplicationAttempt("))
        #expect(verifier.contains("package static func verifyForCurrentApplication("))
        #expect(!verifier.contains("public static func makeCurrentApplicationAttempt("))
        #expect(!verifier.contains("public static func verifyForCurrentApplication("))
    }

    @Test("manifest-aware app authorizer remains the public production composition seam")
    func appAuthorizerOwnsPublicProductionComposition() throws {
        let authorizer = try source(
            "Sources/NembraCaptureAppAuthorization/AuthenticatedStationaryCaptureAppAuthorizer.swift"
        )

        #expect(authorizer.contains("public func beginAttempt(\n        installManifestData: Data"))
        #expect(authorizer.contains("public func authorize(\n        envelopeData: Data,"))
        #expect(authorizer.contains("private func beginAttempt(\n        externalBindings:"))
        #expect(authorizer.contains(".makeCurrentApplicationAttempt(externalBindings:"))
        #expect(authorizer.contains(".verifyForCurrentApplication("))
    }

    @Test("app-container transport proof self-triggers when its authority definition moves")
    func appContainerTransportProofPushTriggerCoversItsOwnDefinition() throws {
        let workflow = try repositorySource(
            ".github/workflows/capture-app-container-transport-proof.yml"
        )
        let pushStart = workflow.range(of: "  push:\n")
        let dispatchStart = workflow.range(of: "  workflow_dispatch:\n")

        #expect(pushStart != nil)
        #expect(dispatchStart != nil)
        guard let pushStart, let dispatchStart else { return }
        #expect(pushStart.upperBound <= dispatchStart.lowerBound)
        guard pushStart.upperBound <= dispatchStart.lowerBound else { return }

        let pushBlock = String(workflow[pushStart.upperBound..<dispatchStart.lowerBound])
        #expect(
            pushBlock.contains(
                "      - '.github/workflows/capture-app-container-transport-proof.yml'"
            )
        )
        #expect(
            pushBlock.contains(
                "      - 'scripts/ci/xcode27_devicectl_manifest_transport_contract.sh'"
            )
        )
    }

    private func source(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func repositorySource(_ relativePath: String) throws -> String {
        let fileManager = FileManager.default
        let starts = [
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent(),
        ]

        for start in starts {
            var directory = start.standardizedFileURL
            while true {
                let candidate = directory.appendingPathComponent(relativePath)
                if fileManager.fileExists(atPath: candidate.path) {
                    return try String(contentsOf: candidate, encoding: .utf8)
                }

                let parent = directory.deletingLastPathComponent()
                if parent.path == directory.path { break }
                directory = parent
            }
        }

        throw RepositorySourceError.notFound(relativePath)
    }

    private enum RepositorySourceError: Error {
        case notFound(String)
    }
}
