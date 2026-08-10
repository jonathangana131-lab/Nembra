import Foundation
import Testing

@Suite("ES80 Capture locked-surface visual acceptance")
struct ES80CaptureLockedSurfaceVisualAcceptanceTests {
    private static func captureShellSource() throws -> String {
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

    private static func lockedStateBranch(in source: String) throws -> Substring {
        let start = try #require(source.range(of: "case .physicalProcedureLocked:"))
        let end = try #require(
            source.range(
                of: "case let .bluetoothUnavailable(message):",
                range: start.upperBound..<source.endIndex
            )
        )
        return source[start.lowerBound..<end.lowerBound]
    }

    @Test("locked rider surface stays human-first and truth-subordinate")
    func riderHierarchyRemainsHumanFirst() throws {
        let source = try Self.captureShellSource()
        let lockedState = try Self.lockedStateBranch(in: source)

        #expect(lockedState.contains("eyebrow: \"CAPTURE LOCKED\""))
        #expect(lockedState.contains("title: \"This build is not ready for a field capture\""))
        #expect(
            lockedState.contains(
                "Field capture is locked for this build. OFF / ON checks, connection, capture, and sealing stay unavailable until this exact build is authorized."
            )
        )
        #expect(lockedState.contains("symbol: \"lock.shield.fill\""))

        let detailsStart = try #require(source.range(of: "private var captureDetailsSheet: some View"))
        let details = source[detailsStart.lowerBound..<source.endIndex]
        #expect(details.contains("Text(\"Truth boundary\")"))
        #expect(details.contains("This artifact is passive software evidence."))
        #expect(details.contains("it does not authenticate the physical ES80"))
        #expect(details.contains("This screen does not assign GATT, Tuya/DP, battery, current, power, speed, regen, or command semantics."))
    }

    @Test("physical lock exposes no actionable capture control before authority")
    func physicalLockHasNoInteractiveBypass() throws {
        let source = try Self.captureShellSource()
        let lockedState = try Self.lockedStateBranch(in: source)

        #expect(!lockedState.contains("primaryButton("))
        #expect(!lockedState.contains("secondaryButton("))
        #expect(!lockedState.contains("NavigationLink("))
        #expect(!lockedState.contains("ShareLink("))

        let gate = try #require(source.range(of: "guard status.physicalProcedurePermitted else {"))
        let lockedReturn = try #require(
            source.range(
                of: "return .physicalProcedureLocked",
                range: gate.lowerBound..<source.endIndex
            )
        )
        let foregroundCheck = try #require(
            source.range(
                of: "if status.foregroundIntegrityLost",
                range: lockedReturn.upperBound..<source.endIndex
            )
        )
        #expect(gate.lowerBound < lockedReturn.lowerBound)
        #expect(lockedReturn.lowerBound < foregroundCheck.lowerBound)
    }

    @Test("locked shell preserves accessible wrapping and explicit product identity")
    func lockCopyAndAccessibilityStayLegible() throws {
        let source = try Self.captureShellSource()

        #expect(source.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
        #expect(source.contains("@Environment(\\.accessibilityReduceMotion) private var accessibilityReduceMotion"))
        #expect(source.contains("@Environment(\\.accessibilityReduceTransparency) private var accessibilityReduceTransparency"))
        #expect(source.contains("@Environment(\\.accessibilityDifferentiateWithoutColor) private var accessibilityDifferentiateWithoutColor"))
        #expect(source.contains("if dynamicTypeSize.isAccessibilitySize"))
        #expect(source.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(source.contains(".accessibilityIdentifier(\"es80.capture-shell\")"))
        #expect(source.contains(".navigationTitle(\"Nembra Capture\")"))
        #expect(source.contains(".sheet(isPresented: $showingDetails)"))
    }
}
