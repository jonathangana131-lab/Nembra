import Foundation

/// Exact-byte JSON ambiguity guard used by authority-adjacent Capture evidence parsers.
///
/// Foundation's keyed JSON decoders collapse duplicate object members. Evidence records retain the
/// SHA-256 of their exact bytes, so accepting duplicate semantic keys would make the meaning of those
/// exact bytes depend on parser precedence. This scanner rejects repeated semantic top-level keys,
/// including escape-equivalent spellings, before keyed decoding occurs.
enum PassiveBluetoothStrictJSONObject {
    static func duplicateTopLevelObjectKey(in data: Data) -> String? {
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
