import Foundation
import XCTest

final class DashboardLowBatteryAccessibilitySourceTests: XCTestCase {
    func testLiveLowBatteryWarningIsPresentInVoiceOverSemantics() throws {
        let source = try dashboardSource()

        XCTAssertTrue(source.contains(".accessibilityValue(compactMetricAccessibilityValue(title: title, value: value, warning: warning, retained: retained))"))
        XCTAssertTrue(source.contains("if warning, value != \"—\""))
        XCTAssertTrue(source.contains("return \"\\(title) low, \\(value)\""))
        XCTAssertTrue(source.contains("if batteryInstrumentWarning"))
        XCTAssertTrue(source.contains("return \"Low battery, \\(batteryText)\""))
    }

    func testRangeVoiceOverUsesLearnedRangeSemantics() throws {
        let source = try dashboardSource()

        XCTAssertTrue(source.contains(".accessibilityLabel(batteryReadout == .charge ? \"Battery\" : \"Learned range\")"))
        XCTAssertFalse(source.contains(".accessibilityLabel(batteryReadout == .charge ? \"Battery\" : \"Estimated range\")"))
    }

    private func dashboardSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot
                .deletingLastPathComponent()
                .appendingPathComponent("NembraApp/Features/Dashboard/DashboardView.swift"),
            encoding: .utf8
        )
    }
}