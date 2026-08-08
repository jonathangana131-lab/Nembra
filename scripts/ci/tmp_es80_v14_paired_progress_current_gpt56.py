from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one exact anchor, found {count}")
    return text.replace(old, new, 1)


shell_path = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
shell = shell_path.read_text()

scene_anchor = "    @Environment(\\.scenePhase) private var scenePhase\n"
shell = replace_once(
    shell,
    scene_anchor,
    scene_anchor + "    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n",
    "dynamic type environment",
)

old_progress = '''            HStack(spacing: 6) {
                ForEach(0..<6, id: \\.self) { index in
                    Capsule(style: .continuous)
                        .fill(progressSegmentFill(
                            index: index,
                            completedWindows: completed,
                            currentWindow: current,
                            status: status
                        ))
                        .frame(height: 5)
                }
            }

            HStack {
                Text("OFF 1")
                Spacer()
                Text("ON 1")
                Spacer()
                Text("OFF 2")
                Spacer()
                Text("ON 2")
                Spacer()
                Text("READY")
                Spacer()
                Text("SEAL")
            }
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(.secondary)
'''
new_progress = '''            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \\.self) { index in
                            accessibilityProgressStage(
                                index: index,
                                completedWindows: completed,
                                currentWindow: current,
                                status: status
                            )
                        }
                    }

                    HStack(spacing: 8) {
                        ForEach(3..<6, id: \\.self) { index in
                            accessibilityProgressStage(
                                index: index,
                                completedWindows: completed,
                                currentWindow: current,
                                status: status
                            )
                        }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(0..<6, id: \\.self) { index in
                        Capsule(style: .continuous)
                            .fill(progressSegmentFill(
                                index: index,
                                completedWindows: completed,
                                currentWindow: current,
                                status: status
                            ))
                            .frame(height: 5)
                    }
                }

                HStack {
                    Text("OFF 1")
                    Spacer()
                    Text("ON 1")
                    Spacer()
                    Text("OFF 2")
                    Spacer()
                    Text("ON 2")
                    Spacer()
                    Text("READY")
                    Spacer()
                    Text("SEAL")
                }
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
            }
'''
shell = replace_once(shell, old_progress, new_progress, "paired accessibility progress rail")

primary_anchor = '''    @ViewBuilder
    private func primaryContent(
'''
helper = '''    private func accessibilityProgressStage(
        index: Int,
        completedWindows: Int,
        currentWindow: PassiveBluetoothPowerCycleObservationPhase?,
        status: PassiveBluetoothExperimentOneCoordinator.Status
    ) -> some View {
        VStack(spacing: 6) {
            Capsule(style: .continuous)
                .fill(progressSegmentFill(
                    index: index,
                    completedWindows: completedWindows,
                    currentWindow: currentWindow,
                    status: status
                ))
                .frame(height: 5)

            Text(progressStageLabel(index: index))
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func progressStageLabel(index: Int) -> String {
        switch index {
        case 0: "OFF 1"
        case 1: "ON 1"
        case 2: "OFF 2"
        case 3: "ON 2"
        case 4: "READY"
        case 5: "SEAL"
        default: ""
        }
    }

'''
shell = replace_once(shell, primary_anchor, helper + primary_anchor, "accessibility progress helper")
shell_path.write_text(shell)

