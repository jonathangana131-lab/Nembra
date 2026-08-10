from pathlib import Path

parent = "a267d0b6d16c1fee881dd23bc2ca5abc15baf9fe"
app = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = app.read_text(encoding="utf-8")

field_anchor = "    private var membershipRequestID = UUID()\n"
if source.count(field_anchor) != 1:
    raise SystemExit("membership generation anchor drifted")
source = source.replace(
    field_anchor,
    field_anchor + "    private var secureLinkViewGeneration = UUID()\n",
    1,
)

start_token = "    func abandonCorrelationForViewExit() {"
end_token = "\n\n    var privateConfig: Bool"
if source.count(start_token) != 1:
    raise SystemExit("view-exit helper anchor drifted")
start = source.index(start_token)
end = source.index(end_token, start)
replacement = '''    func abandonCorrelationForViewExit() {
        // View visibility is an app-local evidence-authority boundary. Rotate it synchronously so
        // no already-admitted async task can start or promote official Tuya work after navigation.
        secureLinkViewGeneration = UUID()

        membershipRequestID = UUID()
        membershipBusy = false
#if canImport(ThingSmartHomeKit)
        membershipProbe = nil
#endif

        if phase == .authenticating || phase == .observing {
            watchdog?.cancel()
            watchdog = nil
            let tokenAtExit = currentConnectionToken
            phase = .failed
            message = "Secure Link left the screen during authenticated-session work. Relaunch Capture and restart from OFF1; no Bluetooth disconnect is claimed."
            log("secure_link_view_exit_retired_official_authority")

            if let tokenAtExit {
                Task { @MainActor [weak self] in
                    guard let self, self.currentConnectionToken == tokenAtExit else { return }
                    await self.invalidateInternalLifecycle(
                        token: tokenAtExit,
                        message: "Secure Link left the screen during authenticated-session work. Relaunch Capture and restart from OFF1; no Bluetooth disconnect is claimed.",
                        kind: "secure_link_view_exit_retired_official_authority"
                    )
                }
            } else {
                localBLESettlementToken = nil
                sdkLocalBLEOnline = false
                driver = nil
            }
        }

        guard processCorrelationLease != nil || correlationSession != nil else { return }
        // Existing helper stops package transport before releasing this controller's lease.
        abandonPackageCorrelation()
        phase = .failed
        message = "Bluetooth correlation was interrupted when Capture left Secure Link. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series."
        log("target_correlation_abandoned_on_view_exit")
    }'''
source = source[:start] + replacement + source[end:]

method_start = source.index("    private func beginOfficialConnection(candidate: Candidate) {")
method_end = source.index("\n    private func authenticated(token:", method_start)
method = source[method_start:method_end]

authority_guard = '''        guard targetCorrelationOperatorConfirmed,
              selectedID == candidate.id,
              candidate.likely,
              buildIdentity.isAuthoritativeFieldBuild,
              sdkDeviceMembershipVerified,
              sdkAccountLoggedIn,
              accountIdentityLeaseIsAuthorized else {
            failLocally("Confirmed build or Tuya account/device authority changed before connection start.", "sdk_authority_changed")
            return
        }
'''
if method.count(authority_guard) != 1:
    raise SystemExit("official connection authority guard drifted")
method = method.replace(authority_guard, authority_guard + "        let viewGeneration = secureLinkViewGeneration\n", 1)

initial_task_guard = "            guard let self else { return }\n            do {\n                let token = try await self.sessionLedger.beginConnection()\n"
if method.count(initial_task_guard) != 1:
    raise SystemExit("official connection task entry drifted")
method = method.replace(
    initial_task_guard,
    '''            guard let self,
                  self.secureLinkViewGeneration == viewGeneration,
                  self.phase == .authenticating else { return }
            do {
                let token = try await self.sessionLedger.beginConnection()
                guard self.secureLinkViewGeneration == viewGeneration,
                      self.phase == .authenticating else {
                    do {
                        try await self.sessionLedger.markInternalLifecycleFailure(for: token)
                    } catch {
                        self.phase = .failed
                        self.message = "Secure Link exited while session generation started, and that generation could not be retired. Relaunch Capture before another attempt."
                        self.log("view_exit_generation_retirement_failed", [
                            "generation": String(token.diagnosticGeneration),
                            "error": error.localizedDescription
                        ])
                    }
                    await self.refreshLedgerSnapshot()
                    return
                }
''',
    1,
)

