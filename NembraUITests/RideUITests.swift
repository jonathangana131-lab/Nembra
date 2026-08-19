import XCTest

final class RideUITests: XCTestCase {
    private struct ElementSemantics: Equatable {
        let label: String
        let value: String
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    @MainActor
    func testAutomaticRideSurvivesProcessRelaunchWithSameDurableIdentity() {
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchEnvironment["NEMBRA_SIMULATION_SCENARIO"] = "riding"
        app.launchEnvironment["NEMBRA_SIMULATION_STORAGE_NAMESPACE"] = UUID().uuidString
        app.launch()

        let rideStatus = app.descendants(matching: .any)["home.ride-status"]
        XCTAssertTrue(rideStatus.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForValue("Riding automatically", element: rideStatus, timeout: 5),
            "A fresh authoritative Simulator packet should drive the real automatic ride path."
        )
        keepScreenshot(named: "Automatic Ride Active Home")

        app.terminate()
        app.launch()

        let recoveredStatus = app.descendants(matching: .any)["home.ride-status"]
        XCTAssertTrue(recoveredStatus.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForValue("Ride resumed", element: recoveredStatus, timeout: 6),
            "A process relaunch must restore the durable ride and resume it after fresh evidence."
        )
        keepScreenshot(named: "Automatic Ride Recovered Home")
    }

