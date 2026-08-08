import Testing
@testable import NembraBluetoothCapture

struct PassiveCoreBluetoothArtifactAuthorityContextTests {
    @Test
    func exactFrozenAuthorityRemainsValid() {
        let context = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 7,
            authorityGeneration: 11
        )

        #expect(
            context.matches(
                targetSessionGeneration: 7,
                authorityGeneration: 11
            )
        )
    }

    @Test
    func targetSessionChangeInvalidatesSuspendedArtifactRead() {
        let context = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 7,
            authorityGeneration: 11
        )

        #expect(
            !context.matches(
                targetSessionGeneration: 8,
                authorityGeneration: 11
            )
        )
    }

    @Test
    func authorityGenerationChangeInvalidatesSuspendedArtifactRead() {
        let context = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 7,
            authorityGeneration: 11
        )

        #expect(
            !context.matches(
                targetSessionGeneration: 7,
                authorityGeneration: 12
            )
        )
    }
}