ui_path = Path("NembraUITests/ES80ResearchCaptureUITests.swift")
ui = ui_path.read_text()
landscape_anchor = '''    @MainActor
    func testV14SimulatorQAHorizonReadyLandscapeKeepsFinishAndTruthVisible() {
'''
accessibility_test = r'''    @MainActor
    func testV14SimulatorQAHorizonReadyProgressRecomposesAtAccessibilityExtraExtraExtraLarge() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--es80-passive-capture-simulator-qa",
            "--es80-capture-qa-scenario=observationHorizonReady",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let qaDisclosure = app.descendants(matching: .any)["es80.capture.simulator-qa"]
        let progress = app.descendants(matching: .any)["es80.capture.experiment-progress"]
        let finish = app.descendants(matching: .any)["es80.capture.finish"]

        XCTAssertTrue(app.descendants(matching: .any)["es80.capture-shell"].waitForExistence(timeout: 5))
        XCTAssertTrue(qaDisclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(progress.waitForExistence(timeout: 3))
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.field-no-go"].exists)

        let windowFrame = app.windows.firstMatch.frame
        assertVisibleInScreenshotViewport(
            qaDisclosure,
            windowFrame: windowFrame,
            context: "synthetic Simulator QA disclosure at positive-state Accessibility XXXL"
        )
        assertVisibleInScreenshotViewport(
            progress,
            windowFrame: windowFrame,
            context: "paired positive Capture progress rail at Accessibility XXXL"
        )

        let progressAttachment = XCTAttachment(screenshot: app.screenshot())
        progressAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Paired Progress — Accessibility XXXL"
        progressAttachment.lifetime = .keepAlways
        add(progressAttachment)

        for _ in 0..<4 {
            if finish.frame.intersects(windowFrame) { break }
            app.swipeUp()
        }
        assertVisibleInScreenshotViewport(
            finish,
            windowFrame: windowFrame,
            context: "Seal Capture action after inspecting paired progress at Accessibility XXXL"
        )

        let sealAttachment = XCTAttachment(screenshot: app.screenshot())
        sealAttachment.name = "Nembra Capture V14 — SIMULATOR QA — Seal — Accessibility XXXL"
        sealAttachment.lifetime = .keepAlways
        add(sealAttachment)
    }

'''
ui = replace_once(ui, landscape_anchor, accessibility_test + landscape_anchor, "Horizon-ready accessibility UI acceptance")

ui = replace_once(
    ui,
    '''        let qaDisclosure = app.descendants(matching: .any)["es80.capture.simulator-qa"]
        let readyState = app.staticTexts["Capture can be sealed"]
        let finish = app.descendants(matching: .any)["es80.capture.finish"]
''',
    '''        let qaDisclosure = app.descendants(matching: .any)["es80.capture.simulator-qa"]
        let progress = app.descendants(matching: .any)["es80.capture.experiment-progress"]
        let readyState = app.staticTexts["Capture can be sealed"]
        let finish = app.descendants(matching: .any)["es80.capture.finish"]
''',
    "landscape progress element",
)
ui = replace_once(
    ui,
    '''        XCTAssertTrue(qaDisclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(readyState.waitForExistence(timeout: 3))
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
''',
    '''        XCTAssertTrue(qaDisclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(progress.waitForExistence(timeout: 3))
        XCTAssertTrue(readyState.waitForExistence(timeout: 3))
        XCTAssertTrue(finish.waitForExistence(timeout: 3))
''',
    "landscape progress existence",
)
ui = replace_once(
    ui,
    '''        assertVisibleInScreenshotViewport(
            readyState,
            windowFrame: windowFrame,
            context: "Horizon-ready state in landscape"
        )
''',
    '''        assertVisibleInScreenshotViewport(
            progress,
            windowFrame: windowFrame,
            context: "positive Capture progress rail in landscape"
        )
        assertVisibleInScreenshotViewport(
            readyState,
            windowFrame: windowFrame,
            context: "Horizon-ready state in landscape"
        )
''',
    "landscape progress viewport",
)
ui_path.write_text(ui)

# Fail closed before any product commit.
shell = shell_path.read_text()
ui = ui_path.read_text()
assert "@Environment(\\.dynamicTypeSize) private var dynamicTypeSize" in shell
assert "if dynamicTypeSize.isAccessibilitySize" in shell
assert "ForEach(0..<3" in shell and "ForEach(3..<6" in shell
assert "accessibilityProgressStage" in shell
assert "progressStageLabel(index: index)" in shell
assert "testV14SimulatorQAHorizonReadyProgressRecomposesAtAccessibilityExtraExtraExtraLarge" in ui
assert 'context: "paired positive Capture progress rail at Accessibility XXXL"' in ui
assert 'context: "positive Capture progress rail in landscape"' in ui
