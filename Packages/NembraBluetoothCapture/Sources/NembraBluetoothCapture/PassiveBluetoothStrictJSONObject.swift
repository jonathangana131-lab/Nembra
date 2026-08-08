import Foundation

/// Byte-preserving duplicate-key guard for small authority-bearing JSON objects.
///
/// Foundation's `JSONSerialization` and `JSONDecoder` can collapse duplicate object members with
/// different precedence. Signed or externally accepted bytes must therefore reject duplicate
/// semantic keys before either keyed parser is allowed to interpret authority.
///
/// Callers still own full JSON/schema validation. This scanner only detects repeated keys at the
/// top level of the root object. JSON string escapes are decoded before comparison, so alternate
/// spellings such as `decision` and `decisio\u006e` are the same semantic key.
package enum PassiveBluetoothStrictJSONObject {
    package static func duplicateTopLevelKey(in data: Data) -> String? {
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
