import Foundation
import Testing

@Suite("ES80 Capture Details Dynamic Type source acceptance")
struct ES80CaptureDetailsDynamicTypeSourceAcceptanceTests {
    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func shellSource() throws -> String {
        try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("Features")
                .appendingPathComponent("Research")
                .appendingPathComponent("ES80CaptureShellView.swift"),
            encoding: .utf8
        )
    }

    @Test("Capture Details engineering rows deliberately recompose at accessibility sizes")
    func detailsRowsRecomposeForAccessibilitySizes() throws {
        let source = try Self.shellSource()

        let detailRowStart = try #require(source.range(of: "private func detailRow(_ title: String, value: String)"))
        let followingFunction = try #require(
            source.range(
                of: "private func digestDetailRow",
                range: detailRowStart.upperBound..<source.endIndex
            )
        )
        let detailRowSource = String(source[detailRowStart.lowerBound..<followingFunction.lowerBound])

        #expect(
            detailRowSource.contains("dynamicTypeSize.isAccessibilitySize"),
            "Capture Details contains long build/session/procedure values. Its ordinary label/value row must deliberately switch away from a single horizontal HStack at accessibility sizes instead of squeezing or clipping engineering truth."
        )

        let hasVerticalComposition = detailRowSource.contains("VStack")
            || detailRowSource.contains("AnyLayout")
            || detailRowSource.contains("ViewThatFits")

        #expect(
            hasVerticalComposition,
            "At accessibility sizes the detail label and value should recompose vertically or through an equivalent adaptive layout, preserving full readable values rather than shrinking them."
        )
    }

    @Test("Capture Details values remain selectable and are not scale-factor compressed")
    func detailsValuesPreserveReadableTruth() throws {
        let source = try Self.shellSource()

        let detailRowStart = try #require(source.range(of: "private func detailRow(_ title: String, value: String)"))
        let followingFunction = try #require(
            source.range(
                of: "private func digestDetailRow",
                range: detailRowStart.upperBound..<source.endIndex
            )
        )
        let detailRowSource = String(source[detailRowStart.lowerBound..<followingFunction.lowerBound])

        #expect(detailRowSource.contains(".textSelection(.enabled)"))
        #expect(
            !detailRowSource.contains("minimumScaleFactor"),
            "Engineering values must wrap/recompose at large text rather than becoming tiny to preserve a compact row."
        )
    }

    @Test("Details accessibility layout cannot alter capture or field authority")
    func detailsLayoutStaysPresentationOnly() throws {
        let source = try Self.shellSource()

        #expect(source.contains("PassiveBluetoothExperimentOneCoordinator"))
        #expect(source.contains("physicalProcedureLocked"))
        #expect(source.contains("Truth boundary"))
        #expect(!source.contains("dynamicTypeSize.isAccessibilitySize && coordinator"))
        #expect(!source.contains("dynamicTypeSize.isAccessibilitySize && presentationAnalysisReady"))
    }
}
