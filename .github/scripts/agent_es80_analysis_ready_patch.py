from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one anchor, found {count}")
    return text.replace(old, new, 1)


shell_path = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
shell = shell_path.read_text()

shell = replace_once(
    shell,
    """    @State private var shareURL: URL?
    @State private var softwareExportData: Data?
    @State private var sharePreparationWarning: String?
    @State private var declaredStationarySetup: PassiveBluetoothStationaryCaptureSetup?""",
    """    @State private var shareURL: URL?
    @State private var finalShareData: Data?
    @State private var finalShareFilename: String?
    @State private var finalShareIntegrityReport: PassiveBluetoothExperimentOneFinalShareArtifactIntegrityReport?
    @State private var analysisReadinessWarning: String?
    @State private var sharePreparationWarning: String?
    @State private var sharePreparationInFlight = false
    @State private var declaredStationarySetup: PassiveBluetoothStationaryCaptureSetup?""",
    "capture share state",
)

shell = replace_once(
    shell,
    """            } else if coordinator.finalizedArtifact != nil {
                primaryButton(
                    \"Prepare Share file\",
                    systemImage: \"arrow.clockwise\",
                    identifier: \"es80.capture.prepare-share\"
                ) {
                    prepareSoftwareExportForShare()
                }
            } else {""",
    """            } else if coordinator.finalizedArtifact != nil {
                primaryButton(
                    sharePreparationInFlight
                        ? \"Preparing Share…\"
                        : (finalShareData == nil ? \"Prepare Share file\" : \"Retry Share file\"),
                    systemImage: \"arrow.clockwise\",
                    disabled: sharePreparationInFlight,
                    identifier: \"es80.capture.prepare-share\"
                ) {
                    prepareFinalShareForShare()
                }
            } else {""",
    "complete share retry button",
)

shell = replace_once(
    shell,
    """            if let sharePreparationWarning {
                diagnosticBanner(sharePreparationWarning)
            }
            secondaryButton(""",
    """            if let sharePreparationWarning {
                diagnosticBanner(sharePreparationWarning)
            }
            if let analysisReadinessWarning {
                diagnosticBanner(analysisReadinessWarning)
            }
            secondaryButton(""",
    "analysis warning presentation",
)

shell = replace_once(
    shell,
    """                VStack(alignment: .leading, spacing: 4) {
                    Text(\"CAPTURE COMPLETE\")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(\"Ready for analysis\")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }

            if let artifact = coordinator.finalizedArtifact {
                let exportDescription = softwareExportData.map { \" Package-owned Share envelope: \\($0.count.formatted()) bytes.\" } ?? \"\"
                Text(\"\\(artifact.captureJSON.count.formatted()) immutable capture bytes are sealed from this Experiment One authority. Correlation evidence remains bound to the same run.\\(exportDescription) No protocol field meaning is claimed yet.\")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }""",
    """                VStack(alignment: .leading, spacing: 4) {
                    Text(\"CAPTURE COMPLETE\")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(finalShareIntegrityReport == nil ? \"Capture sealed\" : \"Ready for analysis\")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }

            if let report = finalShareIntegrityReport {
                Text(\"The exact \\(report.finalShareByteCount.formatted())-byte final Share artifact passed package-owned outer, software-export, and nested Capture readability checks. It contains \\(report.softwareExport.capture.recordCount.formatted()) capture records, including \\(report.softwareExport.capture.rawValueRecordCount.formatted()) raw value records. These are software integrity facts only; no protocol field meaning or physical authorization is claimed.\")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let artifact = coordinator.finalizedArtifact {
                let shareDescription = finalShareData.map { \" A package-owned final Share artifact is retained in memory (\\($0.count.formatted()) bytes).\" } ?? \"\"
                Text(\"\\(artifact.captureJSON.count.formatted()) immutable capture bytes are sealed from this Experiment One authority. Correlation evidence remains bound to the same run.\\(shareDescription) Analysis readiness is not established until the exact final Share bytes pass the package integrity inspector.\")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }""",
    "completion analysis gate",
)

