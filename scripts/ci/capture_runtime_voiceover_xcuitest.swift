
// Appended at CI runtime to NembraUITests.swift by capture-runtime-voiceover.yml.
// This source is deliberately not part of the normal Nembra UI-test target so
// the accepted app-visible product checkpoint remains byte-for-byte unchanged.
final class CaptureRuntimeVoiceOverUITests: XCTestCase {
    private let knownAX5SemanticTextClippedFalsePositives: Set<String> = [
        "Physical capture locked",
        "Tuya Smart user code"
    ]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 180
    }

    @MainActor
    func testStandaloneCaptureStandardVoiceOverPreservesFirstFoldAuthority() throws {
        let app = launchStandaloneCapture()
        let heroAuthority = "Link the Tuya Smart account that owns this scooter. Bluetooth and physical evidence stay locked until the reviewed field build and fresh scooter authority are verified."

        XCTAssertTrue(
            app.staticTexts["Link this scooter"].waitForExistence(timeout: 5),
            "Standard-size runtime evidence must exercise the compact accepted first-fold hero."
        )
        XCTAssertTrue(
            app.staticTexts[heroAuthority].waitForExistence(timeout: 3),
            "The compact sighted hero must retain the full nonlocalized spoken authority restored by the #2990 finding."
        )
        try assertSharedFailClosedHierarchy(app)
        try performSemanticOverrideAwareAccessibilityAudit(
            app,
            evidenceLabel: "standard",
            expectedFilteredTextClippedLabels: []
        )

        try assertVoiceOverTraversal(
            app: app,
            evidenceLabel: "standard",
            requiredSpeech: [
                "Link this scooter",
                "Link the Tuya Smart account that owns this scooter",
                "Bluetooth and physical evidence stay locked",
                "reviewed field build and fresh scooter authority",
                "Physical capture locked",
                "Tuya Smart user code",
                "Create approval QR",
                "Engineering details"
            ]
        )
    }

    @MainActor
    func testStandaloneCaptureAccessibilityXXXLVoiceOverRemainsActionFirst() throws {
        let app = launchStandaloneCapture()

        XCTAssertFalse(
            app.staticTexts["Link this scooter"].exists,
            "Accessibility XXXL intentionally removes the standard hero so action-first large-type composition remains compact."
        )
        try assertSharedFailClosedHierarchy(app)
        try performSemanticOverrideAwareAccessibilityAudit(
            app,
            evidenceLabel: "accessibility-xxxl",
            expectedFilteredTextClippedLabels: knownAX5SemanticTextClippedFalsePositives
        )

        try assertVoiceOverTraversal(
            app: app,
            evidenceLabel: "accessibility-xxxl",
            requiredSpeech: [
                "Physical capture locked",
                "Tuya Smart user code",
                "Create approval QR",
                "Engineering details"
            ]
        )
    }

    @MainActor
    private func launchStandaloneCapture() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jonathangana131.nembra.capturelearn")
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 8),
            "The exact standalone Capture app must be installed and launchable before runtime accessibility evidence is valid."
        )
        return app
    }

    @MainActor
    private func assertSharedFailClosedHierarchy(_ app: XCUIApplication) throws {
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
            "Public/unprovisioned runtime hierarchy must not expose a physical Capture action anywhere."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["Scan for scooter"].exists,
            "Public/unprovisioned runtime hierarchy must not expose Bluetooth scan authority anywhere."
        )
    }

    @MainActor
    private func performSemanticOverrideAwareAccessibilityAudit(
        _ app: XCUIApplication,
        evidenceLabel: String,
        expectedFilteredTextClippedLabels: Set<String>
    ) throws {
        var filteredTextClippedLabels = Set<String>()
        defer {
            let retained = filteredTextClippedLabels.sorted().joined(separator: "\n")
            let attachment = XCTAttachment(string: retained)
            attachment.name = "Capture Accessibility Audit Filtered Issues - \(evidenceLabel)"
            attachment.lifetime = .keepAlways
            add(attachment)

            print("NEMBRA_CAPTURE_AX_FILTERED_BEGIN \(evidenceLabel)")
            for label in filteredTextClippedLabels.sorted() {
                print(label)
            }
            print("NEMBRA_CAPTURE_AX_FILTERED_END \(evidenceLabel)")
        }

        try app.performAccessibilityAudit(for: .all) { issue in
            guard issue.auditType == .textClipped,
                  let label = issue.element?.label,
                  expectedFilteredTextClippedLabels.contains(label) else {
                // Every non-exact issue remains fail-closed. In particular,
                // other textClipped findings are never hidden by this contract.
                return false
            }
            filteredTextClippedLabels.insert(label)
            return true
        }

        XCTAssertEqual(
            filteredTextClippedLabels,
            expectedFilteredTextClippedLabels,
            "The semantic-label textClipped exception set changed in \(evidenceLabel). Reclassify retained toolchain/product evidence instead of silently carrying a stale audit exception."
        )
    }

    @MainActor
    private func assertVoiceOverTraversal(
        app: XCUIApplication,
        evidenceLabel: String,
        requiredSpeech: [String]
    ) throws {
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

        var utterances: [String] = []
        defer {
            retainTranscript(utterances, evidenceLabel: evidenceLabel)
        }

        if let current = try? service.currentSpeech().utterance, !current.isEmpty {
            utterances.append(current)
        }

        // Keep traversing after all required phrases could have appeared so a
        // later forbidden authority element cannot hide behind an early break.
        // Every moveForward error remains fail-closed until retained evidence
        // demonstrates a specific terminal-boundary contract worth encoding.
        for _ in 0..<64 {
            let output = try service.moveForward()
            if !output.utterance.isEmpty {
                utterances.append(output.utterance)
            }
        }

        let transcript = utterances.enumerated()
            .map { "\($0.offset): \($0.element)" }
            .joined(separator: "\n")
        let normalizedTranscript = transcript.lowercased()

        let positions = try requiredSpeech.map { phrase -> String.Index in
            guard let range = normalizedTranscript.range(of: phrase.lowercased()) else {
                XCTFail("VoiceOver never spoke required semantic phrase '\(phrase)' in \(evidenceLabel). Transcript:\n\(transcript)")
                throw RuntimeVoiceOverContractError.missingSpeech(phrase)
            }
            return range.lowerBound
        }
        for (earlier, later) in zip(positions, positions.dropFirst()) {
            XCTAssertLessThan(
                earlier,
                later,
                "VoiceOver speech ordering is not action/truth preserving in \(evidenceLabel). Transcript:\n\(transcript)"
            )
        }

        XCTAssertFalse(
            transcript.localizedCaseInsensitiveContains("Start capture"),
            "Public/unprovisioned VoiceOver traversal must not expose a physical Capture action."
        )
        XCTAssertFalse(
            transcript.localizedCaseInsensitiveContains("Scan for scooter"),
            "Runtime accessibility traversal must not manufacture Bluetooth/physical authority."
        )
    }

    private func retainTranscript(_ utterances: [String], evidenceLabel: String) {
        let retainedTranscript = utterances.enumerated()
            .map { "\($0.offset): \($0.element)" }
            .joined(separator: "\n")
        let attachment = XCTAttachment(string: retainedTranscript)
        attachment.name = "Capture VoiceOver Runtime Transcript - \(evidenceLabel)"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Mirror a bounded diagnostic to the Actions log even when artifact
        // service retention is unavailable. Bound true UTF-8 bytes while
        // retaining complete Swift Characters.
        let retainedLogByteLimit = 16 * 1024
        let retainedTranscriptByteCount = retainedTranscript.utf8.count
        var retainedLogPrefix = ""
        retainedLogPrefix.reserveCapacity(min(retainedTranscript.count, retainedLogByteLimit))
        var retainedLogByteCount = 0
        for character in retainedTranscript {
            let characterByteCount = String(character).utf8.count
            guard retainedLogByteCount + characterByteCount <= retainedLogByteLimit else {
                break
            }
            retainedLogPrefix.append(character)
            retainedLogByteCount += characterByteCount
        }

        print("NEMBRA_CAPTURE_VOICEOVER_TRANSCRIPT_BEGIN \(evidenceLabel)")
        print(retainedLogPrefix)
        if retainedLogByteCount < retainedTranscriptByteCount {
            print("NEMBRA_CAPTURE_VOICEOVER_TRANSCRIPT_TRUNCATED \(evidenceLabel)")
        }
        print("NEMBRA_CAPTURE_VOICEOVER_TRANSCRIPT_END \(evidenceLabel)")
    }

    private enum RuntimeVoiceOverContractError: Error {
        case missingSpeech(String)
    }
}
