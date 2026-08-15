import Foundation
import Testing

@Suite("Vehicle Controls premium current-main closure")
struct VehicleControlsPremiumCurrentMainSourceTests {
    @Test("Vehicle Controls is a product surface, not a stock settings Form")
    func premiumSurfaceReplacesForm() throws {
        let view = try vehicleControlsSection()

        #expect(!view.contains("Form {"))
        #expect(view.contains("@Environment(\\.dynamicTypeSize)"))
        #expect(view.contains("ScrollView {"))
        #expect(view.contains("LazyVStack"))
        #expect(view.contains("vehicleStatusField"))
    }

    @Test("Premium port preserves every newer current-main control family")
    func preservesCurrentMainControlFamilies() throws {
        let view = try vehicleControlsSection()

        #expect(view.contains("batteryRangeSection"))
        #expect(view.contains("headlightSection"))
        #expect(view.contains("lockSection"))
        #expect(view.contains("modeSection"))
        #expect(view.contains("speedLimitSection"))
        #expect(view.contains("cruiseSection"))
        #expect(view.contains("startModeSection"))
        #expect(view.contains("vehicle-controls.battery-range"))
        #expect(view.contains("canLockFromCurrentSpeedEvidence"))
        #expect(view.contains("hasUserFacingSpeedLimitMapping"))
    }

    @Test("Accessibility sizes deliberately recompose controls instead of shrinking text")
    func accessibilityRecompositionIsStructural() throws {
        let view = try vehicleControlsSection()

        #expect(view.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(view.contains("GridItem(.flexible()"))
        #expect(view.contains("connectionIssueField"))
        #expect(view.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(view.contains("frame(minHeight: 58"))
    }

    @Test("Disconnected retained settings are disclosed and remain last-confirmed")
    func retainedStateRemainsTruthful() throws {
        let view = try vehicleControlsSection()

        #expect(view.contains("vehicle.state.dataAvailability == .retained"))
        #expect(view.contains("Last confirmed settings shown below"))
        #expect(view.contains("vehicle-controls.retained-state"))
        #expect(view.contains("Last confirmed selection"))
        #expect(view.contains("Reconnect to confirm the current setting or make a change."))
    }

    @Test("Selections still derive from confirmed VehicleStore state")
    func confirmedStateRemainsAuthoritative() throws {
        let view = try vehicleControlsSection()

        #expect(view.contains("vehicle.state.rideMode == mode"))
        #expect(view.contains("vehicle.state.isHeadlightOn"))
        #expect(view.contains("vehicle.state.isLocked"))
        #expect(view.contains("vehicle.state.isCruiseEnabled"))
        #expect(view.contains("vehicle.state.startMode"))
        #expect(view.contains("vehicle.isVehicleCommandPending"))
    }

    private func vehicleControlsSection() throws -> Substring {
        let source = try readRepositoryFile("NembraApp/Features/Home/VehicleControlsView.swift")
        guard let start = source.range(of: "struct VehicleControlsView: View"),
              let end = source.range(of: "/// Product-facing Battery/Range surface.", range: start.upperBound..<source.endIndex) else {
            Issue.record("VehicleControlsView section was not found")
            throw SourceContractError.sectionMissing
        }
        return source[start.lowerBound..<end.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
        return String(decoding: data, as: UTF8.self)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
