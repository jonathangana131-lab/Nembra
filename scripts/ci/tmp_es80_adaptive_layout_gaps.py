from pathlib import Path

path = Path("NembraUITests/ES80ResearchCaptureUITests.swift")
workflow = Path(".github/workflows/es80-v14-adaptive-layout-gaps.yml")
self_path = Path("scripts/ci/tmp_es80_adaptive_layout_gaps.py")
source = path.read_text(encoding="utf-8")

anchor = '''    @MainActor
    func testV14SimulatorQACaptureCompleteRemainsActionableAtAccessibilityExtraExtraExtraLarge() {
'''
if source.count(anchor) != 1:
    raise SystemExit(f"expected one adaptive-layout insertion anchor, got {source.count(anchor)}")

required_incumbent = [
    "testV14SimulatorQACapturesRepresentativeInProgressAndRecoveryStates",
    "testV14SimulatorQACaptureCompleteRemainsActionableAtAccessibilityExtraExtraExtraLarge",
    "testV14SimulatorQAHorizonReadyLandscapeKeepsFinishAndTruthVisible",
]
for name in required_incumbent:
    if source.count(name) != 1:
        raise SystemExit(f"current-spine visual gate missing/duplicated: {name}")

new_names = [
    "testV14SimulatorQAHorizonReadyAtAccessibilityExtraExtraExtraLarge",
    "testV14SimulatorQACompleteLandscapeKeepsShareAndDetailsReachable",
]
for name in new_names:
    if name in source:
        raise SystemExit(f"adaptive-layout gap already closed: {name}")

addition = '''    @MainActor
    func testV14SimulatorQAHorizonReadyAtAccessibilityExtraExtraExtraLarge() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=observationHorizonReady",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let simulatorBadge = app.descendants(matching: .any)["es80.capture.simulator-qa"]
        let shell = app.descendants(matching: .any)["es80.capture-shell"]
        let finish = app.descendants(matching: .any)["es80.capture.finish"]
        XCTAssertTrue(shell.waitForExistence(timeout: 5))
        XCTAssertTrue(simulatorBadge.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Capture can be sealed"].waitForExistence(timeout: 3))
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.field-no-go"].exists)

        let topAttachment = XCTAttachment(screenshot: app.screenshot())
        topAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Horizon Ready — Accessibility XXXL — Top"
        topAttachment.lifetime = .keepAlways
        add(topAttachment)

        if !finish.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(finish.exists)

        let actionAttachment = XCTAttachment(screenshot: app.screenshot())
        actionAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Horizon Ready — Accessibility XXXL — Action"
        actionAttachment.lifetime = .keepAlways
        add(actionAttachment)
    }

    @MainActor
    func testV14SimulatorQACompleteLandscapeKeepsShareAndDetailsReachable() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=captureComplete"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["es80.capture.simulator-qa"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft

        let share = app.descendants(matching: .any)["es80.capture.share"]
        let details = app.descendants(matching: .any)["es80.capture.view-details"]
        XCTAssertTrue(app.staticTexts["CAPTURE COMPLETE"].waitForExistence(timeout: 3))
        XCTAssertTrue(share.waitForExistence(timeout: 3))
        XCTAssertTrue(details.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Vehicle controls"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Nembra Capture V14 — SIMULATOR QA — Capture Complete — Landscape"
        attachment.lifetime = .keepAlways
        add(attachment)

        if !share.isHittable || !details.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(share.exists)
        XCTAssertTrue(details.exists)
    }

'''
source = source.replace(anchor, addition + anchor, 1)

for name in required_incumbent + new_names:
    if source.count(name) != 1:
        raise SystemExit(f"expected exactly one final visual gate: {name}")
for required in [
    "--es80-capture-qa-scenario=observationHorizonReady",
    "--es80-capture-qa-scenario=captureComplete",
    "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
    "es80.capture.finish",
    "es80.capture.share",
    "es80.capture.view-details",
    "Capture can be sealed",
    "CAPTURE COMPLETE",
    "SIMULATOR QA",
]:
    if required not in source:
        raise SystemExit(f"adaptive-layout truth/action contract missing: {required}")

path.write_text(source, encoding="utf-8")
for temp in (workflow, self_path):
    if temp.exists():
        temp.unlink()