shell = replace_once(
    shell,
    """                    if let artifact = coordinator.finalizedArtifact {
                        detailRow(\"Capture bytes\", value: artifact.captureJSON.count.formatted())
                        detailRow(\"Observation windows\", value: artifact.powerCycleResult.windows.count.formatted())
                    }

                    Divider()

                    Text(\"Truth boundary\")
                        .font(.headline)
                    Text(\"This artifact is passive software evidence. Repeated full-UUID correlation does not authenticate the physical ES80, and this screen does not assign GATT, Tuya/DP, battery, current, power, speed, regen, or command semantics.\")""",
    """                    if let artifact = coordinator.finalizedArtifact {
                        detailRow(\"Capture bytes\", value: artifact.captureJSON.count.formatted())
                        detailRow(\"Observation windows\", value: artifact.powerCycleResult.windows.count.formatted())
                    }
                    detailRow(
                        \"Analysis readiness\",
                        value: finalShareIntegrityReport == nil ? \"Not established\" : \"Exact bytes readable\"
                    )
                    if let report = finalShareIntegrityReport {
                        detailRow(\"Final Share bytes\", value: report.finalShareByteCount.formatted())
                        detailRow(\"Final Share SHA-256\", value: report.finalShareSHA256)
                        detailRow(\"Procedure\", value: report.procedureVersion)
                        detailRow(\"Experiment\", value: report.experimentID.uuidString)
                        detailRow(\"Software export SHA-256\", value: report.softwareExport.envelopeSHA256)
                        detailRow(\"Capture SHA-256\", value: report.softwareExport.capture.sha256)
                        detailRow(\"Capture session\", value: report.softwareExport.capture.captureSessionID.uuidString)
                        detailRow(\"Records\", value: report.softwareExport.capture.recordCount.formatted())
                        detailRow(\"Raw value records\", value: report.softwareExport.capture.rawValueRecordCount.formatted())
                        detailRow(\"Build\", value: report.softwareExport.buildIdentifier)
                        detailRow(\"Build instance\", value: report.softwareExport.buildInstanceID)
                        detailRow(\"Source commit\", value: report.softwareExport.sourceCommitSHA)
                    } else if let finalShareData {
                        detailRow(\"Retained final Share bytes\", value: finalShareData.count.formatted())
                    }

                    Divider()

                    Text(\"Truth boundary\")
                        .font(.headline)
                    Text(\"This artifact is passive software evidence. Exact-file digests and successful local readability do not authenticate the physical ES80, prove RF completeness, attest the source-to-binary build chain, or authorize a field run. This screen does not assign GATT, Tuya/DP, battery, current, power, speed, regen, or command semantics.\")""",
    "capture details integrity facts",
)

shell = shell.replace("prepareSoftwareExportForShare()", "prepareFinalShareForShare()")

method_start = shell.index("    private func prepareSoftwareExportForShare() {") if "    private func prepareSoftwareExportForShare() {" in shell else shell.index("    private func prepareFinalShareForShare() {")
method_end = shell.index("    private func restartExperiment() {", method_start)
new_method = """    private func prepareFinalShareForShare() {
        guard !sharePreparationInFlight else { return }
        guard coordinator.finalizedArtifact != nil else { return }
        guard let setup = declaredStationarySetup else {
            sharePreparationWarning = \"Capture is sealed, but this run has no retained operator setup declaration. Start a fresh Experiment One rather than inventing setup provenance at export time.\"
            return
        }

        sharePreparationWarning = nil
        if let data = finalShareData, let filename = finalShareFilename {
            sharePreparationInFlight = true
            inspectAndStageFinalShare(data: data, filename: filename)
            return
        }

        do {
            let artifact = try coordinator.finalizedShareArtifactForCurrentApplication(setup: setup)
            finalShareData = artifact.json
            finalShareFilename = artifact.suggestedFilename
            sharePreparationInFlight = true
            inspectAndStageFinalShare(data: artifact.json, filename: artifact.suggestedFilename)
        } catch {
            sharePreparationInFlight = false
            sharePreparationWarning = \"Capture remains sealed, but the package-owned final Share artifact could not be prepared: \\(experimentErrorMessage(error))\"
        }
    }

    private func inspectAndStageFinalShare(data: Data, filename: String) {
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                try? PassiveBluetoothExperimentOneFinalShareArtifactIntegrity.inspect(data)
            }.value
            let stagedURL = await Task.detached(priority: .utility) { () -> URL? in
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                do {
                    try data.write(to: url, options: .atomic)
                    return url
                } catch {
                    return nil
                }
            }.value

            finalShareIntegrityReport = report
            if report == nil {
                analysisReadinessWarning = \"Capture is sealed and the exact final Share bytes are retained, but local analysis readiness could not be established. The artifact remains software evidence only and does not authorize field execution.\"
            } else {
                analysisReadinessWarning = nil
            }

            shareURL = stagedURL
            if stagedURL == nil {
                sharePreparationWarning = \"Capture remains sealed and its exact final Share bytes are retained, but the temporary Share file could not be staged. Retry reuses these same bytes and does not rerun Horizon.\"
            } else {
                sharePreparationWarning = nil
            }
            sharePreparationInFlight = false
        }
    }

"""
shell = shell[:method_start] + new_method + shell[method_end:]

shell = replace_once(
    shell,
    """        shareURL = nil
        softwareExportData = nil
        sharePreparationWarning = nil
        declaredStationarySetup = nil""",
    """        if let shareURL {
            try? FileManager.default.removeItem(at: shareURL)
        }
        shareURL = nil
        finalShareData = nil
        finalShareFilename = nil
        finalShareIntegrityReport = nil
        analysisReadinessWarning = nil
        sharePreparationWarning = nil
        sharePreparationInFlight = false
        declaredStationarySetup = nil""",
    "restart final share state",
)

persist_start = shell.find("    private func persistShareArtifact(_ data: Data) throws -> URL {")
if persist_start != -1:
    persist_end = shell.index("    private func experimentErrorMessage(_ error: Error) -> String {", persist_start)
    shell = shell[:persist_start] + shell[persist_end:]

