import Foundation
import Testing
@testable import NembraBluetoothCapture
@testable import NembraCaptureAppAuthorization

@Suite("Authenticated stationary signer rendezvous document")
struct AuthenticatedStationaryCaptureSignerRendezvousDocumentTests {
    @Test("canonical document exports only non-authorizing current-attempt facts")
    func canonicalNonAuthorizingDocument() throws {
        let start: Int64 = 2_000_000
        let rendezvous = AuthenticatedStationaryCaptureAppSession.SignerRendezvous(
            challengeSHA256: String(repeating: "a", count: 64),
            startedAtWallClockUnixMilliseconds: start,
            startedAtUptimeNanoseconds: 10_000_000_000,
            procedureID: AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID
        )

        let data = try AuthenticatedStationaryCaptureSignerRendezvousDocument.encode(rendezvous)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(
            object["schema"] as? String
                == AuthenticatedStationaryCaptureSignerRendezvousDocument.schema
        )
        #expect(
            object["version"] as? Int
                == AuthenticatedStationaryCaptureSignerRendezvousDocument.schemaVersion
        )
        #expect(object["procedureID"] as? String == rendezvous.procedureID)
        #expect(object["attemptChallengeSHA256"] as? String == rendezvous.challengeSHA256)
        #expect(object["attemptStartedAtUnixMilliseconds"] as? Int == start)
        #expect(
            object["authorizationMustExpireByUnixMilliseconds"] as? Int
                == start
                    + AuthenticatedStationaryCaptureFieldAuthorizationVerifier
                        .maximumAuthorizationLifetimeMilliseconds
        )
        #expect(data.count <= AuthenticatedStationaryCaptureSignerRendezvousDocument.maximumDocumentByteCount)
        #expect(!data.contains(0x0A))

        let text = try #require(String(data: data, encoding: .utf8))
        for forbidden in [
            "GO", "decision", "signature", "publicKey", "privateKey", "capability",
            "deviceID", "deviceIdentifier", "authorizationID", "startedAtUptimeNanoseconds",
        ] {
            #expect(!text.contains(forbidden), "Rendezvous leaked authority/irrelevant state: \(forbidden)")
        }
    }

    @Test("document deadline is anchored to app attempt start, not signer time")
    func deadlineUsesAttemptStart() throws {
        let start: Int64 = 1_800_000_000_000
        let rendezvous = AuthenticatedStationaryCaptureAppSession.SignerRendezvous(
            challengeSHA256: String(repeating: "b", count: 64),
            startedAtWallClockUnixMilliseconds: start,
            startedAtUptimeNanoseconds: 20_000_000_000,
            procedureID: AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID
        )
        let data = try AuthenticatedStationaryCaptureSignerRendezvousDocument.encode(rendezvous)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(
            object["authorizationMustExpireByUnixMilliseconds"] as? Int
                == start + 15 * 60 * 1_000
        )
    }

    @Test("malformed challenge, procedure, and impossible clocks fail before export")
    func invalidFactsFailClosed() {
        let validUptime: UInt64 = 10_000_000_000
        let procedure = AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID

        #expect(throws: AuthenticatedStationaryCaptureSignerRendezvousDocumentError.invalidChallenge) {
            _ = try AuthenticatedStationaryCaptureSignerRendezvousDocument.encode(
                .init(
                    challengeSHA256: String(repeating: "A", count: 64),
                    startedAtWallClockUnixMilliseconds: 1,
                    startedAtUptimeNanoseconds: validUptime,
                    procedureID: procedure
                )
            )
        }
        #expect(throws: AuthenticatedStationaryCaptureSignerRendezvousDocumentError.invalidAttemptClock) {
            _ = try AuthenticatedStationaryCaptureSignerRendezvousDocument.encode(
                .init(
                    challengeSHA256: String(repeating: "a", count: 64),
                    startedAtWallClockUnixMilliseconds: 0,
                    startedAtUptimeNanoseconds: validUptime,
                    procedureID: procedure
                )
            )
        }
        #expect(throws: AuthenticatedStationaryCaptureSignerRendezvousDocumentError.invalidProcedure) {
            _ = try AuthenticatedStationaryCaptureSignerRendezvousDocument.encode(
                .init(
                    challengeSHA256: String(repeating: "a", count: 64),
                    startedAtWallClockUnixMilliseconds: 1,
                    startedAtUptimeNanoseconds: validUptime,
                    procedureID: "wrong-procedure"
                )
            )
        }
        #expect(throws: AuthenticatedStationaryCaptureSignerRendezvousDocumentError.deadlineOverflow) {
            _ = try AuthenticatedStationaryCaptureSignerRendezvousDocument.encode(
                .init(
                    challengeSHA256: String(repeating: "a", count: 64),
                    startedAtWallClockUnixMilliseconds: Int64.max,
                    startedAtUptimeNanoseconds: validUptime,
                    procedureID: procedure
                )
            )
        }
    }

    @Test("document is deterministic compact sorted JSON")
    func deterministicCanonicalBytes() throws {
        let rendezvous = AuthenticatedStationaryCaptureAppSession.SignerRendezvous(
            challengeSHA256: String(repeating: "c", count: 64),
            startedAtWallClockUnixMilliseconds: 2_000_000,
            startedAtUptimeNanoseconds: 10_000_000_000,
            procedureID: AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID
        )
        let first = try AuthenticatedStationaryCaptureSignerRendezvousDocument.encode(rendezvous)
        let second = try AuthenticatedStationaryCaptureSignerRendezvousDocument.encode(rendezvous)
        #expect(first == second)

        let value = try JSONSerialization.jsonObject(with: first)
        let canonical = try JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        #expect(first == canonical)
    }
}
