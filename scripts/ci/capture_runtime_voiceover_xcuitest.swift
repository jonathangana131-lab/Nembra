
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
        XCTAssertFalse(
            app.descendants(matching: .any)["Start capture"].exists,
            "Public/unprovisioned runtime hierarchy must not expose a physical Capture action anywhere, including offscreen or under a non-button element type."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["Scan for scooter"].exists,
            "Public/unprovisioned runtime hierarchy must not expose Bluetooth scan authority anywhere, including offscreen or under a non-button element type."
        )

        // Use the runner's complete supported audit set instead of naming
        // individual cases. Xcode 27 beta 4's Swift overlay does not expose
        // every case documented by newer Apple SDKs, while `.all` remains the
        // fail-closed contract: every audit category supported by this exact
        // runner executes, including any categories added by a later SDK.
        try app.performAccessibilityAudit(for: .all)

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

        // Retain whatever VoiceOver actually spoke even when a strict
        // moveForward() call throws. The throw stays fail-closed. The same
        // transcript is mirrored to the XCTest/job log with a true 16 KiB
        // UTF-8 byte ceiling so non-ASCII speech cannot silently exceed the
        // evidence bound advertised by this runtime contract.
        defer {
            let retainedTranscript = utterances.enumerated()
                .map { "\($0.offset): \($0.element)" }
                .joined(separator: "\n")
            let attachment = XCTAttachment(string: retainedTranscript)
            attachment.name = "Capture VoiceOver Runtime Transcript"
            attachment.lifetime = .keepAlways
            add(attachment)

            let retainedLogByteLimit = 16 * 1024
            let retainedTranscriptByteCount = retainedTranscript.utf8.count
            var retainedLogPrefix = ""
            retainedLogPrefix.reserveCapacity(
                min(retainedTranscript.count, retainedLogByteLimit)
            )
            var retainedLogByteCount = 0
            for character in retainedTranscript {
                let characterByteCount = String(character).utf8.count
                guard retainedLogByteCount + characterByteCount <= retainedLogByteLimit else {
                    break
                }
                retainedLogPrefix.append(character)
                retainedLogByteCount += characterByteCount
            }

            print("NEMBRA_CAPTURE_VOICEOVER_TRANSCRIPT_BEGIN")
            print(retainedLogPrefix)
            if retainedLogByteCount < retainedTranscriptByteCount {
                print("NEMBRA_CAPTURE_VOICEOVER_TRANSCRIPT_TRUNCATED")
            }
            print("NEMBRA_CAPTURE_VOICEOVER_TRANSCRIPT_END")
        }

        if let current = try? service.currentSpeech().utterance, !current.isEmpty {
            utterances.append(current)
        }

        // Traverse a bounded horizon even after the required phrases appear so
        // later forbidden authority cannot hide behind an early success break.
        // Until retained runtime evidence demonstrates a specific terminal
        // VoiceOver boundary error, every moveForward failure is fail-closed.
        for _ in 0..<64 {
            let output = try service.moveForward()
            let utterance = output.utterance
            if !utterance.isEmpty {
                utterances.append(utterance)
            }
        }

        let transcript = utterances.enumerated()
            .map { "\($0.offset): \($0.element)" }
            .joined(separator: "\n")

        let normalizedTranscript = transcript.lowercased()
        let positions = try requiredSpeech.map { phrase -> String.Index in
            guard let range = normalizedTranscript.range(of: phrase.lowercased()) else {
                XCTFail("VoiceOver never spoke required semantic phrase '\(phrase)'. Transcript:\n\(transcript)")
                throw RuntimeVoiceOverContractError.missingSpeech(phrase)
            }
            return range.lowerBound
        }
        for (earlier, later) in zip(positions, positions.dropFirst()) {
            XCTAssertLessThan(
                earlier,
                later,
                "VoiceOver speech must preserve lock authority -> user-code field -> approval QR -> engineering disclosure ordering, including when one utterance contains multiple semantic phrases. Transcript:\n\(transcript)"
            )
        }

        XCTAssertFalse(
            transcript.localizedCaseInsensitiveContains("Start capture"),
            "Public/unprovisioned VoiceOver traversal must not expose a physical Capture action anywhere in the bounded traversal horizon."
        )
        XCTAssertFalse(
            transcript.localizedCaseInsensitiveContains("Scan for scooter"),
            "Runtime accessibility traversal must not manufacture Bluetooth/physical authority anywhere in the bounded traversal horizon."
        )
    }

    private enum RuntimeVoiceOverContractError: Error {
        case missingSpeech(String)
    }
}