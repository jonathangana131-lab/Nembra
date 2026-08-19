import XCTest

final class NembraCaptureUITests: XCTestCase {
    private let syntheticLaunchArgument = "--nembra-capture-simulator-ui"
    private let syntheticDisclosureIdentifier = "nembra.capture.qa.synthetic-disclosure"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPublicBuildFailsClosedAndKeepsAccountLinkReachable() throws {
        let app = launchPublicApp()

        XCTAssertTrue(app.descendants(matching: .any)["capture.p0-root"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["Physical capture locked"].exists)
        XCTAssertFalse(app.staticTexts["Field build ready"].exists)
        XCTAssertFalse(app.descendants(matching: .any)[syntheticDisclosureIdentifier].exists)
        XCTAssertFalse(app.descendants(matching: .any)["nembra.capture.qa.synthetic-root"].exists)

        let accountLink = app.buttons["nembra.capture.root.account-link-action"]
        XCTAssertTrue(accountLink.waitForExistence(timeout: 3))
        XCTAssertTrue(accountLink.isEnabled)
        XCTAssertTrue(accountLink.isHittable)

        assertNoCompleteOrShare(in: app)
    }

    @MainActor
    func testAccessibilityXXXLKeepsTheOnlyPublicActionUsable() throws {
        let app = launchPublicApp(extraArguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ])

        XCTAssertTrue(app.descendants(matching: .any)["capture.p0-root"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["Physical capture locked"].exists)
        XCTAssertFalse(app.descendants(matching: .any)[syntheticDisclosureIdentifier].exists)

        let accountLink = app.buttons["nembra.capture.root.account-link-action"]
        XCTAssertTrue(accountLink.waitForExistence(timeout: 3))
        XCTAssertTrue(accountLink.isEnabled)
        XCTAssertTrue(accountLink.isHittable)
    }

    @MainActor
    func testUnknownSyntheticScenarioBlocksInsteadOfOpeningLiveCapture() throws {
        let app = XCUIApplication()
        app.launchArguments += englishLaunchArguments + [syntheticLaunchArgument, "not-allow-listed"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)[syntheticDisclosureIdentifier].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["nembra.capture.qa.invalid-scenario"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["capture.p0-root"].exists)
        XCTAssertFalse(app.buttons["nembra.capture.root.account-link-action"].exists)
    }

    @MainActor
    func testSyntheticSafetySheetRepeatsDisclosureAndConfirmationIsFreshLocalState() throws {
        let app = launchSyntheticApp(scenario: "safety")
        let review = app.buttons["nembra.capture.stationary-safety-review"]
        reveal(review, in: app)
        review.tap()

        XCTAssertTrue(app.descendants(matching: .any)["nembra.capture.qa.synthetic-sheet-disclosure"].waitForExistence(timeout: 3))
        XCTAssertTrue(element("The scooter is stationary.", in: app).exists)
        XCTAssertTrue(element("The scooter is powered OFF.", in: app).exists)
        XCTAssertTrue(element("The charger is disconnected.", in: app).exists)
        XCTAssertTrue(element("No one will ride the scooter during this capture.", in: app).exists)
        XCTAssertTrue(element("No one will touch the scooter controls during this capture.", in: app).exists)
        XCTAssertTrue(element("Capture cannot sense or verify the charger or these physical conditions. Your confirmation is recorded as an operator declaration, never as scooter telemetry.", in: app).exists)
        keepSyntheticScreenshot(named: "SAFETY-SHEET")

        let cancel = app.buttons["Cancel"]
        reveal(cancel, in: app)
        cancel.tap()
        XCTAssertTrue(waitForHittable(review, timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["nembra.capture.correlation.outcome"].exists)

        review.tap()
        let confirm = app.buttons["nembra.capture.stationary-safety-confirm"]
        reveal(confirm, in: app)
        confirm.tap()

        XCTAssertTrue(app.descendants(matching: .any)["nembra.capture.correlation.outcome"].waitForExistence(timeout: 3))
        XCTAssertTrue(element("Scooter signal found", in: app).exists)
    }

    @MainActor
    func testSyntheticSafetySheetAtAccessibilityXXXLKeepsDisclosureAndConfirmationReachable() throws {
        let app = launchSyntheticApp(
            scenario: "safety",
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
            ]
        )

        let review = app.buttons["nembra.capture.stationary-safety-review"]
        reveal(review, in: app)
        review.tap()

        XCTAssertTrue(app.descendants(matching: .any)["nembra.capture.qa.synthetic-sheet-disclosure"].waitForExistence(timeout: 3))
        let confirm = app.buttons["nembra.capture.stationary-safety-confirm"]
        reveal(confirm, in: app)
        XCTAssertTrue(confirm.isEnabled)
        keepSyntheticScreenshot(named: "SAFETY-SHEET-AX-XXXL")
    }

    @MainActor
    func testSyntheticCorrelationWithNoRepeatableTargetStopsWithoutConfirmation() throws {
        let app = launchSyntheticApp(scenario: "correlation-none")

        XCTAssertTrue(app.descendants(matching: .any)["nembra.capture.correlation.outcome"].waitForExistence(timeout: 3))
        XCTAssertTrue(element("No full UUID repeated the required OFF1→ON1→OFF2→ON2 pattern. Do not fall back to the historical capture UUID; restart the fresh correlation series.", in: app).exists)
        XCTAssertFalse(app.buttons["nembra.capture.correlation.confirm"].exists)
        assertNoCompleteOrShare(in: app)
        keepSyntheticScreenshot(named: "CORRELATION-NONE")
    }

    @MainActor
    func testSyntheticAmbiguousCorrelationStopsWithoutGuessing() throws {
        let app = launchSyntheticApp(scenario: "correlation-ambiguous")

        XCTAssertTrue(app.descendants(matching: .any)["nembra.capture.correlation.outcome"].waitForExistence(timeout: 3))
        XCTAssertTrue(element("Fresh correlation remained ambiguous across 2 repeatable full UUIDs. Do not guess from name, RSSI, FD50, or Tuya hints; restart from OFF1 after reducing nearby-device ambiguity.", in: app).exists)
        XCTAssertFalse(app.buttons["nembra.capture.correlation.confirm"].exists)
        assertNoCompleteOrShare(in: app)
        keepSyntheticScreenshot(named: "CORRELATION-AMBIGUOUS")
    }

    @MainActor
    func testSyntheticSingleCorrelationRequiresConfirmationBeforeObservationPresentation() throws {
        let app = launchSyntheticApp(scenario: "correlation-success")

        XCTAssertTrue(app.descendants(matching: .any)["nembra.capture.correlation.outcome"].waitForExistence(timeout: 3))
        XCTAssertTrue(element("Scooter signal found", in: app).exists)
        let confirm = app.buttons["nembra.capture.correlation.confirm"]
        reveal(confirm, in: app)
        XCTAssertFalse(app.descendants(matching: .any)["nembra.capture.observation.surface"].exists)
        keepSyntheticScreenshot(named: "CORRELATION-SUCCESS")

        confirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["nembra.capture.observation.surface"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSyntheticCorrelationToObservationFitsCompactLandscape() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = launchSyntheticApp(scenario: "correlation-success")
        let confirm = app.buttons["nembra.capture.correlation.confirm"]
        reveal(confirm, in: app)
        confirm.tap()

        XCTAssertTrue(app.descendants(matching: .any)["nembra.capture.observation.surface"].waitForExistence(timeout: 3))
        reveal(app.buttons["nembra.capture.stop-attempt"], in: app)
        reveal(app.buttons["nembra.capture.qa.complete-observation"], in: app)
        keepSyntheticScreenshot(named: "CORRELATION-OBSERVATION-COMPACT-LANDSCAPE")
    }

    @MainActor
    func testSyntheticObservationCompletionPresentationStillRequiresIntegrityBeforeComplete() throws {
        let app = launchSyntheticApp(scenario: "observation-active")

        XCTAssertTrue(app.descendants(matching: .any)["nembra.capture.observation.surface"].waitForExistence(timeout: 3))
        XCTAssertTrue(element("18 / 45 s", in: app).exists)
        XCTAssertTrue(app.buttons["nembra.capture.stop-attempt"].exists)
        assertNoCompleteOrShare(in: app)
        keepSyntheticScreenshot(named: "OBSERVATION-ACTIVE")

        let completeObservation = app.buttons["nembra.capture.qa.complete-observation"]
        reveal(completeObservation, in: app)
        completeObservation.tap()

        XCTAssertTrue(element("CAPTURE SEALED", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["nembra.capture.integrity"].exists)
        assertNoCompleteOrShare(in: app)
        keepSyntheticScreenshot(named: "INTEGRITY-PENDING")

        let verifyIntegrity = app.buttons["nembra.capture.qa.verify-integrity"]
        reveal(verifyIntegrity, in: app)
        verifyIntegrity.tap()

        XCTAssertTrue(app.descendants(matching: .any)["nembra.capture.complete"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["nembra.capture.integrity"].exists)
        XCTAssertTrue(app.buttons["nembra.capture.share"].exists)
        XCTAssertTrue(element("SYNTHETIC UI STATE · NO CAPTURE ARTIFACT", in: app).exists)
        keepSyntheticScreenshot(named: "INTEGRITY-GATED-COMPLETE")
    }

    @MainActor
    func testSyntheticObservationTimeoutIsTerminalAndCannotPresentComplete() throws {
        let app = launchSyntheticApp(scenario: "observation-timeout")

        XCTAssertTrue(app.descendants(matching: .any)["nembra.capture.observation.surface"].waitForExistence(timeout: 3))
        XCTAssertTrue(element("Scooter data did not become sufficient before the bounded observation deadline. Keep the scooter stationary, relaunch Capture, and start again from scooter OFF.", in: app).exists)
        assertNoCompleteOrShare(in: app)
        keepSyntheticScreenshot(named: "OBSERVATION-TIMEOUT")
    }

    @MainActor
    func testSyntheticStoppingObservationCancelsWithoutAcceptedState() throws {
        let app = launchSyntheticApp(scenario: "observation-active")
        let stop = app.buttons["nembra.capture.stop-attempt"]
        reveal(stop, in: app)
        stop.tap()

        XCTAssertTrue(element("Attempt stopped", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("The operator stopped this synthetic presentation. No observation, accepted state, or artifact carries forward.", in: app).exists)
        assertNoCompleteOrShare(in: app)
        keepSyntheticScreenshot(named: "OBSERVATION-CANCELLED")
    }

    @MainActor
    func testSyntheticShareCancellationCanRetryTheSamePresentation() throws {
        let app = launchSyntheticApp(scenario: "share-retry")

        XCTAssertTrue(app.descendants(matching: .any)["nembra.capture.complete"].waitForExistence(timeout: 3))
        XCTAssertTrue(element("Display-only QA digest · SYNTHETIC-NO-ARTIFACT-0001", in: app).exists)
        XCTAssertTrue(element("If sharing is cancelled or fails, tap Share Capture again. The same verified bytes remain sealed.", in: app).exists)

        let share = app.buttons["nembra.capture.share"]
        reveal(share, in: app)
        share.tap()

        XCTAssertTrue(app.descendants(matching: .any)["nembra.capture.qa.share-surrogate"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["nembra.capture.qa.synthetic-sheet-disclosure"].exists)
        XCTAssertTrue(element("Synthetic share attempt 1", in: app).exists)
        keepSyntheticScreenshot(named: "SHARE-ATTEMPT-1")

        app.buttons["nembra.capture.qa.share-cancel"].tap()
        XCTAssertTrue(waitForHittable(share, timeout: 3))
        share.tap()

        XCTAssertTrue(element("Synthetic share attempt 2", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["nembra.capture.qa.synthetic-sheet-disclosure"].exists)
        keepSyntheticScreenshot(named: "SHARE-ATTEMPT-2")
    }

    @MainActor
    private func launchPublicApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += englishLaunchArguments + extraArguments
        app.launch()
        return app
    }

    @MainActor
    private func launchSyntheticApp(
        scenario: String,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += englishLaunchArguments + extraArguments + [syntheticLaunchArgument, scenario]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)[syntheticDisclosureIdentifier].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["nembra.capture.qa.synthetic-root"].exists)
        XCTAssertFalse(app.staticTexts["Field build ready"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["capture.p0-root"].exists)
        return app
    }

    private var englishLaunchArguments: [String] {
        ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    @MainActor
    private func element(_ labelOrIdentifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[labelOrIdentifier]
    }

    @MainActor
    private func assertNoCompleteOrShare(in app: XCUIApplication) {
        XCTAssertFalse(app.descendants(matching: .any)["nembra.capture.complete"].exists)
        XCTAssertFalse(app.buttons["nembra.capture.share"].exists)
        XCTAssertFalse(app.staticTexts["CAPTURE COMPLETE"].exists)
    }

    @MainActor
    private func reveal(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumSwipes: Int = 6
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        if waitForHittable(element, timeout: 0.5) { return }

        for _ in 0..<maximumSwipes where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(waitForHittable(element, timeout: 2))
    }

    @MainActor
    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func keepSyntheticScreenshot(named name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "SYNTHETIC-QA-\(name)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
