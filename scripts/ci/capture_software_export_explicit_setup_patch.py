from pathlib import Path

p = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneSoftwareExport.swift")
s = p.read_text()

def one(old, new, label):
    global s
    c = s.count(old)
    if c != 1:
        raise SystemExit(f"{label}: expected 1 anchor, found {c}")
    s = s.replace(old, new, 1)

one(
'''        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
''',
'''        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        setup: PassiveBluetoothStationaryCaptureSetup
''',
"public make signature"
)
one(
'''            powerCycleResult: finalizedArtifact.powerCycleResult,
            runtimeBuildIdentity: runtimeBuildIdentity
''',
'''            powerCycleResult: finalizedArtifact.powerCycleResult,
            runtimeBuildIdentity: runtimeBuildIdentity,
            setup: setup
''',
"public make forwarding"
)
one(
'''        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
''',
'''        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        setup: PassiveBluetoothStationaryCaptureSetup
''',
"package make signature"
)
one(
'''            selectedPeripheralIdentifier: selectedTarget.uuidString,
            setup: .init(
                chargerState: .disconnected,
                executionContext: .foregroundUnlockedScreenOn,
                stockAppReferenceSetup: .none
            )
''',
'''            selectedPeripheralIdentifier: selectedTarget.uuidString,
            setup: setup
''',
"manifest setup"
)
one(
'''    public static func makeForCurrentApplication(
        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact
    ) throws -> PassiveBluetoothExperimentOneSoftwareExport {
        try make(
            finalizedArtifact: finalizedArtifact,
            runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()
        )
    }
''',
'''    public static func makeForCurrentApplication(
        finalizedArtifact: PassiveBluetoothExperimentOneCoordinator.FinalizedArtifact,
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> PassiveBluetoothExperimentOneSoftwareExport {
        try make(
            finalizedArtifact: finalizedArtifact,
            runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication(),
            setup: setup
        )
    }
''',
"current app helper"
)
one(
'''    func finalizedSoftwareExportForCurrentApplication()
        throws -> PassiveBluetoothExperimentOneSoftwareExport {
        guard let finalizedArtifact else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.artifactNotFinalized
        }
        return try PassiveBluetoothExperimentOneSoftwareExportCodec.makeForCurrentApplication(
            finalizedArtifact: finalizedArtifact
        )
    }

    func encodedFinalizedSoftwareExportForCurrentApplication(prettyPrinted: Bool = true) throws -> Data {
        try PassiveBluetoothExperimentOneSoftwareExportCodec.encode(
            finalizedSoftwareExportForCurrentApplication(),
            prettyPrinted: prettyPrinted
        )
    }
''',
'''    func finalizedSoftwareExportForCurrentApplication(
        setup: PassiveBluetoothStationaryCaptureSetup
    ) throws -> PassiveBluetoothExperimentOneSoftwareExport {
        guard let finalizedArtifact else {
            throw PassiveBluetoothExperimentOneSoftwareExportError.artifactNotFinalized
        }
        return try PassiveBluetoothExperimentOneSoftwareExportCodec.makeForCurrentApplication(
            finalizedArtifact: finalizedArtifact,
            setup: setup
        )
    }

    func encodedFinalizedSoftwareExportForCurrentApplication(
        setup: PassiveBluetoothStationaryCaptureSetup,
        prettyPrinted: Bool = true
    ) throws -> Data {
        try PassiveBluetoothExperimentOneSoftwareExportCodec.encode(
            finalizedSoftwareExportForCurrentApplication(setup: setup),
            prettyPrinted: prettyPrinted
        )
    }
''',
"coordinator helpers"
)

p.write_text(s)
