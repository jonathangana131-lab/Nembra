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

        let freezeBoundary: String.Index
        if let inlineFreeze = watchdog.range(of: "ExactByteArtifactSeal(sealing:") {
            freezeBoundary = inlineFreeze.lowerBound
            let betweenFreezeAndCapability = watchdog[
                inlineFreeze.lowerBound..<capabilitySeal.lowerBound
            ]
            #expect(betweenFreezeAndCapability.contains(".verifies("))
        } else {
            let freezeCall = try #require(
                watchdog.range(of: "freezeAcceptedArtifactForAuthorizationSeal(")
            )
            freezeBoundary = freezeCall.lowerBound

            let helper = try section(
                in: app,
                from: "private func freezeAcceptedArtifactForAuthorizationSeal(",
                throughAnyOf: [
                    "private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken)",
                    "private func invalidateSourceAuthority("
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
