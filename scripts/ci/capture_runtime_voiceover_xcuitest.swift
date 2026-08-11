
// Appended at CI runtime to NembraUITests.swift by capture-runtime-voiceover.yml.
// This source is deliberately not part of the normal Nembra UI-test target so
// the accepted app-visible product head remains byte-for-byte unchanged.
final class CaptureRuntimeVoiceOverUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 180
    }

    @MainActor
    func testStandaloneCaptureRuntimeVoiceOverTraversalAndAudit() throws {
        let app = XCUIApplication(bundleIdentifier: "com.jonathangana131.nembra.capturelearn")
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 8),
            "The exact standalone Capture app must be installed and launchable before runtime accessibility evidence is valid."
        )

        XCTAssertTrue(
            app.staticTexts["Physical capture locked"].waitForExistence(timeout: 5),
            "Runtime accessibility evidence must remain on the public/unprovisioned fail-closed Capture root."
        )
        XCTAssertTrue(
            app.textFields["Tuya Smart user code"].waitForExistence(timeout: 3),
            "The runtime text field must expose its full semantic label rather than only the sighted AX placeholder."
        )
        XCTAssertTrue(
            app.buttons["Create approval QR"].waitForExistence(timeout: 3),
            "The approval-only action must expose the full semantic label at runtime."
        )
        XCTAssertTrue(
            app.buttons["Engineering details"].waitForExistence(timeout: 3),
            "The compact sighted Details disclosure must retain the full Engineering details semantic label."
        )

        try app.performAccessibilityAudit(
            for: [
                .sufficientElementDescription,
                .hitRegion,
                .dynamicType,
                .textClipped,
                .trait,
                .parentChild,
                .elementDetection,
                .action
            ]
        )

        let service = XCUIDevice.shared.voiceOverService
        if service.isEnabled {
            try service.disable()
        }
        try service.enable()
        defer {
            if service.isEnabled {
                try? service.disable()
            }
        }

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 3))

        let requiredSpeech = [
            "Physical capture locked",
            "Tuya Smart user code",
            "Create approval QR",
            "Engineering details"
        ]
        var utterances: [String] = []

        if let current = try? service.currentSpeech().utterance, !current.isEmpty {
            utterances.append(current)
        }

        for _ in 0..<64 {
            let output = try service.moveForward()
            let utterance = output.utterance
            if !utterance.isEmpty {
                utterances.append(utterance)
            }
            if requiredSpeech.allSatisfy({ phrase in
                utterances.contains(where: { $0.localizedCaseInsensitiveContains(phrase) })
            }) {
                break
            }
        }

        let transcript = utterances.enumerated()
            .map { "\($0.offset): \($0.element)" }
            .joined(separator: "\n")
        let attachment = XCTAttachment(string: transcript)
        attachment.name = "Capture VoiceOver Runtime Transcript"
        attachment.lifetime = .keepAlways
        add(attachment)

        let indices = try requiredSpeech.map { phrase -> Int in
            guard let index = utterances.firstIndex(where: { $0.localizedCaseInsensitiveContains(phrase) }) else {
                XCTFail("VoiceOver never spoke required semantic phrase '\(phrase)'. Transcript:\n\(transcript)")
                throw RuntimeVoiceOverContractError.missingSpeech(phrase)
            }
            return index
        }

        XCTAssertEqual(
            indices,
            indices.sorted(),
            "VoiceOver traversal must preserve lock authority -> user-code field -> approval QR -> engineering disclosure ordering. Transcript:\n\(transcript)"
        )

        XCTAssertFalse(
            transcript.localizedCaseInsensitiveContains("Start capture"),
            "Public/unprovisioned VoiceOver traversal must not expose a physical Capture action."
        )
        XCTAssertFalse(
            transcript.localizedCaseInsensitiveContains("Scan for scooter"),
            "Runtime accessibility traversal must not manufacture Bluetooth/physical authority."
        )
    }

    private enum RuntimeVoiceOverContractError: Error {
        case missingSpeech(String)
    }
}