pre_connect_anchor = '''                await self.refreshLedgerSnapshot()
                self.log("official_connect_requested", [
'''
if method.count(pre_connect_anchor) != 1:
    raise SystemExit("pre-connect ledger anchor drifted")
method = method.replace(
    pre_connect_anchor,
    '''                await self.refreshLedgerSnapshot()
                guard self.secureLinkViewGeneration == viewGeneration,
                      self.phase == .authenticating else {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Secure Link exited before the official Tuya connection request. Relaunch Capture and restart from OFF1.",
                        kind: "view_exit_before_official_connect"
                    )
                    return
                }
                self.log("official_connect_requested", [
''',
    1,
)
source = source[:method_start] + method + source[method_end:]

watchdog_start = source.index("    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {")
watchdog_end = source.index("\n    private func recordObservedTransportLoss", watchdog_start)
watchdog = source[watchdog_start:watchdog_end]
entry_anchor = '''    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
'''
if watchdog.count(entry_anchor) != 1:
    raise SystemExit("watchdog entry drifted")
watchdog = watchdog.replace(
    entry_anchor,
    '''    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {
        watchdog?.cancel()
        let viewGeneration = secureLinkViewGeneration
        watchdog = Task { @MainActor [weak self] in
''',
    1,
)
loop_guard = '''                guard let self,
                      self.currentConnectionToken == token,
                      self.secureSessionEstablished,
                      let driver = self.driver else { return }
'''
if watchdog.count(loop_guard) != 1:
    raise SystemExit("watchdog loop guard drifted")
watchdog = watchdog.replace(
    loop_guard,
    '''                guard let self,
                      self.secureLinkViewGeneration == viewGeneration,
                      self.currentConnectionToken == token,
                      self.secureSessionEstablished,
                      let driver = self.driver else { return }
''',
    1,
)
post_seal_anchor = '''                        try await sessionLedger.sealAcceptedObservation(for: token)
                        guard self.buildIdentity.isAuthoritativeFieldBuild,
'''
if watchdog.count(post_seal_anchor) != 1:
    raise SystemExit("post-seal authority anchor drifted")
watchdog = watchdog.replace(
    post_seal_anchor,
    '''                        try await sessionLedger.sealAcceptedObservation(for: token)
                        guard self.secureLinkViewGeneration == viewGeneration,
                              self.phase == .observing else {
                            self.currentConnectionToken = nil
                            self.localBLESettlementToken = nil
                            self.sdkLocalBLEOnline = false
                            self.driver = nil
                            self.phase = .failed
                            self.message = "Secure Link left the screen while canonical acceptance was sealing. The package seal is diagnostic only; restart from OFF1."
                            self.log("view_exit_during_acceptance_seal", [
                                "generation": String(token.diagnosticGeneration)
                            ])
                            await self.refreshLedgerSnapshot()
                            return
                        }
                        guard self.buildIdentity.isAuthoritativeFieldBuild,
''',
    1,
)
source = source[:watchdog_start] + watchdog + source[watchdog_end:]

# Fail construction if the intended safety properties are not mechanically present.
cleanup_start = source.index("    func abandonCorrelationForViewExit() {")
cleanup_end = source.index("\n\n    var privateConfig: Bool", cleanup_start)
cleanup = source[cleanup_start:cleanup_end]
begin_start = source.index("    private func beginOfficialConnection(candidate: Candidate) {")
begin_end = source.index("\n    private func authenticated(token:", begin_start)
begin = source[begin_start:begin_end]
watchdog_start = source.index("    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {")
watchdog_end = source.index("\n    private func recordObservedTransportLoss", watchdog_start)
watchdog = source[watchdog_start:watchdog_end]

assert cleanup.index("secureLinkViewGeneration = UUID()") < cleanup.index("guard processCorrelationLease")
for needle in ("watchdog?.cancel()", "phase = .failed", "invalidateInternalLifecycle"):
    assert needle in cleanup
