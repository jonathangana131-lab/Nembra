import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothCaptureStrictJSONTests {
    @Test
    func externalBuildRecordRejectsExactDuplicateTopLevelField() {
        let data = Data(#"{"schemaVersion":3,"schemaVersion":3}"#.utf8)

        #expect(throws: PassiveBluetoothCaptureExternalBuildRecordError.duplicateField("schemaVersion")) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(data)
        }
    }

    @Test
    func externalBuildRecordRejectsEscapedEquivalentDuplicateField() {
        let data = Data(#"{"schemaVersion":3,"\u0073chemaVersion":3}"#.utf8)

        #expect(throws: PassiveBluetoothCaptureExternalBuildRecordError.duplicateField("schemaVersion")) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(data)
        }
    }

    @Test
    func strictValidatorRejectsNestedDuplicateKeys() {
        let data = Data(#"{"outer":{"value":1,"value":2}}"#.utf8)

        #expect(throws: PassiveBluetoothCaptureStrictJSONError.duplicateObjectKey("value")) {
            try PassiveBluetoothCaptureStrictJSON.validateNoDuplicateObjectKeys(data)
        }
    }

    @Test
    func strictValidatorPreservesOrdinaryWhitespaceOrderingAndDistinctKeys() throws {
        let data = Data(
            """
            {
              "z": [1, {"nested": true}],
              "a": "value",
              "schemaVersion": 3
            }
            """.utf8
        )

        try PassiveBluetoothCaptureStrictJSON.validateNoDuplicateObjectKeys(data)
    }

    @Test
    func malformedJSONFailsBeforeAnyDeclarationCanBeMinted() {
        let data = Data(#"{"schemaVersion":3,"broken":}"#.utf8)

        #expect(throws: PassiveBluetoothCaptureStrictJSONError.malformedJSON) {
            try PassiveBluetoothCaptureStrictJSON.validateNoDuplicateObjectKeys(data)
        }
    }
}
