import Foundation
import Testing

@Suite("Ride window Navigation clearance source")
struct RideWindowNavigationClearanceSourceTests {
    @Test("Normal-size Ride Window timestamps reserve the persistent Navigation launcher footprint")
    func rideWindowReservesNavigationLauncherFootprint() throws {
        let source = try String(contentsOf: appRootViewURL, encoding: .utf8)

        let timelineStart = try #require(source.range(of: "private func timelineRow(title: String, date: Date) -> some View"))
        let recordingStart = try #require(
            source.range(
                of: "private func recordingDetailRow(_ title: String, value: String) -> some View",
                range: timelineStart.upperBound..<source.endIndex
            )
        )
        let timelineSource = String(source[timelineStart.lowerBound..<recordingStart.lowerBound])

        #expect(
            timelineSource.contains(".padding(.trailing, 72)"),
            "The retained Ride detail witness shows navigation.launch covering the Ended timestamp. Reserve the 54 pt launcher + 18 pt trailing footprint locally in Ride Window rows instead of shrinking text or moving global Navigation."
        )
        #expect(
            timelineSource.contains("Text(title)")
                && timelineSource.contains("Text(timestamp(date))")
                && timelineSource.components(separatedBy: "Text(title)").count == 2
                && timelineSource.components(separatedBy: "Text(timestamp(date))").count == 2
                && timelineSource.contains(".font(.subheadline.weight(.medium))")
                && timelineSource.contains(".font(.subheadline.monospacedDigit())")
                && timelineSource.contains("VStack(alignment: .leading, spacing: 4)")
                && !timelineSource.contains("ViewThatFits(")
                && !timelineSource.contains(".accessibilityLabeledPair(")
                && !timelineSource.contains(".accessibilityElement(children: .ignore)")
                && !timelineSource.contains(".accessibilityElement(children: .combine)"),
            "Ride Window rows must expose one native semantic-font Text pair in title-then-timestamp order. Duplicate ViewThatFits candidates and synthetic combined, ignored, or labeled-pair nodes caused alternating Xcode 27 Dynamic Type and hit-region audit failures."
        )
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
