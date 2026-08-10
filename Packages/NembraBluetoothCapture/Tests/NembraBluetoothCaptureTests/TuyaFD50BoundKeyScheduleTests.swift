import Foundation
import Testing
@testable import NembraBluetoothCapture

struct TuyaFD50BoundKeyScheduleTests {
    @Test
    func deviceInfoKeyMatchesPinnedVector() throws {
        let key = try TuyaFD50BoundKeySchedule.deviceInfoKey(
            localKey: Data("0123456789ABCDEF".utf8),
            secretKey: Data("FEDCBA9876543210".utf8)
        )

        #expect(key.hexString == "d386590c8c11c892e40b711d476d5676")
    }

    @Test
    func sessionKeyMatchesPinnedVector() throws {
        let key = try TuyaFD50BoundKeySchedule.sessionKey(
            localKey: Data("0123456789ABCDEF".utf8),
            secretKey: Data("FEDCBA9876543210".utf8),
            pairRandom: Data([1, 2, 3, 4, 5, 6])
        )

        #expect(key.hexString == "e2e42abec6975b2230ece8f821d3974e")
    }

    @Test
    func rejectsWrongCredentialLengths() {
        #expect(throws: TuyaFD50BoundKeyScheduleError.invalidLength(
            field: "localKey",
            expected: 16,
            actual: 15
        )) {
            try TuyaFD50BoundKeySchedule.deviceInfoKey(
                localKey: Data(repeating: 0, count: 15),
                secretKey: Data(repeating: 0, count: 16)
            )
        }

        #expect(throws: TuyaFD50BoundKeyScheduleError.invalidLength(
            field: "pairRandom",
            expected: 6,
            actual: 5
        )) {
            try TuyaFD50BoundKeySchedule.sessionKey(
                localKey: Data(repeating: 0, count: 16),
                secretKey: Data(repeating: 0, count: 16),
                pairRandom: Data(repeating: 0, count: 5)
            )
        }
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
