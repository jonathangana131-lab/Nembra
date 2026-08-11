#!/usr/bin/env python3
from pathlib import Path
import subprocess

VISUAL_SOURCE_SHA = "3f085d6b3ebba064f104ba13ab434db04a1769f0"
ENTRYPOINT = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/CaptureP0RootPrecisionLayoutAcceptanceTests.swift")

visual = subprocess.check_output(
    ["git", "show", f"{VISUAL_SOURCE_SHA}:{ENTRYPOINT.as_posix()}"],
    text=True,
)

replacements = {
    '"Field build authority: ready"': '"Build provenance: ready"',
    '"Field build authority: locked"': '"Build provenance: locked"',
    '"Field build ready"': '"Build provenance ready"',
    '"Continue to Capture"': '"Continue to preflight"',
}
for old, new in replacements.items():
    visual = visual.replace(old, new)

heading_anchor = '''            .font(dynamicTypeSize.isAccessibilitySize ? .title2.bold() : .largeTitle.bold())
            .fixedSize(horizontal: false, vertical: true)

            Text(
'''
heading_replacement = '''            .font(dynamicTypeSize.isAccessibilitySize ? .title2.bold() : .largeTitle.bold())
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)

            Text(
'''
if heading_anchor not in visual:
    raise SystemExit("root hero heading anchor missing from reviewed visual source")
visual = visual.replace(heading_anchor, heading_replacement, 1)

combine_anchor = '''        .accessibilityElement(children: .combine)
    }

    private var buildAuthorityStatus: some View {
'''
if combine_anchor not in visual:
    raise SystemExit("root hero combined accessibility anchor missing from reviewed visual source")
visual = visual.replace(
    combine_anchor,
    '''    }

    private var buildAuthorityStatus: some View {
''',
    1,
)

required = [
    'Text(fieldBuildIsAuthoritative ? "Build provenance ready" : "Physical capture locked")',
    '"This public build can prepare account metadata, but it cannot scan, connect, or collect physical scooter evidence."',
    '"This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings."',
    'NavigationLink(fieldBuildIsAuthoritative ? "Continue to preflight" : "View locked preflight")',
    '.accessibilityLabel(fieldBuildIsAuthoritative ? "Build provenance ready" : "Physical capture locked")',
    '.accessibilityAddTraits(.isHeader)',
    'private func rootSection<Content: View>',
    'if !isAccessibilityLayout {',
    'if isAccessibilityLayout {',
    '.frame(maxWidth: .infinity, minHeight: 50)',
    '.tint(.cyan)',
]
for needle in required:
    if needle not in visual:
        raise SystemExit(f"required convergence invariant missing: {needle}")

if 'Text(fieldBuildIsAuthoritative ? "Field build ready"' in visual:
    raise SystemExit("stale field-readiness overclaim remains")
if 'NavigationLink(fieldBuildIsAuthoritative ? "Continue to Capture"' in visual:
    raise SystemExit("stale direct-Capture readiness label remains")

ENTRYPOINT.write_text(visual, encoding="utf-8")

TEST.write_text(r'''import Foundation
import Testing

@Suite("Capture P0 precision root acceptance")
struct CaptureP0RootPrecisionLayoutAcceptanceTests {
    @Test("root keeps build-provenance truth while using the flatter precision hierarchy")
    func truthAndPrecisionHierarchyConverge() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: source,
            from: "private struct CaptureP0Root: View",
            to: "private final class SecureLinkController:"
        ))

        #expect(root.contains("private let buildIdentity = NembraCaptureBuildIdentity.current"))
        #expect(root.contains("buildIdentity.isAuthoritativeFieldBuild"))
        #expect(root.contains("Text(fieldBuildIsAuthoritative ? \"Build provenance ready\" : \"Physical capture locked\")"))
        #expect(root.contains("This public build can prepare account metadata, but it cannot scan, connect, or collect physical scooter evidence."))
        #expect(root.contains("NavigationLink(fieldBuildIsAuthoritative ? \"Continue to preflight\" : \"View locked preflight\")"))
        #expect(root.contains("private func rootSection<Content: View>"))
        #expect(!root.contains("private func rootPanel<Content: View>"))
        #expect(root.contains("LinearGradient("))
        #expect(root.contains("Color.white.opacity(0.14)"))
        #expect(root.contains(".accessibilityAddTraits(.isHeader)"))

        let hero = String(try section(in: root, from: "private var rootHero: some View", to: "private var buildAuthorityStatus: some View"))
        #expect(!hero.contains(".accessibilityElement(children: .combine)"))
    }

    @Test("Accessibility first fold puts the account action before verbose support copy")
    func accessibilityFirstFoldIsActionable() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: source,
            from: "private struct CaptureP0Root: View",
            to: "private final class SecureLinkController:"
        ))
        let panel = String(try section(
            in: root,
            from: "private var accountSetupPanel: some View",
            to: "private var statusText: some View"
        ))

        let field = try #require(panel.range(of: "TextField(\"Paste user code\""))
        let action = try #require(panel.range(of: "Label(\"Create approval QR\"", range: field.upperBound..<panel.endIndex))
        let fullWidth = try #require(panel.range(of: ".frame(maxWidth: .infinity, minHeight: 50)", range: action.upperBound..<panel.endIndex))
        let accessibilitySupport = try #require(panel.range(of: "if isAccessibilityLayout {", range: fullWidth.upperBound..<panel.endIndex))
        let metadataCopy = try #require(panel.range(of: "This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings.", range: accessibilitySupport.upperBound..<panel.endIndex))
        #expect(field.lowerBound < action.lowerBound)
        #expect(action.lowerBound < accessibilitySupport.lowerBound)
        #expect(accessibilitySupport.lowerBound < metadataCopy.lowerBound)
        #expect(panel.contains(".tint(.cyan)"))

        let standardSupport = try #require(panel.range(of: "if !isAccessibilityLayout {"))
        let firstMetadataCopy = try #require(panel.range(of: "This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings.", range: standardSupport.upperBound..<field.lowerBound))
        #expect(standardSupport.lowerBound < firstMetadataCopy.lowerBound)
        #expect(firstMetadataCopy.lowerBound < field.lowerBound)
    }

    @Test("Accessibility public lock is compact but remains explicit")
    func accessibilityLockRemainsTruthful() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: source,
            from: "private struct CaptureP0Root: View",
            to: "private final class SecureLinkController:"
        ))
        let status = String(try section(
            in: root,
            from: "private var buildAuthorityStatus: some View",
            to: "private var accountSetupPanel: some View"
        ))

        #expect(status.contains("Public build: account metadata only. Bluetooth and physical evidence stay locked."))
        #expect(status.contains("Build provenance ready"))
        #expect(status.contains("Physical capture locked"))
        #expect(status.contains("Build provenance is ready. Account and scooter authority are still required before Bluetooth starts."))
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
''', encoding="utf-8")

for path in [
    Path("scripts/ci/v14_materialize_capture_precision_truth.py"),
    Path(".github/workflows/v14-capture-precision-truth-bootstrap.yml"),
]:
    if path.exists():
        path.unlink()

print("Materialized current-parent Capture precision/truth convergence and removed bootstrap files.")
