import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture root large-type hierarchy")
struct CaptureRootLargeTypeHierarchySourceTests {
    // Keep the AX-first-viewport composition mechanically reviewable as the UI evolves.
    // Rendered AX5 pixels remain the acceptance authority; these markers only prevent
    // accidental reintroduction of the rejected three-hero source hierarchy.
    @Test("large type keeps the recovery action ahead of redundant lock branding")
    func largeTypeHierarchy() throws {
        let app = try read("NembraApp/App/NembraCaptureEntrypoint.swift")

        let heroStart = try #require(app.range(of: "private var rootHero"))
        let authorityStart = try #require(
            app.range(of: "private var buildAuthorityStatus", range: heroStart.upperBound..<app.endIndex)
        )
        let accountStart = try #require(
            app.range(of: "private var accountSetupPanel", range: authorityStart.upperBound..<app.endIndex)
        )
        let statusStart = try #require(
            app.range(of: "private var statusText", range: accountStart.upperBound..<app.endIndex)
        )

        let hero = String(app[heroStart.lowerBound..<authorityStart.lowerBound])
        let authority = String(app[authorityStart.lowerBound..<accountStart.lowerBound])
        let account = String(app[accountStart.lowerBound..<statusStart.lowerBound])

        #expect(hero.contains("if !isAccessibilityLayout"))
        #expect(hero.contains("Prepare the scooter link"))
        #expect(!hero.contains("Prepare scooter link"))
        #expect(!hero.contains("Capture locked"))
        #expect(!hero.contains("NEMBRA CAPTURE"))

        #expect(authority.contains("isAccessibilityLayout ? \"Capture locked\" : \"Physical capture locked\""))
        #expect(authority.contains(".font(isAccessibilityLayout ? .body.weight(.semibold) : .headline)"))
        #expect(authority.contains(".dynamicTypeSize(...DynamicTypeSize.accessibility1)"))
        #expect(authority.contains(".padding(.vertical, isAccessibilityLayout ? 2 : 10)"))
        #expect(authority.contains(".accessibilityLabel(fieldBuildIsAuthoritative ? \"Build provenance ready\" : \"Physical capture locked\")"))
        #expect(authority.contains("Bluetooth and physical evidence collection are locked."))

        #expect(account.contains("isAccessibilityLayout ? \"Account setup\" : \"Prepare account metadata\""))
        #expect(account.contains("if !isAccessibilityLayout"))
        #expect(account.contains("TextField(isAccessibilityLayout ? \"Tuya user code\" : \"Paste user code\""))
        #expect(account.contains("Label(isAccessibilityLayout ? \"Create QR\" : \"Create approval QR\""))
        #expect(account.contains(".accessibilityLabel(\"Create approval QR\")"))
        #expect(account.contains("nembra.capture.root.account-link-action"))
        #expect(account.contains("It does not start Bluetooth or physical Capture."))
        #expect(account.contains("if isAccessibilityLayout, tuya.phase != .needsUserCode"))
        #expect(!account.contains("Account setup only in this public build."))

        let field = try #require(account.range(of: "TextField(isAccessibilityLayout ? \"Tuya user code\" : \"Paste user code\""))
        let action = try #require(account.range(of: "Label(isAccessibilityLayout ? \"Create QR\" : \"Create approval QR\""))
        let support = try #require(account.range(
            of: "if isAccessibilityLayout, tuya.phase != .needsUserCode",
            range: action.upperBound..<account.endIndex
        ))
        #expect(field.lowerBound < action.lowerBound)
        #expect(action.lowerBound < support.lowerBound)
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
