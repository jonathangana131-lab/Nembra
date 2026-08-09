import Foundation
import Testing

@Suite("ES80 Capture locked-surface visual acceptance")
struct ES80CaptureLockedSurfaceVisualAcceptanceTests {
    private static func appSource() throws -> String {
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
                .appendingPathComponent("App")
                .appendingPathComponent("NembraApp.swift"),
            encoding: .utf8
        )
    }

    private static func engineeringDetailsControl(in source: String) throws -> Substring {
        let label = try #require(source.range(of: "Text(\"Engineering details\")"))
        let identifier = try #require(
            source.range(
                of: ".accessibilityIdentifier(\"es80.capture.engineering-details\")",
                range: label.lowerBound..<source.endIndex
            )
        )
        return source[label.lowerBound..<identifier.upperBound]
    }

    @Test("locked rider surface keeps exact engineering truth subordinate to the primary lock")
    func riderHierarchyRemainsHumanFirst() throws {
        let source = try Self.appSource()
        let lockedSurfaceStart = try #require(
            source.range(of: "private struct ES80ExperimentOneFieldNoGoView: View")
        )
        let lockedSurface = source[lockedSurfaceStart.lowerBound..<source.endIndex]
        let lockTitle = try #require(lockedSurface.range(of: "Text(\"Capture locked\")"))
        let accessibilityRiderMessage = try #require(
            lockedSurface.range(of: "\"Final exact-build checks are still in progress.\"")
        )
        let defaultRiderMessage = try #require(
            lockedSurface.range(of: "\"This build is still finishing its final checks before it can collect real ES80 data.\"")
        )
        let physicalBoundary = try #require(
            lockedSurface.range(of: ".accessibilityIdentifier(\"es80.capture.physical-run-locked\")")
        )
        let details = try #require(lockedSurface.range(of: "Text(\"Engineering details\")"))
        let rawRecipe = try #require(lockedSurface.range(of: "Text(recipeID)"))

        #expect(lockTitle.lowerBound < accessibilityRiderMessage.lowerBound)
        #expect(accessibilityRiderMessage.lowerBound < defaultRiderMessage.lowerBound)
        #expect(defaultRiderMessage.lowerBound < physicalBoundary.lowerBound)
        #expect(physicalBoundary.lowerBound < details.lowerBound)
        #expect(details.lowerBound < rawRecipe.lowerBound)
        #expect(lockedSurface.contains("if engineeringDetailsExpanded"))
        #expect(lockedSurface.contains("Software evidence only. This does not verify a physical ES80 or unlock scooter controls."))
    }

    @Test("Engineering Details disclosure has a full-width explicit 44-point minimum hit target")
    func engineeringDetailsMeetsMinimumHitTarget() throws {
        let source = try Self.appSource()
        let control = try Self.engineeringDetailsControl(in: source)

        #expect(control.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(control.contains(".contentShape(Rectangle())"))
        #expect(
            control.contains(".frame(minHeight: 44)")
                || control.contains(".frame(minHeight: 50)")
                || control.contains(".frame(minHeight: 56)"),
            "The only interactive control on the locked rider surface must explicitly preserve at least a 44pt tap target, including at large Dynamic Type sizes."
        )
        #expect(control.contains(".accessibilityValue(engineeringDetailsExpanded ? \"Expanded\" : \"Collapsed\")"))
        #expect(control.contains(".accessibilityHint("))
    }

    @Test("locked surface preserves wrapping and off-main build identity measurement")
    func lockCopyAndBuildIdentityStayLegibleAndResponsive() throws {
        let source = try Self.appSource()

        #expect(source.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(source.contains("Task.detached(priority: .utility)"))
        #expect(source.contains("guard !Task.isCancelled else { return }"))
        #expect(source.contains(".accessibilityIdentifier(\"es80.capture.build-identity\")"))
        #expect(source.contains(".accessibilityIdentifier(\"es80.capture.field-no-go\")"))
    }
}
