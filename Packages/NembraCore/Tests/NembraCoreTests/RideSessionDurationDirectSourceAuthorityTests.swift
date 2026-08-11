import Foundation
import Testing

@Test("Ride duration producer authority stays package-scoped in SwiftPM and file-private in direct-source builds")
func rideDurationProducerAuthorityBuildModeFence() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Packages/NembraCore/Sources/NembraCore/RideSessionDurationEvidence.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(source.contains("#if SWIFT_PACKAGE\n    /// Package tests and package-owned producers may construct snapshots directly."))
    #expect(source.contains("package init(\n        sessionID: UUID,\n        observedDurationNanoseconds: UInt64?"))
    #expect(source.contains("#else\n    /// Direct-source app builds keep snapshot minting in this file"))
    #expect(source.contains("fileprivate init(\n        sessionID: UUID,\n        observedDurationNanoseconds: UInt64?"))

    #expect(source.contains("package var snapshot: RideSessionDurationEvidenceSnapshot"))
    #expect(source.contains("fileprivate var snapshot: RideSessionDurationEvidenceSnapshot"))
    #expect(source.contains("private var projectedSnapshot: RideSessionDurationEvidenceSnapshot"))

    #expect(source.contains("package mutating func upsert("))
    #expect(source.contains("fileprivate mutating func upsert("))
    #expect(source.contains("private mutating func upsertValidated("))
    #expect(source.contains("try upsertValidated(segment)"))

    #expect(source.contains("package init(\n        sessionID: UUID,\n        beginsAfterUnobservedInterval: Bool = false"))
    #expect(source.contains("fileprivate init(\n        sessionID: UUID,\n        beginsAfterUnobservedInterval: Bool = false"))
}
