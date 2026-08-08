import Foundation

/// Raw-byte duplicate-key custody for the stationary capture manifest.
///
/// Foundation keyed JSON APIs collapse repeated object members. The stationary manifest is an
/// exact evidence sidecar, so every object in the retained bytes must have one unambiguous semantic
/// key set before `JSONSerialization` or `JSONDecoder` is allowed to interpret it.
enum PassiveBluetoothStationaryCaptureManifestStrictJSON {
    static func duplicateObjectKeyPath(in data: Data) -> String? {
        var parser = Parser(bytes: Array(data))
        return parser.firstDuplicateObjectKeyPath()
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        mutating func firstDuplicateObjectKeyPath() -> String? {
            var duplicatePath: String?
            skipWhitespace()
            guard parseValue(path: "", duplicatePath: &duplicatePath) else {
                return nil
            }
            return duplicatePath
        }

        private mutating func parseValue(
            path: String,
            duplicatePath: inout String?
        ) -> Bool {
            skipWhitespace()
            guard index < bytes.count else { return false }

            switch bytes[index] {
            case 0x7B:
                return parseObject(path: path, duplicatePath: &duplicatePath)
            case 0x5B:
                return parseArray(path: path, duplicatePath: &duplicatePath)
            case 0x22:
                return parseString() != nil
            default:
                return parseScalar()
            }
        }

        private mutating func parseObject(
            path: String,
            duplicatePath: inout String?
        ) -> Bool {
            guard consume(0x7B) else { return false }
            skipWhitespace()
            if consume(0x7D) { return true }

            var seenKeys = Set<String>()
            while index < bytes.count {
                skipWhitespace()
                guard let key = parseString() else { return false }
                skipWhitespace()
                guard consume(0x3A) else { return false }

                let qualifiedPath = path.isEmpty ? key : "\(path).\(key)"
                guard seenKeys.insert(key).inserted else {
                    duplicatePath = qualifiedPath
                    return true
                }

                guard parseValue(path: qualifiedPath, duplicatePath: &duplicatePath) else {
                    return false
                }
                if duplicatePath != nil { return true }

                skipWhitespace()
                if consume(0x7D) { return true }
                guard consume(0x2C) else { return false }
            }
            return false
        }

        private mutating func parseArray(
            path: String,
            duplicatePath: inout String?
        ) -> Bool {
            guard consume(0x5B) else { return false }
            skipWhitespace()
            if consume(0x5D) { return true }

            var elementIndex = 0
            while index < bytes.count {
                let elementPath = path.isEmpty ? "[\(elementIndex)]" : "\(path)[\(elementIndex)]"
                guard parseValue(path: elementPath, duplicatePath: &duplicatePath) else {
                    return false
                }
                if duplicatePath != nil { return true }

                elementIndex += 1
                skipWhitespace()
                if consume(0x5D) { return true }
                guard consume(0x2C) else { return false }
            }
            return false
        }

        private mutating func parseString() -> String? {
            guard index < bytes.count, bytes[index] == 0x22 else { return nil }
            let start = index
            index += 1
            var isEscaped = false

            while index < bytes.count {
                let byte = bytes[index]
                if isEscaped {
                    isEscaped = false
                } else if byte == 0x5C {
                    isEscaped = true
                } else if byte == 0x22 {
                    index += 1
                    let encoded = Data(bytes[start..<index])
                    return try? JSONDecoder().decode(String.self, from: encoded)
                }
                index += 1
            }
            return nil
        }

        private mutating func parseScalar() -> Bool {
            let start = index
            while index < bytes.count {
                let byte = bytes[index]
                if isJSONWhitespace(byte) || byte == 0x2C || byte == 0x5D || byte == 0x7D {
                    break
                }
                index += 1
            }
            return index > start
        }

        private mutating func skipWhitespace() {
            while index < bytes.count, isJSONWhitespace(bytes[index]) {
                index += 1
            }
        }

        private mutating func consume(_ byte: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }

        private func isJSONWhitespace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        }
    }
}
