from pathlib import Path


def once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


workflow_path = Path(".github/workflows/capture-field-build-provenance.yml")
workflow = workflow_path.read_text()
workflow = once(
    workflow,
    "  pull_request:\n    paths:\n",
    "  pull_request:\n    paths:\n      - \"Packages/NembraBluetoothCapture/**\"\n      - NembraApp/Features/Research/TuyaAccountBridge.swift\n",
    "provenance trigger",
)
workflow_path.write_text(workflow)

bridge_path = Path("NembraApp/Features/Research/TuyaAccountBridge.swift")
bridge = bridge_path.read_text()
bridge = once(
    bridge,
    "/// and read-only Device Sharing endpoints to collect the device's cloud metadata, current status,\n/// specifications, and local DP strategy before the next Bluetooth experiment.\n",
    "/// and read-only Device Sharing endpoints to collect the device's cloud metadata, current status,\n/// and specifications before the next Bluetooth experiment.\n",
    "bridge documentation",
)
bridge = once(
    bridge,
    "    @Published private(set) var selectedDeviceStatus: [String: Any]?\n    @Published private(set) var selectedDeviceSpecifications: [String: Any]?\n    @Published private(set) var selectedDeviceLocalStrategy: [String: Any]?\n",
    "    @Published private(set) var selectedDeviceStatus: [String: Any]?\n    @Published private(set) var selectedDeviceStatusResponse: Any?\n    @Published private(set) var selectedDeviceSpecifications: [String: Any]?\n",
    "status properties",
)
bridge = once(
    bridge,
    "        selectedDeviceStatus = nil\n        selectedDeviceSpecifications = nil\n        selectedDeviceLocalStrategy = nil\n",
    "        selectedDeviceStatus = nil\n        selectedDeviceStatusResponse = nil\n        selectedDeviceSpecifications = nil\n",
    "selected device reset",
)
bridge = once(
    bridge,
    "            \"status\": Self.redactSecrets(selectedDeviceStatus ?? [:]),\n            \"specifications\": Self.redactSecrets(selectedDeviceSpecifications ?? [:]),\n            \"localStrategy\": Self.redactSecrets(selectedDeviceLocalStrategy ?? [:]),\n",
    "            \"status\": Self.redactSecrets(selectedDeviceStatus ?? [:]),\n            \"specifications\": Self.redactSecrets(selectedDeviceSpecifications ?? [:]),\n",
    "metadata export fields",
)
bridge = once(
    bridge,
    "        if let selectedDeviceMetadata {\n            envelope[\"deviceDetailRedacted\"] = Self.redactSecrets(selectedDeviceMetadata)\n        }\n",
    "        if let selectedDeviceMetadata {\n            envelope[\"deviceDetailRedacted\"] = Self.redactSecrets(selectedDeviceMetadata)\n        }\n        if let selectedDeviceStatusResponse {\n            envelope[\"statusResponse\"] = Self.redactSecrets(selectedDeviceStatusResponse)\n        }\n",
    "status response export",
)
old_load = '''        async let detailResponse = signedGET(path: "/v1.0/m/life/ha/devices/detail", params: ["devIds": device.id])
        async let specResponse = signedGET(path: "/v1.1/m/life/\(device.id)/specifications")
        async let strategyResponse = signedGET(path: "/v1.0/m/life/devices/\(device.id)/status")

        let (detail, specs, strategy) = try await (detailResponse, specResponse, strategyResponse)
        guard !Task.isCancelled,
              generation == operationGeneration,
              selectedDeviceID == device.id else { return }
        let detailArray = detail["result"] as? [[String: Any]] ?? []
        let rawDetail = detailArray.first ?? [:]
        selectedDeviceMetadata = Self.redactAccountUID(
            Self.redactSecrets(rawDetail),
            accountUID: accountUID
        ) as? [String: Any] ?? [:]
        selectedDeviceSpecifications = Self.redactAccountUID(
            Self.redactSecrets(specs["result"] as? [String: Any] ?? [:]),
            accountUID: accountUID
        ) as? [String: Any] ?? [:]
        selectedDeviceLocalStrategy = Self.redactAccountUID(
            Self.redactSecrets(strategy["result"] as? [String: Any] ?? [:]),
            accountUID: accountUID
        ) as? [String: Any] ?? [:]

        var statusMap: [String: Any] = [:]
        if let statuses = rawDetail["status"] as? [[String: Any]] {
            for status in statuses {
                if let code = Self.string(status["code"]), let value = status["value"] {
                    statusMap[code] = value
                }
            }
        }
'''
new_load = '''        async let detailResponse = signedGET(path: "/v1.0/m/life/ha/devices/detail", params: ["devIds": device.id])
        async let specResponse = signedGET(path: "/v1.1/m/life/\(device.id)/specifications")
        async let statusResponse = signedGET(path: "/v1.0/m/life/devices/\(device.id)/status")

        let (detail, specs, status) = try await (detailResponse, specResponse, statusResponse)
        guard !Task.isCancelled,
              generation == operationGeneration,
              selectedDeviceID == device.id else { return }
        let detailArray = detail["result"] as? [[String: Any]] ?? []
        let rawDetail = detailArray.first ?? [:]
        let rawStatusResult: Any = status["result"] ?? NSNull()
        selectedDeviceMetadata = Self.redactAccountUID(
            Self.redactSecrets(rawDetail),
            accountUID: accountUID
        ) as? [String: Any] ?? [:]
        selectedDeviceSpecifications = Self.redactAccountUID(
            Self.redactSecrets(specs["result"] as? [String: Any] ?? [:]),
            accountUID: accountUID
        ) as? [String: Any] ?? [:]
        selectedDeviceStatusResponse = Self.redactAccountUID(
            Self.redactSecrets(rawStatusResult),
            accountUID: accountUID
        )

        var statusMap: [String: Any] = [:]
        if let statusDictionary = rawStatusResult as? [String: Any] {
            statusMap = statusDictionary
        } else if let statuses = rawStatusResult as? [[String: Any]] {
            for status in statuses {
                if let code = Self.string(status["code"]), let value = status["value"] {
                    statusMap[code] = value
                }
            }
        } else if let statuses = rawDetail["status"] as? [[String: Any]] {
            for status in statuses {
                if let code = Self.string(status["code"]), let value = status["value"] {
                    statusMap[code] = value
                }
            }
        }
'''
bridge = once(bridge, old_load, new_load, "status endpoint semantics")
if "selectedDeviceLocalStrategy" in bridge or '"localStrategy"' in bridge:
    raise SystemExit("fabricated localStrategy semantics remain")
