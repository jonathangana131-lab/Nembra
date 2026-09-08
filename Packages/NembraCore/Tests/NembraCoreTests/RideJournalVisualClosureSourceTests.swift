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
            "rides.completed-row",
            "rides.history",
        ] {
            #expect(history.contains("accessibilityIdentifier(\"\(identifier)\")"))
        }

        // Empty and error states flow through journalStateSurface so the identifier
        // is supplied at the call site and applied by the shared helper. Pin both
        // halves of that contract instead of requiring a direct modifier literal.
        for identifier in ["rides.empty", "rides.error"] {
            #expect(history.contains("identifier: \"\(identifier)\""))
        }
        #expect(history.contains(".accessibilityIdentifier(identifier)"))

        #expect(history.contains("accessibilityReduceTransparency"))
        #expect(history.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(history.contains("journalStateSurface"))
    }

    @Test("Ride records stay fail closed for unverified live scooter telemetry semantics")
    func rideRecordsDoNotPromoteUnverifiedTelemetrySemantics() throws {
        let source = try String(contentsOf: appRootViewURL, encoding: .utf8)
        let history = try scopedSource(
            source,
            from: "private struct RideHistoryView: View",
            until: "private struct RideRouteMapView: View"
        )

        // Until authenticated physical payload evidence establishes actual DP meaning,
        // the ride journal may present only evidence it truly owns: timestamps,
        // quality-screened GPS geometry/distance, and an already-recorded odometer delta.
        // It must not grow convenient-looking battery/speed/control telemetry merely
        // because those concepts exist elsewhere in the product or simulator.
        for forbiddenPresentation in [
            "Battery",
            "BATTERY",
            "Top speed",
            "TOP SPEED",
            "Ride mode",
            "RIDE MODE",
            "Headlight",
            "HEADLIGHT",
            "Brake",
            "BRAKE",
            "Power",
            "POWER",
        ] {
            #expect(!history.contains("Text(\"\(forbiddenPresentation)\")"))
            #expect(!history.contains("title: \"\(forbiddenPresentation)\""))
            #expect(!history.contains("label: \"\(forbiddenPresentation)\""))
        }

        #expect(history.contains("Verified rides, kept with their evidence."))
        #expect(history.contains("Verified rides will appear here once Nembra can safely record accepted live scooter evidence."))
        #expect(history.contains("Scooter odometer and GPS distance stay separate"))
        #expect(history.contains("qualityScreenedGPSDistanceMeters"))
        #expect(history.contains("startingOdometerKilometers"))
        #expect(history.contains("endingOdometerKilometers"))
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