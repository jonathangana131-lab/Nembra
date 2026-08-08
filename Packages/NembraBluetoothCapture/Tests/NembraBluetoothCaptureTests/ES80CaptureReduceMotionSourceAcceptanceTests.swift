import Foundation
import Testing

@Suite("ES80 Capture Reduce Motion source acceptance")
struct ES80CaptureReduceMotionSourceAcceptanceTests {
    private static func shellSource() throws -> String {
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
                .appendingPathComponent("Features")
                .appendingPathComponent("Research")
                .appendingPathComponent("ES80CaptureShellView.swift"),
            encoding: .utf8
        )
    }

    @Test("Capture explicitly respects Reduce Motion for continuous activity indicators")
    func captureHasReduceMotionAwareActivityTreatment() throws {
        let source = try Self.shellSource()

        // The shell intentionally avoids custom animations, but it still uses indeterminate
        // ProgressView spinners in several long-running rider states. Reduce Motion must therefore
        // be an explicit product decision rather than relying on undocumented/default spinner
        // behavior. The reduced-motion branch should preserve the same truthful text/state while
        // replacing continuous decorative motion with a restrained static activity cue.
        #expect(source.contains("@Environment(\\.accessibilityReduceMotion)"))
        #expect(source.contains("accessibilityReduceMotion"))
        #expect(
            source.contains("reduceMotionActivityIndicator")
                || source.contains("motionSafeActivityIndicator")
                || source.contains("if accessibilityReduceMotion"),
            "Capture needs an explicit reduced-motion activity presentation instead of unconditional indeterminate spinners."
        )
    }

    @Test("Reduce Motion treatment cannot alter capture authority")
    func reducedMotionStaysPresentationOnly() throws {
        let source = try Self.shellSource()

        let forbiddenAuthorityCoupling = [
            "accessibilityReduceMotion && coordinator",
            "accessibilityReduceMotion ? coordinator",
            "accessibilityReduceMotion && PassiveBluetooth",
            "accessibilityReduceMotion ? PassiveBluetooth"
        ]

        for coupling in forbiddenAuthorityCoupling {
            #expect(!source.contains(coupling))
        }

        #expect(source.contains("TimelineView(.periodic("))
        #expect(source.contains("static let statusPollInterval: TimeInterval = 0.5"))
    }
}
