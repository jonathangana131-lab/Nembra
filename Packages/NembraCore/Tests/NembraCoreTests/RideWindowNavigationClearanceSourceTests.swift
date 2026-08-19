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
            timelineSource.contains(".accessibilityElement(children: .ignore)")
                && timelineSource.contains(".accessibilityLabel(title)")
                && timelineSource.contains(".accessibilityValue(timestamp(date))")
                && timelineSource.contains(".contentShape(.accessibility, Rectangle())")
                && !timelineSource.contains(".accessibilityElement(children: .combine)"),
            "Ride Window rows must expose one explicit label/value element across the padded row while their semantic Text views remain free to scale. Combining the adaptive ViewThatFits children caused alternating Xcode 27 Dynamic Type audit failures, and limiting the accessibility shape to its text caused an 18 pt hit-region audit failure."
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
