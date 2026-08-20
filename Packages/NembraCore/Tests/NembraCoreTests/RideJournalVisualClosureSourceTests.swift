import Foundation
import Testing

@Suite("Ride journal visual closure source")
struct RideJournalVisualClosureSourceTests {
    @Test("Rides is a dedicated journal surface instead of a generic List archive")
    func rideJournalOwnsItsPrimarySurface() throws {
        let source = try String(contentsOf: appRootViewURL, encoding: .utf8)
        let history = try scopedSource(
            source,
            from: "private struct RideHistoryView: View",
            until: "private struct RideHistoryRowView: View"
        )

        #expect(history.contains("ScrollView {"))
        #expect(history.contains("LazyVStack(alignment: .leading"))
        #expect(history.contains("Text(\"RIDE JOURNAL\")"))
        #expect(history.contains("accessibilityIdentifier(\"rides.journal-header\")"))
        #expect(history.contains("accessibilityIdentifier(\"rides.history\")"))
        #expect(history.contains(".refreshable"))
        #expect(!history.contains("List {"))
        #expect(!history.contains("ContentUnavailableView("))
    }

    @Test("Journal preserves source-separated distance evidence and truthful unavailable state")
    func journalKeepsDistanceSourcesDistinct() throws {
        let source = try String(contentsOf: appRootViewURL, encoding: .utf8)
        let row = try scopedSource(
            source,
            from: "private struct RideHistoryRowView: View",
            until: "private struct RideHistoryDetailView: View"
        )

        #expect(row.contains("startingOdometerKilometers"))
        #expect(row.contains("endingOdometerKilometers"))
        #expect(row.contains("qualityScreenedGPSDistanceMeters"))
        #expect(row.contains("Text(\"SCOOTER\")") || row.contains("label: \"SCOOTER\""))
        #expect(row.contains("label: \"GPS\""))
        #expect(row.contains("Text(\"Unavailable\")"))
        #expect(row.contains("scooter distance"))
        #expect(row.contains("GPS recorded distance"))
    }

    @Test("Journal states are custom, reachable, and retain established UI identifiers")
    func journalStatesRemainAutomationAndAccessibilityStable() throws {
        let source = try String(contentsOf: appRootViewURL, encoding: .utf8)
        let history = try scopedSource(
            source,
            from: "private struct RideHistoryView: View",
            until: "private struct RideHistoryRowView: View"
        )

        for identifier in [
            "rides.loading",
            "rides.empty",
            "rides.error",
            "rides.completed-row",
            "rides.history",
        ] {
            #expect(history.contains("accessibilityIdentifier(\"\(identifier)\")"))
        }

        #expect(history.contains("accessibilityReduceTransparency"))
        #expect(history.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(history.contains("journalStateSurface"))
    }

    private func scopedSource(_ source: String, from startMarker: String, until endMarker: String) throws -> String {
        let start = try #require(source.range(of: startMarker))
        let end = try #require(source.range(of: endMarker, range: start.upperBound..<source.endIndex))
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private var appRootViewURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NembraApp/App/AppRootView.swift")
    }
}
