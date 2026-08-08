from pathlib import Path

path = Path("NembraUITests/ES80ResearchCaptureUITests.swift")
source = path.read_text()

for name in (
    "testV14SimulatorQAHorizonReadyDynamicTypeSurfacesHaveRetainedAccessibilityEvidence",
    "testV14SimulatorQAHorizonReadyProgressHasRetainedLandscapeEvidence",
):
    if f"func {name}()" in source:
        raise RuntimeError(f"UI evidence method already exists: {name}")

last_close = source.rfind("\n}")
if last_close < 0:
    raise RuntimeError("UI test class closing brace not found")

methods = r'''

    @MainActor
    func testV14SimulatorQAHorizonReadyDynamicTypeSurfacesHaveRetainedAccessibilityEvidence() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=observationHorizonReady",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let shell = app.descendants(matching: .any)["es80.capture-shell"]
        let qaDisclosure = app.descendants(matching: .any)["es80.capture.simulator-qa"]
        let passiveMode = app.staticTexts["PASSIVE / READ ONLY"]
        let progress = app.descendants(matching: .any)["es80.capture.experiment-progress"]
        let health = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Capture health."))
            .firstMatch
        let finish = app.descendants(matching: .any)["es80.capture.finish"]

        XCTAssertTrue(shell.waitForExistence(timeout: 5))
        XCTAssertTrue(qaDisclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(passiveMode.waitForExistence(timeout: 3))
        XCTAssertTrue(progress.waitForExistence(timeout: 3))
        XCTAssertTrue(health.waitForExistence(timeout: 3))
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.field-no-go"].exists)
        XCTAssertFalse(app.buttons["Vehicle controls"].exists)

        let topFrame = app.windows.firstMatch.frame
        assertVisibleInScreenshotViewport(
            qaDisclosure,
            windowFrame: topFrame,
            context: "synthetic disclosure beside Horizon-ready hero at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            passiveMode,
            windowFrame: topFrame,
            context: "recomposed PASSIVE / READ ONLY hero state at Accessibility XXXL"
        )

        let heroAttachment = XCTAttachment(screenshot: app.screenshot())
        heroAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Horizon Ready Hero — Accessibility XXXL"
        heroAttachment.lifetime = .keepAlways
        add(heroAttachment)

        bringIntoScreenshotViewport(
            progress,
            in: app,
            context: "paired Horizon-ready Capture progress at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            progress,
            windowFrame: app.windows.firstMatch.frame,
            context: "paired Horizon-ready Capture progress at Accessibility XXXL"
        )
        let progressAttachment = XCTAttachment(screenshot: app.screenshot())
        progressAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Horizon Ready Progress — Accessibility XXXL"
        progressAttachment.lifetime = .keepAlways
        add(progressAttachment)

        bringIntoScreenshotViewport(
            health,
            in: app,
            context: "stacked Capture health at Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            health,
            windowFrame: app.windows.firstMatch.frame,
            context: "stacked Capture health at Accessibility XXXL"
        )
        let healthAttachment = XCTAttachment(screenshot: app.screenshot())
        healthAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Capture Health — Accessibility XXXL"
        healthAttachment.lifetime = .keepAlways
        add(healthAttachment)

        bringIntoScreenshotViewport(
            finish,
            in: app,
            context: "Seal Capture after large-text instrumentation review"
        )
        assertVisibleInScreenshotViewport(
            finish,
            windowFrame: app.windows.firstMatch.frame,
            context: "Seal Capture after large-text instrumentation review"
        )
        let sealAttachment = XCTAttachment(screenshot: app.screenshot())
        sealAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Horizon Ready Seal — Accessibility XXXL"
        sealAttachment.lifetime = .keepAlways
        add(sealAttachment)
    }

    @MainActor
    func testV14SimulatorQAHorizonReadyProgressHasRetainedLandscapeEvidence() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=observationHorizonReady"
        ]
        app.launch()

        let shell = app.descendants(matching: .any)["es80.capture-shell"]
        XCTAssertTrue(shell.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft

        let qaDisclosure = app.descendants(matching: .any)["es80.capture.simulator-qa"]
        let progress = app.descendants(matching: .any)["es80.capture.experiment-progress"]
        let finish = app.descendants(matching: .any)["es80.capture.finish"]
        XCTAssertTrue(qaDisclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(progress.waitForExistence(timeout: 3))
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.field-no-go"].exists)

        let landscapeFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(
            landscapeFrame.width,
            landscapeFrame.height,
            "The progress evidence path must actually run in landscape."
        )

        bringIntoScreenshotViewport(
            progress,
            in: app,
            context: "Horizon-ready Capture progress in landscape"
        )
        assertVisibleInScreenshotViewport(
            progress,
            windowFrame: app.windows.firstMatch.frame,
            context: "Horizon-ready Capture progress in landscape"
        )

        let progressAttachment = XCTAttachment(screenshot: app.screenshot())
        progressAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Horizon Ready Progress — Landscape"
        progressAttachment.lifetime = .keepAlways
        add(progressAttachment)

        bringIntoScreenshotViewport(
            finish,
            in: app,
            context: "Seal Capture after landscape progress review"
        )
        assertVisibleInScreenshotViewport(
            finish,
            windowFrame: app.windows.firstMatch.frame,
            context: "Seal Capture after landscape progress review"
        )
    }
'''

source = source[:last_close] + methods + source[last_close:]
path.write_text(source)

# Source-level guard: the new runtime evidence must target the real positive shell,
# explicit synthetic QA seam, accessibility category, progress semantics, and screenshots.
written = path.read_text()
for required in (
    "--es80-passive-capture-simulator-qa",
    "--es80-capture-qa-scenario=observationHorizonReady",
    "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
    "es80.capture-shell",
    "es80.capture.simulator-qa",
    "PASSIVE / READ ONLY",
    "es80.capture.experiment-progress",
    "Capture health.",
    "es80.capture.finish",
    "Horizon Ready Progress — Accessibility XXXL",
    "Capture Health — Accessibility XXXL",
    "Horizon Ready Progress — Landscape",
):
    if required not in written:
        raise RuntimeError(f"required evidence marker missing after transform: {required}")
