import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture accepted export envelope immutability")
struct TuyaAcceptedExportEnvelopeSealSourceTests {
    @Test("accepted export freezes acceptance-bound metadata instead of rereading live SDK state")
    func acceptedExportUsesSealedEnvelopeSnapshot() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(
            in: app,
            from: "private final class SecureLinkController",
            to: "private protocol OfficialTuyaDriver"
        )
        let acceptance = try section(
            in: controller,
            from: "try await sessionLedger.sealAcceptedObservation(for: token)",
            to: "self.phase = .accepted"
        )
        let export = try section(
            in: controller,
            from: "func prepareExport()",
            to: "private func resetDiscoverySessionOnly()"
        )

        #expect(
            controller.contains("sealedAcceptedExportSnapshot"),
            Comment(rawValue: "Freezing only the event array is insufficient: accepted account/membership/local-BLE fields are still read from mutable controller state during export.")
        )
        #expect(
            acceptance.contains("sealedAcceptedExportSnapshot"),
            Comment(rawValue: "The complete acceptance-bound export snapshot must be captured synchronously after the package seal and before UI acceptance.")
        )
        #expect(
            export.contains("sealedAcceptedExportSnapshot"),
            Comment(rawValue: "An accepted export must serialize the sealed acceptance snapshot rather than re-read mutable post-seal SDK/controller state.")
        )
    }

    @Test("post-seal SDK logout can mutate live membership without changing the already-sealed accepted phase")
    func acceptedArtifactCannotDependOnLiveMembershipFields() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let invalidation = try section(
            in: app,
            from: "func invalidateSDKMembership()",
            to: "func verifySDKMembership"
        )
        let export = try section(
            in: app,
            from: "func prepareExport()",
            to: "private func resetDiscoverySessionOnly()"
        )

        #expect(invalidation.contains("sdkDeviceMembershipVerified = false"))
        #expect(!invalidation.contains(".accepted].contains(phase)"))
        #expect(export.contains("sdkAccountLoggedIn:"))
        #expect(export.contains("sdkDeviceMembershipVerified:"))
        #expect(
            export.contains("sealedAcceptedExportSnapshot"),
            Comment(rawValue: "Because live SDK/membership fields can change after seal, accepted export authority must come from a frozen snapshot, not those live properties.")
        )
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
