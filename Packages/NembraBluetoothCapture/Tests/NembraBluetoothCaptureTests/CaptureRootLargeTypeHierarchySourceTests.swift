import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture root large-type hierarchy")
struct CaptureRootLargeTypeHierarchySourceTests {
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

        #expect(hero.contains("Prepare scooter link"))
        #expect(!hero.contains("Capture locked"))
        #expect(!hero.contains("NEMBRA CAPTURE"))

        #expect(authority.contains("Physical capture locked"))
        #expect(authority.contains(".font(isAccessibilityLayout ? .subheadline.weight(.semibold) : .headline)"))
        #expect(authority.contains(".padding(.vertical, isAccessibilityLayout ? 4 : 10)"))
        #expect(authority.contains("Bluetooth and physical evidence collection are locked."))

        #expect(account.contains("Set up account metadata"))
        #expect(account.contains("nembra.capture.root.account-link-action"))
        #expect(account.contains("It does not start Bluetooth or physical Capture."))
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