    @MainActor
    func testCompletedRideAppearsWithDurableRouteThroughRealRidePipeline() throws {
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchEnvironment["NEMBRA_SIMULATION_SCENARIO"] = "riding"
        app.launchEnvironment["NEMBRA_SIMULATION_STORAGE_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["NEMBRA_SIMULATION_AUTOCOMPLETE_RIDE"] = "1"
        app.launch()

        let ridesTab = app.tabBars.buttons["Rides"]
        XCTAssertTrue(ridesTab.waitForExistence(timeout: 5))
        ridesTab.tap()

        XCTAssertTrue(
            app.otherElements["rides.activity.daily-chart"].waitForExistence(timeout: 5),
            "The mileage destination marker must not overwrite the accepted-mileage chart identifier."
        )

        let row = app.buttons["rides.completed-row"]
        XCTAssertTrue(
            scrollCompletedRideRowIntoView(row, in: app, timeout: 8),
            "The explicit QA auto-completion must flow through RideEngine, durable history commit, and the real Rides surface."
        )

        let rowValue = row.value as? String ?? ""
        XCTAssertTrue(
            row.label.localizedCaseInsensitiveContains("Ride on"),
            "A completed ride row must expose one concise Nembra-owned ride identity."
        )
        XCTAssertFalse(
            rowValue.localizedCaseInsensitiveContains("Completed ride"),
            "A normal completed ride must not repeat its identity inside the accessibility value."
        )
        XCTAssertFalse(
            rowValue.localizedCaseInsensitiveContains("recovered after relaunch"),
            "The uninterrupted QA ride must not claim recovered continuity."
        )
        keepScreenshot(named: "Completed Ride History")

        row.tap()
        let detail = app.scrollViews["rides.detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))

        let odometer = app.descendants(matching: .any)["rides.evidence.odometer"]
        XCTAssertTrue(odometer.exists)
        let odometerSemantics = "\(odometer.label) \(odometer.value as? String ?? "")"
        XCTAssertTrue(
            odometerSemantics.contains("mi") || odometerSemantics.contains("km"),
            "The completed ride must expose measured odometer distance evidence in the active locale."
        )
        XCTAssertFalse(
            odometerSemantics.contains("0.0"),
            "The end-to-end QA fixture must establish the ride baseline before advancing odometer evidence."
        )

        let routeMap = app.descendants(matching: .any)["rides.route-map"]
        if !routeMap.waitForExistence(timeout: 3) {
            detail.swipeUp()
        }
        XCTAssertTrue(
            routeMap.waitForExistence(timeout: 3),
            "The explicit QA route fixture must pass through RideRouteRecorder, exact durable route storage, and MapKit presentation."
        )
        XCTAssertEqual(
            routeMap.label,
            "Recorded ride route",
            "The persisted route visualization must expose the Nembra-owned route identity instead of relying on MapKit internals."
        )
        let routeSemantics = routeMap.value as? String ?? ""
        XCTAssertTrue(
            routeSemantics.localizedCaseInsensitiveContains("Route coverage partial"),
            "This fixture starts route recording after ride activation, so accessibility must preserve partial-coverage truth."
        )
        XCTAssertTrue(
            routeSemantics.localizedCaseInsensitiveContains("4 recorded points"),
            "Route accessibility must report the four points actually persisted by the explicit QA fixture."
        )
        XCTAssertTrue(
            routeSemantics.localizedCaseInsensitiveContains("no known route gaps recorded"),
            "Partial coverage without an explicit internal segment gap must not invent a known route gap."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["rides.route-unavailable"].exists,
            "A ride with verified persisted route geometry must not fall back to the no-route state."
        )
        keepScreenshot(named: "Completed Ride Details With Route")

        try app.performAccessibilityAudit(
            for: [
                .sufficientElementDescription,
                .hitRegion,
                .textClipped,
                .trait,
                .dynamicType
            ]
        )
    }

    @MainActor
    func testCompletedRideTodayAndLatestRideSurviveRelaunchWithoutDuplication() {
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait

        let storageNamespace = UUID().uuidString
        let app = XCUIApplication()
        app.launchEnvironment["NEMBRA_SIMULATION_SCENARIO"] = "riding"
        app.launchEnvironment["NEMBRA_SIMULATION_STORAGE_NAMESPACE"] = storageNamespace
        app.launchEnvironment["NEMBRA_SIMULATION_AUTOCOMPLETE_RIDE"] = "1"
        app.launch()

        let initialLatestRide = app.descendants(matching: .any)["home.latest-ride.open"]
        XCTAssertTrue(
            initialLatestRide.waitForExistence(timeout: 8),
            "The explicit Simulator QA ride must complete through the durable history pipeline."
        )

        let initialTodayDistance = app.descendants(matching: .any)["home.metric.trip"]
        let initialTodayDuration = app.descendants(matching: .any)["home.metric.duration"]
        XCTAssertTrue(
            waitForNonzeroMetric(initialTodayDistance, timeout: 5),
            "Today's trip must expose nonzero accepted route distance after completion."
        )
        XCTAssertTrue(
            waitForNonzeroMetric(initialTodayDuration, timeout: 5),
            "Today's duration must expose nonzero accepted monotonic evidence after completion."
        )

        let distanceBeforeRelaunch = semantics(of: initialTodayDistance)
        let durationBeforeRelaunch = semantics(of: initialTodayDuration)
        let latestRideBeforeRelaunch = semantics(of: initialLatestRide)
        XCTAssertEqual(distanceBeforeRelaunch.label, "Today's trip")
        XCTAssertEqual(durationBeforeRelaunch.label, "Today's duration")
        assertNonzeroMetric(distanceBeforeRelaunch, named: "Today's trip")
        assertNonzeroMetric(durationBeforeRelaunch, named: "Today's duration")

        XCTAssertTrue(
            scrollFullyClearOfFloatingTabBar(initialLatestRide, in: app),
            "The durable latest-ride continuation must scroll fully clear of the native floating tab bar."
        )
        assertFullyInsideWindowAndAboveTabBar(initialLatestRide, in: app)
        keepScreenshot(named: "Durable Today Before Relaunch - Simulator QA Only")

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "NEMBRA_SIMULATION_AUTOCOMPLETE_RIDE")
        app.launch()

        let relaunchedLatestRide = app.descendants(matching: .any)["home.latest-ride.open"]
        XCTAssertTrue(
            relaunchedLatestRide.waitForExistence(timeout: 8),
            "Relaunching the same storage namespace must restore the latest completed ride."
        )

        let relaunchedTodayDistance = app.descendants(matching: .any)["home.metric.trip"]
        let relaunchedTodayDuration = app.descendants(matching: .any)["home.metric.duration"]
        XCTAssertTrue(
            waitForSemantics(distanceBeforeRelaunch, element: relaunchedTodayDistance, timeout: 6),
            "Relaunch must preserve Today's exact accepted distance display and provenance semantics."
        )
        XCTAssertTrue(
            waitForNonzeroMetric(relaunchedTodayDuration, timeout: 6),
            "A fresh current ride may advance duration, but it must not reset durable Today duration to zero."
        )
        XCTAssertTrue(
            waitForSemantics(latestRideBeforeRelaunch, element: relaunchedLatestRide, timeout: 6),
            "Relaunch must restore the exact same latest completed-ride identity and evidence summary."
        )

        XCTAssertEqual(semantics(of: relaunchedTodayDistance), distanceBeforeRelaunch)
        XCTAssertEqual(semantics(of: relaunchedLatestRide), latestRideBeforeRelaunch)
        let durationAfterRelaunch = semantics(of: relaunchedTodayDuration)
        XCTAssertEqual(durationAfterRelaunch.label, "Today's duration")
        assertNonzeroMetric(durationAfterRelaunch, named: "Today's duration")

        XCTAssertTrue(
            scrollFullyClearOfFloatingTabBar(relaunchedLatestRide, in: app),
            "The restored latest-ride continuation must remain fully operable above floating tab chrome."
        )
        assertFullyInsideWindowAndAboveTabBar(relaunchedLatestRide, in: app)
        keepScreenshot(named: "Durable Today After Relaunch - Simulator QA Only")

        let ridesTab = app.tabBars.buttons["Rides"]
        XCTAssertTrue(ridesTab.waitForExistence(timeout: 3))
        ridesTab.tap()

        let completedRows = app.buttons.matching(identifier: "rides.completed-row")
        XCTAssertTrue(
            scrollCompletedRideRowIntoView(completedRows.firstMatch, in: app, timeout: 6),
            "The restored completed ride must remain available on Rides."
        )
        let savedRideSummary = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "1 saved ride")
        ).firstMatch
        XCTAssertTrue(
            savedRideSummary.waitForExistence(timeout: 3),
            "The durable archive summary must still report exactly one saved ride after relaunch."
        )
    }

