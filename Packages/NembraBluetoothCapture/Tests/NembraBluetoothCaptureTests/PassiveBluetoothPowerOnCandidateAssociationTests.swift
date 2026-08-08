import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothPowerOnCandidateAssociationTests {
    private let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let third = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    @Test
    func exactlyOneNewConnectableIdentifierResolvesUniquely() {
        let resolution = PassiveBluetoothPowerOnCandidateAssociation.resolve(
            baselineConnectableIdentifiers: [first],
            refreshedConnectableIdentifiers: [first, second]
        )

        #expect(resolution == .uniqueNewCandidate(second))
    }

    @Test
    func noNewConnectableIdentifierFailsClosed() {
        let resolution = PassiveBluetoothPowerOnCandidateAssociation.resolve(
            baselineConnectableIdentifiers: [first, second],
            refreshedConnectableIdentifiers: [first, second]
        )

        #expect(resolution == .noNewCandidate)
    }

    @Test
    func disappearingBaselineIdentifiersDoNotBecomePositiveEvidence() {
        let resolution = PassiveBluetoothPowerOnCandidateAssociation.resolve(
            baselineConnectableIdentifiers: [first, second],
            refreshedConnectableIdentifiers: [second]
        )

        #expect(resolution == .noNewCandidate)
    }

    @Test
    func multipleNewConnectableIdentifiersRemainAmbiguous() {
        let resolution = PassiveBluetoothPowerOnCandidateAssociation.resolve(
            baselineConnectableIdentifiers: [first],
            refreshedConnectableIdentifiers: [first, third, second]
        )

        #expect(resolution == .ambiguousNewCandidates([second, third]))
    }

    @Test
    func ambiguityOrderingIsDeterministicAcrossInputOrder() {
        let forward = PassiveBluetoothPowerOnCandidateAssociation.resolve(
            baselineConnectableIdentifiers: [],
            refreshedConnectableIdentifiers: [third, first, second]
        )
        let reverse = PassiveBluetoothPowerOnCandidateAssociation.resolve(
            baselineConnectableIdentifiers: [],
            refreshedConnectableIdentifiers: [second, first, third]
        )

        let expected = PassiveBluetoothPowerOnCandidateAssociation.Resolution
            .ambiguousNewCandidates([first, second, third])
        #expect(forward == expected)
        #expect(reverse == expected)
    }

    @Test
    func preexistingStrongCandidateCannotWinOverOneNewCandidate() {
        let resolution = PassiveBluetoothPowerOnCandidateAssociation.resolve(
            baselineConnectableIdentifiers: [first, second],
            refreshedConnectableIdentifiers: [first, second, third]
        )

        #expect(resolution == .uniqueNewCandidate(third))
    }
}
