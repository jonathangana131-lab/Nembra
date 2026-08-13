import Foundation
import Testing

@Test("deadline gate precedes accepted chronology mutation")
func deadlineGatePrecedesAcceptedChronologyMutation() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: root.appendingPathComponent(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        ),
        encoding: .utf8
    )

    let marker = "public func observeCurrentConnection(for token: TuyaReadOnlyConnectionToken) throws {"
    let start = try #require(source.range(of: marker))
    let tail = source[start.lowerBound...]
    let end = try #require(tail.range(of: "\n    /// Seals a failed observation horizon"))
    let body = String(tail[..<end.lowerBound])

    let deadline = try #require(body.range(of: "shouldRetireIncompleteObservation"))
    let mutation = try #require(body.range(of: "latestObservedUptimeNanoseconds = now"))
    #expect(deadline.lowerBound < mutation.lowerBound)
}
