import Foundation

/// Exact-byte JSON safeguards shared by Capture's external authority formats.
///
/// Foundation's keyed JSON APIs collapse duplicate object members. Authority-bearing callers must
/// reject repeated semantic keys before decoding so trust never depends on parser precedence.
enum PassiveBluetoothStrictJSON {
    static func duplicateTopLevelObjectKey(in data: Data) -> String? {
        duplicateObjectKey(in: data, scope: .topLevelOnly)
    }

    /// Returns the first repeated semantic key found in any JSON object, including nested objects.
    ///
    /// Closed-world formats with structured nested authority should use this in addition to their
    /// explicit top-level check so `JSONSerialization` never gets to collapse a nested duplicate
    /// before shape validation sees the exact bytes.
    static func duplicateObjectKeyAtAnyDepth(in data: Data) -> String? {
        duplicateObjectKey(in: data, scope: .allObjects)
    }

    private enum DuplicateScope {
        case topLevelOnly
        case allObjects
    }

    private static func duplicateObjectKey(
        in data: Data,
        scope: DuplicateScope
    ) -> String? {
        let bytes = Array(data)
        var seenKeysByObject = [Set<String>()]
        seenKeysByObject.removeAll(keepingCapacity: true)
        var index = 0

        while index < bytes.count {
            switch bytes[index] {
            case 0x7B: // {
                seenKeysByObject.append([])
            case 0x7D: // }
                if !seenKeysByObject.isEmpty {
                    seenKeysByObject.removeLast()
                }
            case 0x22: // "
                let stringStart = index
                index += 1
                var isEscaped = false

                while index < bytes.count {
                    let byte = bytes[index]
                    if isEscaped {
                        isEscaped = false
                    } else if byte == 0x5C { // \\
                        isEscaped = true
                    } else if byte == 0x22 {
                        break
                    }
                    index += 1
                }

                guard index < bytes.count else { return nil }
                let stringEnd = index

                if !seenKeysByObject.isEmpty {
                    var lookahead = index + 1
                    while lookahead < bytes.count, isJSONWhitespace(bytes[lookahead]) {
                        lookahead += 1
                    }
                    if lookahead < bytes.count, bytes[lookahead] == 0x3A { // :
                        let shouldInspect = scope == .allObjects || seenKeysByObject.count == 1
                        if shouldInspect {
                            let encodedKey = Data(bytes[stringStart...stringEnd])
                            if let key = try? JSONDecoder().decode(String.self, from: encodedKey),
                               !seenKeysByObject[seenKeysByObject.count - 1].insert(key).inserted {
                                return key
                            }
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
