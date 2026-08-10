import CryptoKit
import Foundation

/// Candidate bound-session key schedule reproduced from TuyaOpen's current FD50 BLE source.
///
/// This deliberately performs no Bluetooth I/O and makes no claim that a particular scooter
/// uses this protocol generation. A physical/advertisement compatibility gate must establish
/// that before any caller is allowed to build or transmit an authentication frame.
public enum TuyaFD50BoundKeySchedule {
    public static let loginKeyLength = 16
    public static let secretKeyLength = 16
    public static let pairRandomLength = 6

    /// TuyaOpen encryption mode 14: MD5(login/local key + activation secret key).
    public static func deviceInfoKey(localKey: Data, secretKey: Data) throws -> Data {
        try requireLength(localKey, loginKeyLength, field: "localKey")
        try requireLength(secretKey, secretKeyLength, field: "secretKey")
        return md5(localKey + secretKey)
    }

    /// TuyaOpen encryption mode 15: MD5(login/local key + activation secret key + pair random).
    public static func sessionKey(
        localKey: Data,
        secretKey: Data,
        pairRandom: Data
    ) throws -> Data {
        try requireLength(localKey, loginKeyLength, field: "localKey")
        try requireLength(secretKey, secretKeyLength, field: "secretKey")
        try requireLength(pairRandom, pairRandomLength, field: "pairRandom")
        return md5(localKey + secretKey + pairRandom)
    }

    private static func requireLength(_ value: Data, _ expected: Int, field: String) throws {
        guard value.count == expected else {
            throw TuyaFD50BoundKeyScheduleError.invalidLength(
                field: field,
                expected: expected,
                actual: value.count
            )
        }
    }

    private static func md5(_ data: Data) -> Data {
        Data(Insecure.MD5.hash(data: data))
    }
}

public enum TuyaFD50BoundKeyScheduleError: Error, Equatable, Sendable {
    case invalidLength(field: String, expected: Int, actual: Int)
}