for needle in (
    "let viewGeneration = secureLinkViewGeneration",
    "self.secureLinkViewGeneration == viewGeneration",
    "newDriver.connect(",
    "view_exit_before_official_connect",
):
    assert needle in begin
assert begin.rindex("self.secureLinkViewGeneration == viewGeneration") < begin.index("newDriver.connect(")
for needle in (
    "let viewGeneration = secureLinkViewGeneration",
    "self.secureLinkViewGeneration == viewGeneration",
    "view_exit_during_acceptance_seal",
):
    assert needle in watchdog
for forbidden in ("disconnectBLE", "publishDps", "queryDps", "writeValue"):
    assert forbidden not in cleanup

app.write_text(source, encoding="utf-8")

test = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSecureLinkOffscreenAuthoritySourceTests.swift")
if test.exists():
    raise SystemExit("off-screen authority regression already exists")
test.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Secure Link off-screen authority source contract")
struct TuyaSecureLinkOffscreenAuthoritySourceTests {
    @Test("view exit synchronously revokes pending official-session UI authority")
    func viewExitRevokesOfficialSessionAuthority() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let cleanup = String(try section(
            in: source,
            from: "func abandonCorrelationForViewExit()",
            to: "var privateConfig: Bool"
        ))

        let generation = try #require(cleanup.range(of: "secureLinkViewGeneration = UUID()"))
        let packageGuard = try #require(cleanup.range(of: "guard processCorrelationLease"))
        #expect(generation.lowerBound < packageGuard.lowerBound)
        #expect(cleanup.contains("phase == .authenticating || phase == .observing"))
        #expect(cleanup.contains("watchdog?.cancel()"))
        #expect(cleanup.contains("phase = .failed"))
        #expect(cleanup.contains("invalidateInternalLifecycle"))
        #expect(!cleanup.contains("disconnectBLE"))
        #expect(!cleanup.contains("publishDps"))
        #expect(!cleanup.contains("queryDps"))
        #expect(!cleanup.contains("writeValue"))
    }

    @Test("an admitted official connection task rechecks the view generation before transport start")
    func queuedOfficialConnectionCannotStartAfterExit() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let begin = String(try section(
            in: source,
            from: "private func beginOfficialConnection(candidate: Candidate)",
            to: "private func authenticated(token:"
        ))

        #expect(begin.contains("let viewGeneration = secureLinkViewGeneration"))
        #expect(begin.contains("self.secureLinkViewGeneration == viewGeneration"))
        let lastFence = try #require(begin.ranges(of: "self.secureLinkViewGeneration == viewGeneration").last)
        let connect = try #require(begin.range(of: "newDriver.connect("))
        #expect(lastFence.lowerBound < connect.lowerBound)
        #expect(begin.contains("view_exit_before_official_connect"))
    }

    @Test("watchdog cannot promote or publish acceptance after Secure Link leaves the screen")
    func offscreenWatchdogCannotSealAcceptedProductEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = String(try section(
            in: source,
            from: "private func startWatchdog(token: TuyaReadOnlyConnectionToken)",
            to: "private func recordObservedTransportLoss"
        ))

        #expect(watchdog.contains("let viewGeneration = secureLinkViewGeneration"))
        #expect(watchdog.contains("self.secureLinkViewGeneration == viewGeneration"))
        let packageSeal = try #require(watchdog.range(of: "sealAcceptedObservation(for: token)"))
        let postSealFence = try #require(watchdog.range(of: "view_exit_during_acceptance_seal", range: packageSeal.upperBound..<watchdog.endIndex))
        let acceptedExport = try #require(watchdog.range(of: "self.sealedAcceptedExport = self.makeExport", range: postSealFence.upperBound..<watchdog.endIndex))
        #expect(packageSeal.lowerBound < postSealFence.lowerBound)
        #expect(postSealFence.lowerBound < acceptedExport.lowerBound)
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}

private extension String {
    func ranges(of needle: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var cursor = startIndex
        while cursor < endIndex,
              let range = range(of: needle, range: cursor..<endIndex) {
            result.append(range)
            cursor = range.upperBound
        }
        return result
    }
}
''', encoding="utf-8")
