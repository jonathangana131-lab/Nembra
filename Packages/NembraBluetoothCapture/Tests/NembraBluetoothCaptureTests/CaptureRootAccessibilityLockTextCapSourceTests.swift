import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture root accessibility lock-text cap")
struct CaptureRootAccessibilityLockTextCapSourceTests {
    @Test("accessibility lock banner caps the text itself, not only its icon")
    func lockTextHasItsOwnAccessibilityCap() throws {
        let app = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authorityStart = try #require(app.range(of: "private var buildAuthorityStatus"))
        let accountStart = try #require(
            app.range(of: "private var accountSetupPanel", range: authorityStart.upperBound..<app.endIndex)
        )
        let authority = String(app[authorityStart.lowerBound..<accountStart.lowerBound])

        let lockLiteral = try #require(authority.range(of: "isAccessibilityLayout ? \"Capture locked\" : \"Physical capture locked\""))
        let textStart = try #require(
            authority.range(of: "Text(", options: .backwards, range: authority.startIndex..<lockLiteral.lowerBound)
        )
        let foreground = try #require(
            authority.range(of: ".foregroundStyle", range: lockLiteral.upperBound..<authority.endIndex)
        )
        let lockTextChain = String(authority[textStart.lowerBound..<foreground.lowerBound])

        // The icon has its own cap. That must not satisfy this text-specific contract:
        // AX5 must retain hierarchy instead of letting the redundant lock banner become
        // a two-line hero that pushes the recovery action down the first viewport.
        #expect(lockTextChain.contains(".font(isAccessibilityLayout ? .body.weight(.semibold) : .headline)"))
        #expect(lockTextChain.contains(".dynamicTypeSize(...DynamicTypeSize.accessibility1)"))
    }

    private func read(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
