import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothPowerOnCandidateAssociationTests {
    private let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let third = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    @Test
    func exactlyOneNewEligibleIdentifierResolvesUniquely() {
        let resolution = PassiveBluetoothPowerOnCandidateAssociation.resolve(
            baselineEligibleIdentifiers: [first],
            refreshedEligibleIdentifiers: [first, second]
        )

        #expect(resolution == .uniqueNewCandidate(second))
    }

    @Test
    func noNewEligibleIdentifierFailsClosed() {
        let resolution = PassiveBluetoothPowerOnCandidateAssociation.resolve(
            baselineEligibleIdentifiers: [first, second],
            refreshedEligibleIdentifiers: [first, second]
        )

        #expect(resolution == .noNewCandidate)
    }

    @Test
    func disappearingBaselineIdentifiersDoNotBecomePositiveEvidence() {
        let resolution = PassiveBluetoothPowerOnCandidateAssociation.resolve(
            baselineEligibleIdentifiers: [first, second],
            refreshedEligibleIdentifiers: [second]
        )

        #expect(resolution == .noNewCandidate)
    }

    @Test
    func multipleNewEligibleIdentifiersRemainAmbiguous() {
        let resolution = PassiveBluetoothPowerOnCandidateAssociation.resolve(
            baselineEligibleIdentifiers: [first],
            refreshedEligibleIdentifiers: [first, third, second]
        )

        #expect(resolution == .ambiguousNewCandidates([second, third]))
    }

    @Test
    func ambiguityOrderingIsDeterministicAcrossInputOrder() {
        let forward = PassiveBluetoothPowerOnCandidateAssociation.resolve(
            baselineEligibleIdentifiers: [],
            refreshedEligibleIdentifiers: [third, first, second]
        )
        let reverse = PassiveBluetoothPowerOnCandidateAssociation.resolve(
            baselineEligibleIdentifiers: [],
            refreshedEligibleIdentifiers: [second, first, third]
        )

        let expected = PassiveBluetoothPowerOnCandidateAssociation.Resolution
            .ambiguousNewCandidates([first, second, third])
        #expect(forward == expected)
        #expect(reverse == expected)
    }

    @Test
    func preexistingCandidatesCannotWinOverOneNewCandidate() {
        let resolution = PassiveBluetoothPowerOnCandidateAssociation.resolve(
            baselineEligibleIdentifiers: [first, second],
            refreshedEligibleIdentifiers: [first, second, third]
        )

        #expect(resolution == .uniqueNewCandidate(third))
    }
}
