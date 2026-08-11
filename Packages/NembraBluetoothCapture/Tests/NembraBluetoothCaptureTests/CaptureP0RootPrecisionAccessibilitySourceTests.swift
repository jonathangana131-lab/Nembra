import Foundation
import Testing

@Suite("Capture P0 root precision accessibility")
struct CaptureP0RootPrecisionAccessibilitySourceTests {
    @Test("root preserves fail-closed truth while retiring the generic card stack")
    func precisionRootKeepsTruthWithoutCardSoup() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: source,
            from: "private struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController"
        ))

        #expect(root.contains("private var isAccessibilityLayout: Bool"))
        #expect(root.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(root.contains("private func rootSection<Content: View>"))
        #expect(!root.contains("private func rootPanel<Content: View>"))
        #expect(root.contains("Build provenance ready"))
        #expect(root.contains("Physical capture locked"))
        #expect(root.contains("This public build can prepare account metadata, but it cannot scan, connect, or collect physical scooter evidence."))
        #expect(root.contains("This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings."))
        #expect(root.contains("NavigationLink(fieldBuildIsAuthoritative ? \"Continue to preflight\" : \"View locked preflight\")"))
        #expect(root.contains(".accessibilityAddTraits(.isHeader)"))
        #expect(root.contains(".fill(Color.white.opacity(0.14))"))
    }

    @Test("Accessibility setup keeps the labeled QR action ahead of verbose status")
    func accessibilityPrimaryActionPrecedesVerboseStatus() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let account = String(try section(
            in: source,
            from: "private var accountSetupPanel: some View",
            to: "private var statusText: some View"
        ))

        #expect(account.contains("if !isAccessibilityLayout"))
        #expect(account.contains("Text(\"Tuya Smart user code\")"))
        #expect(account.contains("TextField(\"Paste user code\""))
        #expect(account.contains(".frame(minHeight: 52)"))
        #expect(account.contains("Label(\"Create approval QR\", systemImage: \"qrcode\")"))
        #expect(account.contains(".frame(maxWidth: .infinity, minHeight: 50)"))
        #expect(account.contains(".tint(.cyan)"))
        #expect(account.contains(".foregroundStyle(.black)"))
        #expect(account.contains("if isAccessibilityLayout"))

        let action = try #require(account.range(of: "tuya.requestApproval()"))
        let metadata = try #require(account.range(
            of: "This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings.",
            range: action.upperBound..<account.endIndex
        ))
        let status = try #require(account.range(
            of: "statusText",
            range: metadata.upperBound..<account.endIndex
        ))

        #expect(action.lowerBound < metadata.lowerBound)
        #expect(metadata.lowerBound < status.lowerBound)
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
