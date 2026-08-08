import Foundation
import Testing

@Suite("Experiment One admission staging preview")
struct PassiveBluetoothExperimentOneCaptureAdmissionPreviewTests {
    @Test("preview exposes only immutable producer identity target and issuance chronology")
    func previewDoesNotExposeRecorderOrEvidence() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneRun.swift"), encoding: .utf8)
        let start = try #require(source.range(of: "struct TargetPreview: Equatable, Sendable"))
        let end = try #require(source.range(of: "\n    struct Payload", range: start.lowerBound..<source.endIndex))
        let preview = String(source[start.lowerBound..<end.lowerBound])
        #expect(preview.contains("let admissionIdentity: UUID"))
        #expect(preview.contains("let peripheralIdentifier: UUID"))
        #expect(preview.contains("let issuedAtUptimeNanoseconds: UInt64"))
        #expect(!preview.contains("recorder:"))
        #expect(!preview.contains("powerCycleEvidence:"))
    }
}
