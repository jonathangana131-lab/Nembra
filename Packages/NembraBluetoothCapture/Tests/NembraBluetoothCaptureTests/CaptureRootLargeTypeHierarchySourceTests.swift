import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture root large-type hierarchy")
struct CaptureRootLargeTypeHierarchySourceTests {
    @Test("large type keeps authority and the shortest safe action ahead of recovery details")
    func largeTypeHierarchy() throws {
        let app = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: app,
            from: "@MainActor\nprivate struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController:"
        ))

        let heroStart = try #require(root.range(of: "private var rootHero"))
        let authorityStart = try #require(
            root.range(of: "private var buildAuthorityStatus", range: heroStart.upperBound..<root.endIndex)
        )
        let accountStart = try #require(
            root.range(of: "private var accountSetupPanel", range: authorityStart.upperBound..<root.endIndex)
        )
        let chooserStart = try #require(
            root.range(of: "private var scooterChooserPanel", range: accountStart.upperBound..<root.endIndex)
        )

        let hero = String(root[heroStart.lowerBound..<authorityStart.lowerBound])
        let authority = String(root[authorityStart.lowerBound..<accountStart.lowerBound])
        let account = String(root[accountStart.lowerBound..<chooserStart.lowerBound])

        #expect(hero.contains("if !isAccessibilityLayout"))
        #expect(hero.contains("Link your scooter"))
        #expect(!hero.contains("Capture locked"))
        #expect(!hero.contains("NEMBRA CAPTURE"))

        #expect(authority.contains("Text(fieldBuildIsAuthoritative ? \"Field build ready\" : \"Capture locked\")"))
        #expect(authority.contains(".font(isAccessibilityLayout ? .body.weight(.semibold) : .headline)"))
        #expect(authority.contains(".dynamicTypeSize(...DynamicTypeSize.accessibility1)"))
        #expect(authority.contains(".padding(isAccessibilityLayout ? 12 : 14)"))
        #expect(authority.contains(".accessibilityLabel(fieldBuildIsAuthoritative ? \"Field build ready\" : \"Physical capture locked\")"))
        #expect(authority.contains("This public build cannot authorize Bluetooth or collect physical evidence."))

        #expect(account.contains("Text(sdkAccount.loggedIn ? \"Scooter account linked\" : \"Link scooter account\")"))
        #expect(account.contains("if !fieldBuildIsAuthoritative"))
        #expect(account.contains("Review field requirements"))
        #expect(account.contains("nembra.capture.root.account-link-action"))
        #expect(account.contains("SignInWithAppleButton(.signIn)"))
        #expect(account.contains("Use email or phone instead"))
        #expect(!account.contains("Tuya user code"))
        #expect(!account.contains("Create approval QR"))

        let publicAction = try #require(account.range(of: "Label(\"Review field requirements\""))
        let loggedIn = try #require(account.range(of: "} else if sdkAccount.loggedIn {", range: publicAction.upperBound..<account.endIndex))
        let apple = try #require(account.range(of: "SignInWithAppleButton(.signIn)", range: loggedIn.upperBound..<account.endIndex))
        let alternative = try #require(account.range(of: "DisclosureGroup(\"Use email or phone instead\"", range: apple.upperBound..<account.endIndex))
        #expect(publicAction.lowerBound < loggedIn.lowerBound)
        #expect(loggedIn.lowerBound < apple.lowerBound)
        #expect(apple.lowerBound < alternative.lowerBound)
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