    @MainActor
    func testCompletedRideDetailDarkAppearancePreservesRouteAndBottomControl() {
        let previousAppearance = XCUIDevice.shared.appearance
        defer {
            XCUIDevice.shared.appearance = previousAppearance
            XCUIDevice.shared.orientation = .portrait
        }

        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.appearance = .dark

        let app = XCUIApplication()
        app.launchEnvironment["NEMBRA_SIMULATION_SCENARIO"] = "riding"
        app.launchEnvironment["NEMBRA_SIMULATION_STORAGE_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["NEMBRA_SIMULATION_AUTOCOMPLETE_RIDE"] = "1"
        app.launch()

        let ridesTab = app.tabBars.buttons["Rides"]
        XCTAssertTrue(ridesTab.waitForExistence(timeout: 5))
        ridesTab.tap()

        let row = app.buttons["rides.completed-row"]
        XCTAssertTrue(scrollCompletedRideRowIntoView(row, in: app, timeout: 8))
        row.tap()

        let detail = app.scrollViews["rides.detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))

        let routeMap = app.descendants(matching: .any)["rides.route-map"]
        if !routeMap.waitForExistence(timeout: 3) {
            detail.swipeUp()
        }
        XCTAssertTrue(routeMap.waitForExistence(timeout: 3))
        XCTAssertEqual(routeMap.label, "Recorded ride route")
        XCTAssertTrue(
            (routeMap.value as? String ?? "").localizedCaseInsensitiveContains("Route coverage partial"),
            "Dark appearance must preserve the same accepted partial-route semantics as light appearance."
        )
        XCTAssertFalse(app.descendants(matching: .any)["rides.route-unavailable"].exists)
        keepScreenshot(named: "Completed Ride Details Dark")

        let recordingDetails = app.buttons["rides.recording-details"]
        XCTAssertTrue(
            scrollToHittable(recordingDetails, in: detail, maximumGestures: 4),
            "The final Ride Details control must remain reachable in dark appearance."
        )
        XCTAssertTrue(
            recordingDetails.isHittable,
            "The floating shell chrome must not make the final Ride Details control inoperable."
        )
        keepScreenshot(named: "Completed Ride Details Dark Bottom")
    }

    @MainActor
    func testLongCompletedRideRouteStaysInteractiveAfterDetailInvalidation() {
        let previousAppearance = XCUIDevice.shared.appearance
        defer {
            XCUIDevice.shared.appearance = previousAppearance
            XCUIDevice.shared.orientation = .portrait
        }

        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.appearance = .light

        let app = XCUIApplication()
        app.launchEnvironment["NEMBRA_SIMULATION_SCENARIO"] = "riding"
        app.launchEnvironment["NEMBRA_SIMULATION_STORAGE_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["NEMBRA_SIMULATION_AUTOCOMPLETE_RIDE"] = "1"
        app.launchEnvironment["NEMBRA_SIMULATION_ROUTE_POINT_COUNT"] = "5000"
        app.launch()

        let ridesTab = app.tabBars.buttons["Rides"]
        XCTAssertTrue(ridesTab.waitForExistence(timeout: 5))
        ridesTab.tap()

        let row = app.buttons["rides.completed-row"]
        XCTAssertTrue(
            scrollCompletedRideRowIntoView(row, in: app, timeout: 15),
            "The bounded 5,000-point QA route must still complete through the real recorder/history pipeline."
        )
        row.tap()

        let detail = app.scrollViews["rides.detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))

        let routeMap = app.descendants(matching: .any)["rides.route-map"]
        XCTAssertTrue(
            routeMap.waitForExistence(timeout: 8),
            "A 5,000-point persisted route must become an interactive real MapKit Ride Detail within the UI acceptance bound."
        )
        let routeSemantics = routeMap.value as? String ?? ""
        XCTAssertTrue(
            routeSemantics.localizedCaseInsensitiveContains("5000 recorded points"),
            "Long-route acceptance must prove the exact persisted fixture volume rather than a short-route fallback."
        )
        XCTAssertTrue(routeSemantics.localizedCaseInsensitiveContains("Route coverage partial"))
        keepScreenshot(named: "Completed Ride Details Long Route")

        let recordingDetails = app.buttons["rides.recording-details"]
        XCTAssertTrue(
            scrollToHittable(recordingDetails, in: detail, maximumGestures: 4),
            "The long MapKit route must not make the final detail disclosure unreachable."
        )
        recordingDetails.tap()

        XCTAssertTrue(
            app.staticTexts["Recorded points"].waitForExistence(timeout: 4),
            "Expanding Recording details forces the parent Ride Detail to update and must remain responsive with a long route."
        )
        XCTAssertTrue(
            app.staticTexts["5000"].waitForExistence(timeout: 4),
            "The post-invalidation detail view must still expose the exact long-route point count."
        )
        keepScreenshot(named: "Completed Ride Details Long Route Expanded")
    }

    @MainActor
    private func waitForValue(
        _ value: String,
        element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForNonzeroMetric(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "value != nil AND value MATCHES %@", ".*[1-9].*")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForSemantics(
        _ semantics: ElementSemantics,
        element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(
            format: "label == %@ AND value == %@",
            semantics.label,
            semantics.value
        )
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func scrollCompletedRideRowIntoView(
        _ row: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let history = app.collectionViews["rides.history"]
        guard history.waitForExistence(timeout: min(timeout, 3)) else { return false }

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if row.exists, row.isHittable {
                return true
            }

            history.swipeUp()
        } while Date() < deadline

        return row.exists && row.isHittable
    }

    @MainActor
    private func scrollToHittable(
        _ element: XCUIElement,
        in scrollView: XCUIElement,
        maximumGestures: Int
    ) -> Bool {
        guard scrollView.waitForExistence(timeout: 3) else { return false }

        for gesture in 0...maximumGestures {
            if element.exists, element.isHittable {
                return true
            }
            guard gesture < maximumGestures else { break }
            scrollView.swipeUp()
        }

        return element.exists && element.isHittable
    }

    @MainActor
    private func semantics(of element: XCUIElement) -> ElementSemantics {
        ElementSemantics(
            label: element.label,
            value: element.value as? String ?? ""
        )
    }

    private func assertNonzeroMetric(
        _ semantics: ElementSemantics,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(semantics.label.isEmpty, "\(name) must retain an accessibility label.", file: file, line: line)
        XCTAssertTrue(
            semantics.value.contains(where: { $0.isNumber && $0 != "0" }),
            "\(name) must expose a nonzero accepted value, got '\(semantics.value)'.",
            file: file,
            line: line
        )
    }

    @MainActor
    private func scrollFullyClearOfFloatingTabBar(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumGestures: Int = 4
    ) -> Bool {
        guard element.waitForExistence(timeout: 2) else { return false }
        let scrollView = app.scrollViews.firstMatch
        guard scrollView.waitForExistence(timeout: 2) else { return false }

        for gesture in 0...maximumGestures {
            if isFullyInsideWindowAndAboveTabBar(element, in: app) {
                return true
            }
            guard gesture < maximumGestures else { break }
            scrollView.swipeUp()
            _ = element.waitForExistence(timeout: 1)
        }

        return isFullyInsideWindowAndAboveTabBar(element, in: app)
    }

    @MainActor
    private func assertFullyInsideWindowAndAboveTabBar(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let window = app.windows.firstMatch
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(element.isHittable, "The latest-ride row must be hittable.", file: file, line: line)
        XCTAssertTrue(window.exists, "The application window must exist.", file: file, line: line)
        XCTAssertTrue(tabBar.exists, "The native tab bar must exist.", file: file, line: line)
        XCTAssertTrue(
            window.frame.contains(element.frame),
            "The full latest-ride row \(element.frame) must remain inside window \(window.frame).",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            element.frame.maxY,
            tabBar.frame.minY,
            "The latest-ride row \(element.frame) must clear tab bar \(tabBar.frame).",
            file: file,
            line: line
        )
    }

    @MainActor
    private func isFullyInsideWindowAndAboveTabBar(
        _ element: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        let window = app.windows.firstMatch
        let tabBar = app.tabBars.firstMatch
        guard element.exists,
              element.isHittable,
              window.exists,
              tabBar.exists else { return false }
        return window.frame.contains(element.frame)
            && element.frame.maxY <= tabBar.frame.minY
    }

    @MainActor
    private func keepScreenshot(named name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
