#!/usr/bin/env python3
from pathlib import Path

ui_path = Path("NembraUITests/ES80ResearchCaptureUITests.swift")
ui = ui_path.read_text(encoding="utf-8")
start = ui.index("func testV14SimulatorQACapturesRepresentativeInProgressAndRecoveryStates()")
end = ui.index("func testSimulatorQAAppSeamIsCompileBoundedAndProductionRouteRemainsLocked()", start)
matrix = ui[start:end]

old = '''            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = expectation.screenshotName
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
'''
new = '''            let qaDisclosure = app.descendants(matching: .any)["es80.capture.simulator-qa"]
            let requiredState = app.staticTexts[expectation.requiredText]

            assertVisibleInScreenshotViewport(
                qaDisclosure,
                windowFrame: app.windows.firstMatch.frame,
                context: "Simulator QA disclosure for \\(expectation.scenario)"
            )
            let disclosureAttachment = XCTAttachment(screenshot: app.screenshot())
            disclosureAttachment.name = "\\(expectation.screenshotName) — Disclosure"
            disclosureAttachment.lifetime = .keepAlways
            add(disclosureAttachment)

            bringIntoScreenshotViewport(
                requiredState,
                in: app,
                context: "rider-facing state for \\(expectation.scenario)"
            )
            assertVisibleInScreenshotViewport(
                requiredState,
                windowFrame: app.windows.firstMatch.frame,
                context: "rider-facing state for \\(expectation.scenario)"
            )
            let stateAttachment = XCTAttachment(screenshot: app.screenshot())
            stateAttachment.name = "\\(expectation.screenshotName) — State"
            stateAttachment.lifetime = .keepAlways
            add(stateAttachment)

            if let identifier = expectation.requiredIdentifier {
                let requiredAction = app.descendants(matching: .any)[identifier]
                bringIntoScreenshotViewport(
                    requiredAction,
                    in: app,
                    context: "required action for \\(expectation.scenario)"
                )
                assertVisibleInScreenshotViewport(
                    requiredAction,
                    windowFrame: app.windows.firstMatch.frame,
                    context: "required action for \\(expectation.scenario)"
                )
                let actionAttachment = XCTAttachment(screenshot: app.screenshot())
                actionAttachment.name = "\\(expectation.screenshotName) — Action"
                actionAttachment.lifetime = .keepAlways
                add(actionAttachment)
            }

            app.terminate()
'''

if matrix.count(old) != 1:
    raise SystemExit(f"expected exactly one representative screenshot block, found {matrix.count(old)}")

matrix = matrix.replace(old, new, 1)
ui = ui[:start] + matrix + ui[end:]
ui_path.write_text(ui, encoding="utf-8")

ui = ui_path.read_text(encoding="utf-8")
start = ui.index("func testV14SimulatorQACapturesRepresentativeInProgressAndRecoveryStates()")
end = ui.index("func testSimulatorQAAppSeamIsCompileBoundedAndProductionRouteRemainsLocked()", start)
matrix = ui[start:end]

if matrix.count("assertVisibleInScreenshotViewport(") < 3:
    raise SystemExit("representative matrix lacks disclosure/state/action viewport proof")
if matrix.count("bringIntoScreenshotViewport(") < 2:
    raise SystemExit("representative matrix lacks bounded viewport navigation")
if matrix.index("assertVisibleInScreenshotViewport(") > matrix.index("XCTAttachment(screenshot: app.screenshot())"):
    raise SystemExit("representative screenshot occurs before viewport proof")

for token in (
    '"es80.capture.simulator-qa"',
    "expectation.requiredText",
    "expectation.requiredIdentifier",
    "— Disclosure",
    "— State",
    "— Action",
    "es80.capture.field-no-go",
    "Vehicle controls",
):
    if token not in matrix:
        raise SystemExit(f"representative viewport contract missing: {token}")

acceptance_path = Path(
    "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/"
    "ES80CaptureRepresentativeViewportAcceptanceTests.swift"
)
acceptance = acceptance_path.read_text(encoding="utf-8")
for token in (
    "assertionCount >= 3",
    "navigationCount >= 2",
    'matrix.contains("es80.capture.simulator-qa")',
    'matrix.contains("expectation.requiredText")',
    'matrix.contains("expectation.requiredIdentifier")',
):
    if token not in acceptance:
        raise SystemExit(f"permanent source acceptance missing: {token}")

print("representative viewport repair contract PASS")