bridge_path.write_text(bridge)

test_path = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureRootProductSurfaceSourceTests.swift")
test = test_path.read_text()
marker = '    @Test("legacy card-based Capture root is retired from the metadata bridge")\n'
addition = '''    @Test("Tuya status evidence is preserved as status and never relabeled local strategy")
    func metadataStatusKeepsItsRealProvenance() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")

        #expect(bridge.contains("async let statusResponse = signedGET(path: \\"/v1.0/m/life/devices/\\(device.id)/status\\")"))
        #expect(bridge.contains("let rawStatusResult: Any = status[\\"result\\"] ?? NSNull()"))
        #expect(bridge.contains("selectedDeviceStatusResponse"))
        #expect(bridge.contains("envelope[\\"statusResponse\\"]"))
        #expect(!bridge.contains("selectedDeviceLocalStrategy"))
        #expect(!bridge.contains("\\"localStrategy\\""))
    }

    @Test("field provenance reruns for every Capture package input and the metadata bridge")
    func fieldProvenanceTriggerCoversTrustedCaptureInputs() throws {
        let workflow = try readRepositoryFile(".github/workflows/capture-field-build-provenance.yml")

        #expect(workflow.contains("- \\"Packages/NembraBluetoothCapture/**\\""))
        #expect(workflow.contains("- NembraApp/Features/Research/TuyaAccountBridge.swift"))
    }

'''
test = once(test, marker, addition + marker, "review blocker regression tests")
test_path.write_text(test)
