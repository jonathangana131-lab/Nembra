import Foundation

/// Exact-byte JSON safeguards shared by Capture's externally accepted authority/evidence formats.
///
/// Foundation keyed JSON APIs collapse duplicate object members and can disagree about which value
/// wins. Reject repeated semantic keys before typed decode so authority never depends on parser
/// precedence. JSON escapes are decoded before comparison, making `decision` and `decisio\u006e`
/// the same key.
package enum PassiveBluetoothStrictJSON {
    package static func duplicateTopLevelObjectKey(in data: Data) -> String? {
        let bytes = Array(data)
        var objectDepth = 0
        var seenKeys = Set<String>()
        var index = 0

        while index < bytes.count {
            switch bytes[index] {
            case 0x7B: // {
                objectDepth += 1
            case 0x7D: // }
                objectDepth -= 1
            case 0x22: // "
                let stringStart = index
                index += 1
                var isEscaped = false

                while index < bytes.count {
                    let byte = bytes[index]
                    if isEscaped {
                        isEscaped = false
                    } else if byte == 0x5C { // \
                        isEscaped = true
                    } else if byte == 0x22 {
                        break
                    }
                    index += 1
                }

                guard index < bytes.count else { return nil }
                let stringEnd = index

                if objectDepth == 1 {
                    var lookahead = index + 1
                    while lookahead < bytes.count, isJSONWhitespace(bytes[lookahead]) {
                        lookahead += 1
                    }
                    if lookahead < bytes.count, bytes[lookahead] == 0x3A { // :
                        let encodedKey = Data(bytes[stringStart...stringEnd])
                        if let key = try? JSONDecoder().decode(String.self, from: encodedKey),
                           !seenKeys.insert(key).inserted {
                            return key
                        }
                    }
                }
            default:
                break
            }
            index += 1
        }

        return nil
    }

    private static func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }
}