shell = replace_once(
    shell,
    """        if status.artifactFinalized {
            return \"Experiment One progress, capture sealed and ready for analysis\"
        }""",
    """        if status.artifactFinalized {
            return finalShareIntegrityReport == nil
                ? \"Experiment One progress, capture sealed; analysis readiness not established\"
                : \"Experiment One progress, capture sealed and ready for analysis\"
        }""",
    "progress accessibility analysis gate",
)

shell_path.write_text(shell)

app_tests_path = Path("NembraAppTests/NembraAppTests.swift")
app_tests = app_tests_path.read_text()
old_test = """    func testCaptureShellContinuesSameAuthorityThroughSealAndShare() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let shell = try String(
            contentsOf: root.appendingPathComponent(\"NembraApp/Features/Research/ES80CaptureShellView.swift\"),
            encoding: .utf8
        )
        XCTAssertFalse(shell.contains(\"PassiveBluetoothPowerCycleObservationSession(\"))
        XCTAssertFalse(shell.contains(\"Passive capture binding not available in this build\"))
        XCTAssertTrue(shell.contains(\"coordinator.prepareCaptureRediscovery()\"))
        XCTAssertTrue(shell.contains(\"coordinator.connectPreparedCapture()\"))
        XCTAssertTrue(shell.contains(\"encodedFinalizedObservationHorizonJSON\"))
        XCTAssertTrue(shell.contains(\"ShareLink(item: finalizedCaptureURL)\"))
    }"""
new_test = """    func testCaptureShellContinuesSameAuthorityThroughSealAndFinalShareIntegrity() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let shell = try String(
            contentsOf: root.appendingPathComponent(\"NembraApp/Features/Research/ES80CaptureShellView.swift\"),
            encoding: .utf8
        )
        XCTAssertFalse(shell.contains(\"PassiveBluetoothPowerCycleObservationSession(\"))
        XCTAssertFalse(shell.contains(\"Passive capture binding not available in this build\"))
        XCTAssertTrue(shell.contains(\"coordinator.confirmCorrelatedTargetAndBeginRediscovery()\"))
        XCTAssertTrue(shell.contains(\"coordinator.connectPreparedCapture()\"))
        XCTAssertTrue(shell.contains(\"coordinator.finalizeObservationHorizon()\"))
        XCTAssertTrue(shell.contains(\"coordinator.finalizedShareArtifactForCurrentApplication(setup: setup)\"))
        XCTAssertTrue(shell.contains(\"PassiveBluetoothExperimentOneFinalShareArtifactIntegrity.inspect(data)\"))
        XCTAssertTrue(shell.contains(\"Text(finalShareIntegrityReport == nil ? \\\"Capture sealed\\\" : \\\"Ready for analysis\\\")\"))
        XCTAssertTrue(shell.contains(\"if let data = finalShareData, let filename = finalShareFilename\"))
        XCTAssertTrue(shell.contains(\"ShareLink(item: shareURL)\"))
        XCTAssertFalse(shell.contains(\"encodedFinalizedObservationHorizonJSON\"))
        XCTAssertFalse(shell.contains(\"encodedFinalizedSoftwareExportForCurrentApplication\"))
        XCTAssertFalse(shell.contains(\"persistShareArtifact(artifact.captureJSON)\"))
    }"""
app_tests = replace_once(app_tests, old_test, new_test, "wired app Capture regression")
app_tests_path.write_text(app_tests)

final_tests_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/PassiveBluetoothExperimentOneFinalShareArtifactTests.swift")
final_tests = final_tests_path.read_text()
insert_anchor = """    @Test
    func procedureVersionTamperFailsClosed() throws {"""
integrity_test = """    @Test
    func finalShareIntegrityReportsExactOuterAndNestedCaptureFacts() throws {
        let artifact = try makeArtifact()
        let report = try PassiveBluetoothExperimentOneFinalShareArtifactIntegrity
            .inspect(artifact.json)
        let verified = try PassiveBluetoothExperimentOneFinalShareArtifactCodec
            .decodeAndVerify(artifact.json)

        #expect(report.finalShareSHA256 == sha256Hex(artifact.json))
        #expect(report.finalShareByteCount == artifact.json.count)
        #expect(report.experimentID == verified.experimentID)
        #expect(report.experimentRecipeID == .es80FingerprintV1)
        #expect(report.procedureVersion == \"V14\")
        #expect(report.buildInstanceID == buildInstanceID.lowercased())
        #expect(report.softwareExport.envelopeSHA256 == verified.softwareExportSHA256)
        #expect(report.softwareExport.capture.captureSessionID == UUID(uuidString: \"01234567-89AB-CDEF-0123-456789ABCDEF\"))
        #expect(report.softwareExport.capture.recordCount == 2)
        #expect(report.softwareExport.capture.rawValueRecordCount == 1)
    }

    @Test
    func procedureVersionTamperFailsClosed() throws {"""
final_tests = replace_once(final_tests, insert_anchor, integrity_test, "final share integrity regression")
final_tests_path.write_text(final_tests)
