import Foundation
import Testing

@Suite("Capture field-capability accepted-artifact freeze ordering")
struct TuyaAuthenticatedFieldCapabilityArtifactFreezeSourceTests {
    @Test("opaque capability seals only after immutable accepted bytes are frozen and verified")
    func capabilitySealFollowsExactByteArtifactFreeze() throws {
        let app = try appSource()
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog(token: TuyaReadOnlyConnectionToken)",
            through: "private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken)"
        )

        let packageSeal = try #require(
            watchdog.range(of: "sealAcceptedObservation(for: token)")
        )
        let capabilitySeal = try #require(
            watchdog.range(of: "sealAfterAcceptedArtifactFreeze()")
        )
        let acceptedPromotion = try #require(
            watchdog.range(of: "self.phase = .accepted")
        )

        // Only an artifact-freeze boundary that occurs before the authorization seal
        // can satisfy this ordering contract. A later helper implementation detail must
        // never be used to construct a reversed String range (or masquerade as the
        // operational freeze that authorizes acceptance).
        let preCapabilitySeal = watchdog.startIndex..<capabilitySeal.lowerBound
        let freezeBoundary: String.Index
        if let inlineFreeze = watchdog.range(
            of: "ExactByteArtifactSeal(sealing:",
            range: preCapabilitySeal
        ) {
            freezeBoundary = inlineFreeze.lowerBound
            let betweenFreezeAndCapability = watchdog[
                inlineFreeze.lowerBound..<capabilitySeal.lowerBound
            ]
            #expect(betweenFreezeAndCapability.contains(".verifies("))
        } else {
            let freezeCall = try #require(
                watchdog.range(
                    of: "freezeAcceptedArtifactForAuthorizationSeal(",
                    range: preCapabilitySeal
                )
            )
            freezeBoundary = freezeCall.lowerBound

            let helper = try section(
                in: app,
                from: "private func freezeAcceptedArtifactForAuthorizationSeal(",
                throughAnyOf: [
                    "private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken)",
                    "private func invalidateSourceAuthority(",
                    "func prepareExport()",
                ]
            )
            #expect(helper.contains("ExactByteArtifactSeal(sealing:"))
            #expect(helper.contains(".verifies("))
            #expect(helper.contains("verifiedBytes()") || helper.contains("verifiedCanonicalValue("))
        }

        #expect(packageSeal.lowerBound < freezeBoundary)
        #expect(freezeBoundary < capabilitySeal.lowerBound)
        #expect(capabilitySeal.lowerBound < acceptedPromotion.lowerBound)
    }

    @Test("failed authorization seal cannot leave accepted-looking artifact bytes published")
    func capabilitySealFailureClearsPrepublishedAcceptedArtifact() throws {
        let app = try appSource()
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog(token: TuyaReadOnlyConnectionToken)",
            through: "private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken)"
        )
        let capabilitySeal = try #require(
            watchdog.range(of: "sealAfterAcceptedArtifactFreeze()")
        )
        let acceptedPromotion = try #require(
            watchdog.range(of: "self.phase = .accepted", range: capabilitySeal.upperBound..<watchdog.endIndex)
        )

        let beforeCapabilitySeal = String(watchdog[..<capabilitySeal.lowerBound])
        var publishesAcceptedStateBeforeSeal = beforeCapabilitySeal.contains("self.sealedAcceptedExport =")
            || beforeCapabilitySeal.contains("self.sealedAcceptedArtifact =")
            || beforeCapabilitySeal.contains("self.exportData =")
            || beforeCapabilitySeal.contains("self.acceptedArtifactSHA256 =")
            || beforeCapabilitySeal.contains("self.acceptedArtifactByteCount =")

        if let helperStart = app.range(of: "private func freezeAcceptedArtifactForAuthorizationSeal(") {
            let helperCandidates = [
                "private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken)",
                "private func invalidateSourceAuthority(",
                "func prepareExport()",
            ].compactMap { app.range(of: $0, range: helperStart.upperBound..<app.endIndex) }
            if let helperEnd = helperCandidates.min(by: { $0.lowerBound < $1.lowerBound }) {
                let helper = String(app[helperStart.lowerBound..<helperEnd.lowerBound])
                publishesAcceptedStateBeforeSeal = publishesAcceptedStateBeforeSeal
                    || helper.contains("sealedAcceptedArtifact =")
                    || helper.contains("exportData =")
                    || helper.contains("acceptedArtifactSHA256 =")
                    || helper.contains("acceptedArtifactByteCount =")
            }
        }

        guard publishesAcceptedStateBeforeSeal else { return }

        let afterSealBeforePromotion = watchdog[
            capabilitySeal.upperBound..<acceptedPromotion.lowerBound
        ]
        let catchRange = try #require(afterSealBeforePromotion.range(of: "catch {"))
        let returnRange = try #require(
            afterSealBeforePromotion.range(
                of: "return",
                range: catchRange.upperBound..<afterSealBeforePromotion.endIndex
            )
        )
        let failedSeal = String(afterSealBeforePromotion[catchRange.lowerBound..<returnRange.upperBound])

        #expect(failedSeal.contains("fieldAuthorization.revoke()"))
        #expect(failedSeal.contains("sealedAcceptedExport = nil"))
        #expect(failedSeal.contains("sealedAcceptedArtifact = nil"))
        #expect(failedSeal.contains("exportData = nil"))
        #expect(failedSeal.contains("acceptedArtifactSHA256 = nil"))
        #expect(failedSeal.contains("acceptedArtifactByteCount = nil"))
        #expect(failedSeal.contains("phase = .failed"))
    }

    @Test("a consumed one-OFF1 authorization cannot silently power an in-process retry")
    func failedRetryRequiresFreshArmedAuthorization() throws {
        let app = try appSource()
        let retryReadiness = try section(
            in: app,
            from: "var failedAttemptCanRestartFromOFF1: Bool",
            through: "var canRestartFromFreshOFF1: Bool"
        )

        #expect(retryReadiness.contains("fieldAuthorization.stage == .armed"))
    }

    private func section(
        in source: String,
        from startMarker: String,
        through endMarker: String
    ) throws -> String {
        let start = try #require(source.range(of: startMarker))
        let end = try #require(
            source.range(of: endMarker, range: start.upperBound..<source.endIndex)
        )
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func section(
        in source: String,
        from startMarker: String,
        throughAnyOf endMarkers: [String]
    ) throws -> String {
        let start = try #require(source.range(of: startMarker))
        let candidates = endMarkers.compactMap {
            source.range(of: $0, range: start.upperBound..<source.endIndex)
        }
        let end = try #require(candidates.min(by: { $0.lowerBound < $1.lowerBound }))
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func appSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
    }
}
