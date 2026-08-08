from pathlib import Path

path = Path("NembraUITests/ES80ResearchCaptureUITests.swift")
workflow = Path(".github/workflows/es80-v14-inverse-adaptive-matrix.yml")
self_path = Path("scripts/ci/tmp_es80_inverse_adaptive_matrix.py")
source = path.read_text(encoding="utf-8")

anchor = '''    @MainActor
    func testV14SimulatorQACaptureCompleteRemainsActionableAtAccessibilityExtraExtraExtraLarge() {
'''
if source.count(anchor) != 1:
    raise SystemExit(f"expected one insertion anchor, got {source.count(anchor)}")

incumbent = [
    "testV14SimulatorQACaptureCompleteRemainsActionableAtAccessibilityExtraExtraExtraLarge",
    "testV14SimulatorQAHorizonReadyLandscapeKeepsFinishAndTruthVisible",
    "testV14SimulatorQACapturesRepresentativeInProgressAndRecoveryStates",
]
new_names = [
    "testV14SimulatorQAHorizonReadyRemainsActionableAtAccessibilityExtraExtraExtraLarge",
    "testV14SimulatorQACaptureCompleteLandscapeKeepsShareAndDetailsVisible",
]
for name in incumbent:
    if source.count(name) != 1:
        raise SystemExit(f"incumbent visual gate missing/duplicated: {name}")
for name in new_names:
    if name in source:
        raise SystemExit(f"inverse adaptive gate already exists: {name}")

addition = '''    @MainActor
    func testV14SimulatorQAHorizonReadyRemainsActionableAtAccessibilityExtraExtraExtraLarge() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=observationHorizonReady",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let qaDisclosure = app.descendants(matching: .any)["es80.capture.simulator-qa"]
        let readyState = app.staticTexts["Capture can be sealed"]
        let finish = app.descendants(matching: .any)["es80.capture.finish"]

        XCTAssertTrue(qaDisclosure.waitForExistence(timeout: 5))
        XCTAssertTrue(readyState.waitForExistence(timeout: 3))
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.field-no-go"].exists)
        XCTAssertFalse(app.buttons["Vehicle controls"].exists)

        assertVisibleInScreenshotViewport(
            qaDisclosure,
            windowFrame: app.windows.firstMatch.frame,
            context: "synthetic Simulator QA disclosure at Horizon-ready Accessibility XXXL"
        )
        let disclosureAttachment = XCTAttachment(screenshot: app.screenshot())
        disclosureAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Horizon Ready — Accessibility XXXL — Disclosure"
        disclosureAttachment.lifetime = .keepAlways
        add(disclosureAttachment)

        bringIntoScreenshotViewport(
            readyState,
            in: app,
            context: "Horizon-ready state at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            readyState,
            windowFrame: app.windows.firstMatch.frame,
            context: "Horizon-ready state at Accessibility XXXL"
        )
        let statusAttachment = XCTAttachment(screenshot: app.screenshot())
        statusAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Horizon Ready — Accessibility XXXL — Status"
        statusAttachment.lifetime = .keepAlways
        add(statusAttachment)

        bringIntoScreenshotViewport(
            finish,
            in: app,
            context: "Seal Capture action at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            finish,
            windowFrame: app.windows.firstMatch.frame,
            context: "Seal Capture action at Accessibility XXXL"
        )
        let finishAttachment = XCTAttachment(screenshot: app.screenshot())
        finishAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Horizon Ready — Accessibility XXXL — Seal"
        finishAttachment.lifetime = .keepAlways
        add(finishAttachment)
    }

    @MainActor
    func testV14SimulatorQACaptureCompleteLandscapeKeepsShareAndDetailsVisible() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=captureComplete"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["es80.capture-shell"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft

        let qaDisclosure = app.descendants(matching: .any)["es80.capture.simulator-qa"]
        let completeState = app.staticTexts["CAPTURE COMPLETE"]
        let analysisState = app.staticTexts["Ready for analysis"]
        let shareCapture = app.buttons["Share Capture"]
        let viewDetails = app.buttons["View Details"]

        XCTAssertTrue(qaDisclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(completeState.waitForExistence(timeout: 3))
        XCTAssertTrue(analysisState.waitForExistence(timeout: 3))
        XCTAssertTrue(shareCapture.waitForExistence(timeout: 3))
        XCTAssertTrue(viewDetails.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.field-no-go"].exists)
        XCTAssertFalse(app.buttons["Vehicle controls"].exists)

        let landscapeFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(
            landscapeFrame.width,
            landscapeFrame.height,
            "Capture Complete visual acceptance must actually run in landscape."
        )

        for (element, context, name) in [
            (qaDisclosure, "synthetic Simulator QA disclosure in Capture Complete landscape", "Disclosure"),
            (completeState, "Capture Complete state in landscape", "Complete"),
            (analysisState, "Ready for analysis state in landscape", "Analysis Ready"),
            (shareCapture, "Share Capture action in landscape", "Share"),
            (viewDetails, "View Details action in landscape", "View Details"),
        ] {
            bringIntoScreenshotViewport(element, in: app, context: context)
            assertVisibleInScreenshotViewport(
                element,
                windowFrame: app.windows.firstMatch.frame,
                context: context
            )
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Nembra Capture V14 — SIMULATOR QA — Capture Complete — Landscape — \\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

'''
source = source.replace(anchor, addition + anchor, 1)

for name in incumbent + new_names:
    if source.count(name) != 1:
        raise SystemExit(f"expected exactly one final visual gate: {name}")
for required in [
    "bringIntoScreenshotViewport(",
    "assertVisibleInScreenshotViewport(",
    "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
    "--es80-capture-qa-scenario=observationHorizonReady",
    "--es80-capture-qa-scenario=captureComplete",
    "es80.capture.finish",
    "Share Capture",
    "View Details",
    "SIMULATOR QA",
]:
    if required not in source:
        raise SystemExit(f"visual acceptance contract missing: {required}")

path.write_text(source, encoding="utf-8")
for temp in (workflow, self_path):
    if temp.exists():
        temp.unlink()
