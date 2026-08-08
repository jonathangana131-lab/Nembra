import Foundation
import Testing

@Suite("Experiment One admission staging preview")
struct PassiveBluetoothExperimentOneAdmissionStagingPreviewTests {
    private static func runSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("PassiveBluetoothExperimentOneRun.swift"),
            encoding: .utf8
        )
    }

    @Test("staging preview is package-only, read-only, and producer-constructed")
    func previewSurfaceCannotMintAdmissionAuthority() throws {
        let source = try Self.runSource()
        let admissionStart = try #require(
            source.range(of: "final class PassiveBluetoothExperimentOneCaptureAdmission")?.lowerBound
        )
        let runStart = try #require(
            source.range(of: "\n@MainActor\nfinal class PassiveBluetoothExperimentOneRun", range: admissionStart..<source.endIndex)?.lowerBound
        )
        let admission = source[admissionStart..<runStart]

        #expect(admission.contains("struct StagingPreview"))
        #expect(admission.contains("fileprivate init("))
        #expect(admission.contains("let admissionIdentity: UUID"))
        #expect(admission.contains("let peripheralIdentifier: UUID"))
        #expect(admission.contains("let issuedAtUptimeNanoseconds: UInt64"))
        #expect(!admission.contains("public struct StagingPreview"))
        #expect(!admission.contains("public func stagingPreview"))
    }

    @Test("preview does not consume and cannot be read after the one-shot burns")
    func previewPreservesOneShotBoundary() throws {
        let source = try Self.runSource()
        let start = try #require(source.range(of: "func stagingPreview() throws -> StagingPreview")?.lowerBound)
        let end = try #require(source.range(of: "\n    func consume() throws -> Payload", range: start..<source.endIndex)?.lowerBound)
        let preview = source[start..<end]

        #expect(preview.contains("guard !hasBeenConsumed"))
        #expect(preview.contains("throw ConsumptionError.alreadyConsumed"))
        #expect(preview.contains("admissionIdentity: payload.admissionIdentity"))
        #expect(preview.contains("peripheralIdentifier: payload.peripheralIdentifier"))
        #expect(preview.contains("issuedAtUptimeNanoseconds: payload.issuedAtUptimeNanoseconds"))
        #expect(!preview.contains("hasBeenConsumed = true"))
        #expect(!preview.contains("recorder"))
        #expect(!preview.contains("powerCycleEvidence"))
    }

    @Test("preview and consumed payload share exact producer identity and chronology fields")
    func previewFieldsComeOnlyFromSealedPayload() throws {
        let source = try Self.runSource()
        let previewTypeStart = try #require(source.range(of: "struct StagingPreview")?.lowerBound)
        let payloadStart = try #require(source.range(of: "\n    struct Payload", range: previewTypeStart..<source.endIndex)?.lowerBound)
        let previewType = source[previewTypeStart..<payloadStart]

        #expect(previewType.contains("fileprivate init("))
        #expect(previewType.contains("admissionIdentity: UUID"))
        #expect(previewType.contains("peripheralIdentifier: UUID"))
        #expect(previewType.contains("issuedAtUptimeNanoseconds: UInt64"))
        #expect(!previewType.contains("PassiveCoreBluetoothCaptureRecorder"))
        #expect(!previewType.contains("PassiveBluetoothExperimentOnePowerCycleEvidence"))
    }
}
