import Foundation

enum PassiveBluetoothCaptureStrictJSONError: Error, Equatable, Sendable {
    case malformedJSON
    case duplicateObjectKey(String)
}

/// Exact-byte JSON safety used by externally attested Capture evidence.
///
/// Foundation's object model intentionally collapses duplicate JSON object members. That is unsafe
/// for evidence whose exact bytes are hashed/signed because two consumers could otherwise attach
/// different semantics to the same attested byte string. This validator preserves ordinary JSON
/// whitespace/order flexibility while rejecting duplicate object keys at every nesting level,
/// including escaped spellings such as `"schemaVersion"` and `"\u0073chemaVersion"`.
enum PassiveBluetoothCaptureStrictJSON {
    static func validateNoDuplicateObjectKeys(_ data: Data) throws {
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw PassiveBluetoothCaptureStrictJSONError.malformedJSON
        }

        var parser = Parser(bytes: Array(data))
        try parser.parseValue()
        parser.skipWhitespace()
        guard parser.isAtEnd else {
            throw PassiveBluetoothCaptureStrictJSONError.malformedJSON
        }
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        var isAtEnd: Bool { index == bytes.count }

        mutating func skipWhitespace() {
            while index < bytes.count, Self.isWhitespace(bytes[index]) {
                index += 1
            }
        }

        mutating func parseValue() throws {
            skipWhitespace()
            guard index < bytes.count else { throw PassiveBluetoothCaptureStrictJSONError.malformedJSON }
            switch bytes[index] {
            case 0x7B: // {
                try parseObject()
            case 0x5B: // [
                try parseArray()
            case 0x22: // "
                _ = try parseString()
            default:
                try parsePrimitive()
            }
        }

        mutating func parseObject() throws {
            guard consume(0x7B) else { throw PassiveBluetoothCaptureStrictJSONError.malformedJSON }
            skipWhitespace()
            if consume(0x7D) { return }

            var keys = Set<String>()
            while true {
                skipWhitespace()
                let key = try parseString()
                guard keys.insert(key).inserted else {
                    throw PassiveBluetoothCaptureStrictJSONError.duplicateObjectKey(key)
                }

                skipWhitespace()
                guard consume(0x3A) else { throw PassiveBluetoothCaptureStrictJSONError.malformedJSON }
                try parseValue()
                skipWhitespace()

                if consume(0x7D) { return }
                guard consume(0x2C) else { throw PassiveBluetoothCaptureStrictJSONError.malformedJSON }
            }
        }

        mutating func parseArray() throws {
            guard consume(0x5B) else { throw PassiveBluetoothCaptureStrictJSONError.malformedJSON }
            skipWhitespace()
            if consume(0x5D) { return }

            while true {
                try parseValue()
                skipWhitespace()
                if consume(0x5D) { return }
                guard consume(0x2C) else { throw PassiveBluetoothCaptureStrictJSONError.malformedJSON }
            }
        }

        mutating func parseString() throws -> String {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == 0x22 else {
                throw PassiveBluetoothCaptureStrictJSONError.malformedJSON
            }
            let start = index
            index += 1

            while index < bytes.count {
                let byte = bytes[index]
                if byte == 0x22 {
                    index += 1
                    let literal = Data(bytes[start..<index])
                    do {
                        return try JSONDecoder().decode(String.self, from: literal)
                    } catch {
                        throw PassiveBluetoothCaptureStrictJSONError.malformedJSON
                    }
                }
                if byte < 0x20 {
                    throw PassiveBluetoothCaptureStrictJSONError.malformedJSON
                }
                if byte == 0x5C { // backslash
                    index += 1
                    guard index < bytes.count else {
                        throw PassiveBluetoothCaptureStrictJSONError.malformedJSON
                    }
                }
                index += 1
            }
            throw PassiveBluetoothCaptureStrictJSONError.malformedJSON
        }

        mutating func parsePrimitive() throws {
            let start = index
            while index < bytes.count {
                let byte = bytes[index]
                if Self.isWhitespace(byte) || byte == 0x2C || byte == 0x5D || byte == 0x7D {
                    break
                }
                index += 1
            }
            guard index > start else { throw PassiveBluetoothCaptureStrictJSONError.malformedJSON }
        }

        mutating func consume(_ expected: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == expected else { return false }
            index += 1
            return true
        }

        static func isWhitespace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        }
    }
}
