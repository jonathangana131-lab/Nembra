import Testing
@testable import NembraCore

@Suite("Tuya DP electrical coherence research evidence")
struct TuyaCandidateDPElectricalCoherenceTests {
    private func stream(characteristic: String = "C") throws -> TuyaCandidateValueStreamIdentity {
        try TuyaCandidateValueStreamIdentity(
            peripheralIdentifier: "P",
            serviceIdentifier: "S",
            characteristicIdentifier: characteristic
        )
    }

    private func scope(
        field: String,
        characteristic: String = "C",
        generation: UInt64 = 7,
        width: TuyaCandidateDPDataLengthWidth = .twoByteBigEndian
    ) throws -> TuyaCandidateDPMarkerCorrelationScope {
        try TuyaCandidateDPMarkerCorrelationScope(
            fieldLabel: field,
            streamIdentity: stream(characteristic: characteristic),
            continuityGeneration: generation,
            dataLengthWidth: width
        )
    }

    private func marker(_ time: UInt64, field: String, index: Int) throws -> TuyaCandidateDPStockAppMarker {
        try TuyaCandidateDPStockAppMarker(
            receiptUptimeNanoseconds: time,
            displayedReference: "\(field)-marker-\(index)"
        )
    }

    private func record(id: UInt8, value: [UInt8]) -> TuyaCandidateDPRecord {
        TuyaCandidateDPRecord(
            headerByteOffset: 0,
            valueByteOffset: 4,
            endByteOffsetExclusive: 4 + value.count,
            identifier: id,
            rawType: TuyaCandidateDPKnownType.value.rawValue,
            knownType: .value,
            declaredValueLength: value.count,
            valueBytes: value,
            shapeFinding: .fixedLengthKnownType(.value, allowedLengths: [value.count])
        )
    }

    private func observation(
        scope: TuyaCandidateDPMarkerCorrelationScope,
        time: UInt64,
        id: UInt8,
        value: [UInt8]
    ) -> TuyaCandidateDPMessageObservation {
        let message = TuyaCandidateReassembledMessage(
            streamIdentity: scope.streamIdentity,
            continuityGeneration: scope.continuityGeneration,
            protocolVersionByte: 0x20,
            protocolVersionHighNibble: 2,
            encryptedBytes: [0xAA],
            fragmentCount: 1,
            firstReceiptUptimeNanoseconds: time,
            lastReceiptUptimeNanoseconds: time
        )
        let parsed = TuyaCandidateDPPayload(
            dataLengthWidth: scope.dataLengthWidth,
            sourceByteCount: 4 + value.count,
            records: [record(id: id, value: value)]
        )
        return TuyaCandidateDPMessageObservation(
            reassembledMessage: message,
            parsedPayload: parsed
        )
    }

    private func numericReport(
        field: String,
        markerTimes: [UInt64],
        rawValues: [[UInt8]],
        numericValues: [Double?],
        scale: Double,
        candidateID: UInt8,
        characteristic: String = "C",
        generation: UInt64 = 7,
        width: TuyaCandidateDPDataLengthWidth = .twoByteBigEndian,
        numericTolerance: Double = 0.000_001,
        duplicateSelectedHypothesis: Bool = false
    ) throws -> TuyaCandidateDPNumericHypothesisReport {
        let correlationScope = try scope(
            field: field,
            characteristic: characteristic,
            generation: generation,
            width: width
        )
        let markers = try markerTimes.enumerated().map { index, time in
            try marker(time, field: field, index: index)
        }
        let observations = zip(markerTimes, rawValues).map { time, rawValue in
            observation(
                scope: correlationScope,
                time: time,
                id: candidateID,
                value: rawValue
            )
        }
        let parent = try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: correlationScope,
            markers: markers,
            observations: observations,
            policy: TuyaCandidateDPMarkerCorrelationPolicy(
                maximumMarkerDistanceNanoseconds: 0,
                maximumMarkerCount: 32,
                maximumObservationCount: 32,
                maximumCandidateOccurrenceCount: 64
            )
        )
        let numericReferences = try numericValues.enumerated().compactMap { index, value in
            guard let value else { return nil }
            return try TuyaCandidateDPNumericReference(markerIndex: index, value: value)
        }
        var hypotheses = [
            try TuyaCandidateDPNumericTransformHypothesis(
                identifier: "selected",
                scale: scale
            )
        ]
        if duplicateSelectedHypothesis {
            hypotheses.append(
                try TuyaCandidateDPNumericTransformHypothesis(
                    identifier: "selected",
                    scale: scale
                )
            )
        }
        return try TuyaCandidateDPNumericHypothesisEvaluator.evaluate(
            report: parent,
            candidateIndex: 0,
            numericReferences: numericReferences,
            hypotheses: hypotheses,
            policy: TuyaCandidateDPNumericHypothesisPolicy(
                maximumReferenceCount: 32,
                maximumHypothesisCount: 8,
                absoluteTolerance: numericTolerance
            )
        )
    }

    private func coherencePolicy(
        span: UInt64 = 30,
        absolute: Double = 0.000_001,
        relative: Double = 0
    ) throws -> TuyaCandidateDPElectricalCoherencePolicy {
        try TuyaCandidateDPElectricalCoherencePolicy(
            maximumAnchorCount: 16,
            maximumEvidenceSpanNanoseconds: span,
            absolutePowerTolerance: absolute,
            relativePowerTolerance: relative
        )
    }

    private func anchor(_ index: Int) throws -> TuyaCandidateDPElectricalAnchor {
        try TuyaCandidateDPElectricalAnchor(
            voltageMarkerIndex: index,
            currentMarkerIndex: index,
            powerMarkerIndex: index
        )
    }

    private func uint16(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    @Test("repeated stock anchors and transformed candidates jointly support explicit V×I=P research hypothesis")
    func repeatedJointSupportPreservesRawEvidence() throws {
        let voltage = try numericReport(
            field: "Voltage",
            markerTimes: [100, 1_000],
            rawValues: [uint16(410), uint16(400)],
            numericValues: [41, 40],
            scale: 0.1,
            candidateID: 1
        )
        let current = try numericReport(
            field: "Current",
            markerTimes: [110, 1_010],
            rawValues: [[10], [15]],
            numericValues: [1, 1.5],
            scale: 0.1,
            candidateID: 2
        )
        let power = try numericReport(
            field: "Power",
            markerTimes: [120, 1_020],
            rawValues: [uint16(410), uint16(600)],
            numericValues: [41, 60],
            scale: 0.1,
            candidateID: 3
        )

        let result = try TuyaCandidateDPElectricalCoherenceEvaluator.evaluate(
            voltageReport: voltage,
            voltageHypothesisIdentifier: "selected",
            currentReport: current,
            currentHypothesisIdentifier: "selected",
            powerReport: power,
            powerHypothesisIdentifier: "selected",
            anchors: [try anchor(0), try anchor(1)],
            policy: coherencePolicy()
        )

        #expect(result.scope.voltageFieldLabel == "Voltage")
        #expect(result.scope.currentFieldLabel == "Current")
        #expect(result.scope.powerFieldLabel == "Power")
        #expect(result.voltageSelection.candidate.identifier == 1)
        #expect(result.currentSelection.candidate.identifier == 2)
        #expect(result.powerSelection.candidate.identifier == 3)
        #expect(result.requestedAnchorCount == 2)
        #expect(result.evaluations.count == 2)
        #expect(result.rejectedAnchors.isEmpty)
        #expect(result.referenceRelationshipMatchedCount == 2)
        #expect(result.candidateRelationshipMatchedCount == 2)
        #expect(result.allNumericHypothesesMatchedCount == 2)
        #expect(result.jointSupportCount == 2)

        let first = try #require(result.evaluations.first)
        #expect(first.evidenceSpanNanoseconds == 20)
        #expect(first.referencePredictedPower == 41)
        #expect(first.candidatePredictedPower == 41)
        #expect(first.voltageSample.rawUnsignedMagnitude == 410)
        #expect(first.voltageSample.valueBytes == uint16(410))
        #expect(first.currentSample.valueBytes == [10])
        #expect(first.powerSample.valueBytes == uint16(410))
        #expect(first.supportsJointHypothesis)
    }

    @Test("stock reference coherence does not rescue a candidate transform that misses its own anchors")
    func candidateMismatchRemainsVisible() throws {
        let voltage = try numericReport(
            field: "Voltage",
            markerTimes: [100],
            rawValues: [uint16(410)],
            numericValues: [41],
            scale: 0.1,
            candidateID: 1
        )
        let current = try numericReport(
            field: "Current",
            markerTimes: [110],
            rawValues: [[20]],
            numericValues: [1],
            scale: 0.1,
            candidateID: 2
        )
        let power = try numericReport(
            field: "Power",
            markerTimes: [120],
            rawValues: [uint16(410)],
            numericValues: [41],
            scale: 0.1,
            candidateID: 3
        )

        let result = try TuyaCandidateDPElectricalCoherenceEvaluator.evaluate(
            voltageReport: voltage,
            voltageHypothesisIdentifier: "selected",
            currentReport: current,
            currentHypothesisIdentifier: "selected",
            powerReport: power,
            powerHypothesisIdentifier: "selected",
            anchors: [try anchor(0)],
            policy: coherencePolicy()
        )
        let evaluation = try #require(result.evaluations.first)
        #expect(evaluation.referenceRelationshipWithinTolerance)
        #expect(!evaluation.allNumericHypothesesMatchReferences)
        #expect(!evaluation.candidateRelationshipWithinTolerance)
        #expect(!evaluation.supportsJointHypothesis)
        #expect(result.jointSupportCount == 0)
    }

    @Test("relative tolerance is explicit caller policy rather than an ES80 default")
    func relativeToleranceIsExplicit() throws {
        let voltage = try numericReport(
            field: "Voltage",
            markerTimes: [100],
            rawValues: [uint16(410)],
            numericValues: [41],
            scale: 0.1,
            candidateID: 1
        )
        let current = try numericReport(
            field: "Current",
            markerTimes: [110],
            rawValues: [[10]],
            numericValues: [1],
            scale: 0.1,
            candidateID: 2
        )
        let power = try numericReport(
            field: "Power",
            markerTimes: [120],
            rawValues: [uint16(420)],
            numericValues: [42],
            scale: 0.1,
            candidateID: 3
        )

        let strict = try TuyaCandidateDPElectricalCoherenceEvaluator.evaluate(
            voltageReport: voltage,
            voltageHypothesisIdentifier: "selected",
            currentReport: current,
            currentHypothesisIdentifier: "selected",
            powerReport: power,
            powerHypothesisIdentifier: "selected",
            anchors: [try anchor(0)],
            policy: coherencePolicy(absolute: 0, relative: 0)
        )
        #expect(strict.jointSupportCount == 0)

        let tolerant = try TuyaCandidateDPElectricalCoherenceEvaluator.evaluate(
            voltageReport: voltage,
            voltageHypothesisIdentifier: "selected",
            currentReport: current,
            currentHypothesisIdentifier: "selected",
            powerReport: power,
            powerHypothesisIdentifier: "selected",
            anchors: [try anchor(0)],
            policy: coherencePolicy(absolute: 0, relative: 0.025)
        )
        let evaluation = try #require(tolerant.evaluations.first)
        #expect(evaluation.referenceAllowedPowerError == 1.05)
        #expect(evaluation.referenceAbsolutePowerError == 1)
        #expect(evaluation.referenceRelationshipWithinTolerance)
        #expect(evaluation.candidateRelationshipWithinTolerance)
        #expect(evaluation.supportsJointHypothesis)
    }

    @Test("explicit negative transforms remain signed; evaluator never invents regen or absolute current")
    func explicitSignedTransformIsPreserved() throws {
        let voltage = try numericReport(
            field: "Voltage",
            markerTimes: [100],
            rawValues: [uint16(400)],
            numericValues: [40],
            scale: 0.1,
            candidateID: 1
        )
        let current = try numericReport(
            field: "Current",
            markerTimes: [110],
            rawValues: [[10]],
            numericValues: [-1],
            scale: -0.1,
            candidateID: 2
        )
        let power = try numericReport(
            field: "Power",
            markerTimes: [120],
            rawValues: [uint16(400)],
            numericValues: [-40],
            scale: -0.1,
            candidateID: 3
        )

        let result = try TuyaCandidateDPElectricalCoherenceEvaluator.evaluate(
            voltageReport: voltage,
            voltageHypothesisIdentifier: "selected",
            currentReport: current,
            currentHypothesisIdentifier: "selected",
            powerReport: power,
            powerHypothesisIdentifier: "selected",
            anchors: [try anchor(0)],
            policy: coherencePolicy()
        )
        let evaluation = try #require(result.evaluations.first)
        #expect(evaluation.currentSample.transformedCandidateValue == -1)
        #expect(evaluation.candidatePredictedPower == -40)
        #expect(evaluation.supportsJointHypothesis)
    }

    @Test("too-wide marker and candidate timing span is rejected instead of treated as simultaneous")
    func rejectsWideEvidenceSpan() throws {
        let voltage = try numericReport(
            field: "Voltage",
            markerTimes: [100],
            rawValues: [uint16(410)],
            numericValues: [41],
            scale: 0.1,
            candidateID: 1
        )
        let current = try numericReport(
            field: "Current",
            markerTimes: [200],
            rawValues: [[10]],
            numericValues: [1],
            scale: 0.1,
            candidateID: 2
        )
        let power = try numericReport(
            field: "Power",
            markerTimes: [110],
            rawValues: [uint16(410)],
            numericValues: [41],
            scale: 0.1,
            candidateID: 3
        )

        let result = try TuyaCandidateDPElectricalCoherenceEvaluator.evaluate(
            voltageReport: voltage,
            voltageHypothesisIdentifier: "selected",
            currentReport: current,
            currentHypothesisIdentifier: "selected",
            powerReport: power,
            powerHypothesisIdentifier: "selected",
            anchors: [try anchor(0)],
            policy: coherencePolicy(span: 30)
        )
        #expect(result.evaluations.isEmpty)
        #expect(result.rejectedAnchors.count == 1)
        #expect(
            result.rejectedAnchors.first?.reason
                == .evidenceSpanExceedsPolicy(actual: 100, maximum: 30)
        )
    }

    @Test("missing numeric evidence is retained as an explicit role-specific rejection")
    func missingSampleIsNotDropped() throws {
        let voltage = try numericReport(
            field: "Voltage",
            markerTimes: [100],
            rawValues: [uint16(410)],
            numericValues: [41],
            scale: 0.1,
            candidateID: 1
        )
        let current = try numericReport(
            field: "Current",
            markerTimes: [110],
            rawValues: [[10]],
            numericValues: [1],
            scale: 0.1,
            candidateID: 2
        )
        let power = try numericReport(
            field: "Power",
            markerTimes: [120],
            rawValues: [uint16(410)],
            numericValues: [nil],
            scale: 0.1,
            candidateID: 3
        )

        let result = try TuyaCandidateDPElectricalCoherenceEvaluator.evaluate(
            voltageReport: voltage,
            voltageHypothesisIdentifier: "selected",
            currentReport: current,
            currentHypothesisIdentifier: "selected",
            powerReport: power,
            powerHypothesisIdentifier: "selected",
            anchors: [try anchor(0)],
            policy: coherencePolicy()
        )
        #expect(result.evaluations.isEmpty)
        #expect(
            result.rejectedAnchors.first?.reason
                == .missingNumericSample(role: .power, markerIndex: 0)
        )
        #expect(result.meanCandidateAbsolutePowerError == nil)
    }

    @Test("stream, continuity generation, and framing width may never be mixed across roles")
    func scopeMismatchFailsClosed() throws {
        let voltage = try numericReport(
            field: "Voltage",
            markerTimes: [100],
            rawValues: [uint16(410)],
            numericValues: [41],
            scale: 0.1,
            candidateID: 1
        )
        let wrongStreamCurrent = try numericReport(
            field: "Current",
            markerTimes: [110],
            rawValues: [[10]],
            numericValues: [1],
            scale: 0.1,
            candidateID: 2,
            characteristic: "D"
        )
        let power = try numericReport(
            field: "Power",
            markerTimes: [120],
            rawValues: [uint16(410)],
            numericValues: [41],
            scale: 0.1,
            candidateID: 3
        )

        #expect(throws: TuyaCandidateDPElectricalCoherenceError.streamIdentityMismatch(role: .current)) {
            try TuyaCandidateDPElectricalCoherenceEvaluator.evaluate(
                voltageReport: voltage,
                voltageHypothesisIdentifier: "selected",
                currentReport: wrongStreamCurrent,
                currentHypothesisIdentifier: "selected",
                powerReport: power,
                powerHypothesisIdentifier: "selected",
                anchors: [try anchor(0)],
                policy: coherencePolicy()
            )
        }

        let wrongGenerationCurrent = try numericReport(
            field: "Current",
            markerTimes: [110],
            rawValues: [[10]],
            numericValues: [1],
            scale: 0.1,
            candidateID: 2,
            generation: 8
        )
        #expect(throws: TuyaCandidateDPElectricalCoherenceError.continuityGenerationMismatch(role: .current)) {
            try TuyaCandidateDPElectricalCoherenceEvaluator.evaluate(
                voltageReport: voltage,
                voltageHypothesisIdentifier: "selected",
                currentReport: wrongGenerationCurrent,
                currentHypothesisIdentifier: "selected",
                powerReport: power,
                powerHypothesisIdentifier: "selected",
                anchors: [try anchor(0)],
                policy: coherencePolicy()
            )
        }

        let wrongWidthPower = try numericReport(
            field: "Power",
            markerTimes: [120],
            rawValues: [uint16(410)],
            numericValues: [41],
            scale: 0.1,
            candidateID: 3,
            width: .oneByte
        )
        let current = try numericReport(
            field: "Current",
            markerTimes: [110],
            rawValues: [[10]],
            numericValues: [1],
            scale: 0.1,
            candidateID: 2
        )
        #expect(throws: TuyaCandidateDPElectricalCoherenceError.dataLengthWidthMismatch(role: .power)) {
            try TuyaCandidateDPElectricalCoherenceEvaluator.evaluate(
                voltageReport: voltage,
                voltageHypothesisIdentifier: "selected",
                currentReport: current,
                currentHypothesisIdentifier: "selected",
                powerReport: wrongWidthPower,
                powerHypothesisIdentifier: "selected",
                anchors: [try anchor(0)],
                policy: coherencePolicy()
            )
        }
    }

    @Test("hypothesis selection is exact and duplicate identifiers stay ambiguous")
    func hypothesisIdentityFailsClosed() throws {
        let voltage = try numericReport(
            field: "Voltage",
            markerTimes: [100],
            rawValues: [uint16(410)],
            numericValues: [41],
            scale: 0.1,
            candidateID: 1
        )
        let current = try numericReport(
            field: "Current",
            markerTimes: [110],
            rawValues: [[10]],
            numericValues: [1],
            scale: 0.1,
            candidateID: 2
        )
        let power = try numericReport(
            field: "Power",
            markerTimes: [120],
            rawValues: [uint16(410)],
            numericValues: [41],
            scale: 0.1,
            candidateID: 3,
            duplicateSelectedHypothesis: true
        )

        #expect(throws: TuyaCandidateDPElectricalCoherenceError.missingHypothesis(role: .voltage, identifier: "missing")) {
            try TuyaCandidateDPElectricalCoherenceEvaluator.evaluate(
                voltageReport: voltage,
                voltageHypothesisIdentifier: "missing",
                currentReport: current,
                currentHypothesisIdentifier: "selected",
                powerReport: power,
                powerHypothesisIdentifier: "selected",
                anchors: [try anchor(0)],
                policy: coherencePolicy()
            )
        }
        #expect(throws: TuyaCandidateDPElectricalCoherenceError.ambiguousHypothesisIdentifier(role: .power, identifier: "selected")) {
            try TuyaCandidateDPElectricalCoherenceEvaluator.evaluate(
                voltageReport: voltage,
                voltageHypothesisIdentifier: "selected",
                currentReport: current,
                currentHypothesisIdentifier: "selected",
                powerReport: power,
                powerHypothesisIdentifier: "selected",
                anchors: [try anchor(0)],
                policy: coherencePolicy()
            )
        }
    }

    @Test("anchor reuse cannot manufacture repeated support")
    func duplicateAndReusedAnchorsFailClosed() throws {
        let duplicate = try anchor(0)
        #expect(throws: TuyaCandidateDPElectricalCoherenceError.duplicateAnchor(anchorIndex: 1, previousAnchorIndex: 0)) {
            let voltage = try numericReport(
                field: "Voltage", markerTimes: [100], rawValues: [uint16(410)],
                numericValues: [41], scale: 0.1, candidateID: 1
            )
            let current = try numericReport(
                field: "Current", markerTimes: [110], rawValues: [[10]],
                numericValues: [1], scale: 0.1, candidateID: 2
            )
            let power = try numericReport(
                field: "Power", markerTimes: [120], rawValues: [uint16(410)],
                numericValues: [41], scale: 0.1, candidateID: 3
            )
            try TuyaCandidateDPElectricalCoherenceEvaluator.evaluate(
                voltageReport: voltage,
                voltageHypothesisIdentifier: "selected",
                currentReport: current,
                currentHypothesisIdentifier: "selected",
                powerReport: power,
                powerHypothesisIdentifier: "selected",
                anchors: [duplicate, duplicate],
                policy: coherencePolicy()
            )
        }

        let voltage = try numericReport(
            field: "Voltage", markerTimes: [100, 200], rawValues: [uint16(410), uint16(400)],
            numericValues: [41, 40], scale: 0.1, candidateID: 1
        )
        let current = try numericReport(
            field: "Current", markerTimes: [110, 210], rawValues: [[10], [10]],
            numericValues: [1, 1], scale: 0.1, candidateID: 2
        )
        let power = try numericReport(
            field: "Power", markerTimes: [120, 220], rawValues: [uint16(410), uint16(400)],
            numericValues: [41, 40], scale: 0.1, candidateID: 3
        )
        let first = try TuyaCandidateDPElectricalAnchor(
            voltageMarkerIndex: 0,
            currentMarkerIndex: 0,
            powerMarkerIndex: 0
        )
        let second = try TuyaCandidateDPElectricalAnchor(
            voltageMarkerIndex: 0,
            currentMarkerIndex: 1,
            powerMarkerIndex: 1
        )
        #expect(throws: TuyaCandidateDPElectricalCoherenceError.reusedMarkerIndex(role: .voltage, index: 0)) {
            try TuyaCandidateDPElectricalCoherenceEvaluator.evaluate(
                voltageReport: voltage,
                voltageHypothesisIdentifier: "selected",
                currentReport: current,
                currentHypothesisIdentifier: "selected",
                powerReport: power,
                powerHypothesisIdentifier: "selected",
                anchors: [first, second],
                policy: coherencePolicy(span: 200)
            )
        }
    }

    @Test("nonfinite relationship math is rejected rather than accepted by infinite tolerance")
    func nonFiniteRelationshipFailsClosed() throws {
        let voltage = try numericReport(
            field: "Voltage",
            markerTimes: [100],
            rawValues: [[1]],
            numericValues: [1e308],
            scale: 1e308,
            candidateID: 1
        )
        let current = try numericReport(
            field: "Current",
            markerTimes: [110],
            rawValues: [[1]],
            numericValues: [1e308],
            scale: 1e308,
            candidateID: 2
        )
        let power = try numericReport(
            field: "Power",
            markerTimes: [120],
            rawValues: [[1]],
            numericValues: [1],
            scale: 1,
            candidateID: 3
        )

        let result = try TuyaCandidateDPElectricalCoherenceEvaluator.evaluate(
            voltageReport: voltage,
            voltageHypothesisIdentifier: "selected",
            currentReport: current,
            currentHypothesisIdentifier: "selected",
            powerReport: power,
            powerHypothesisIdentifier: "selected",
            anchors: [try anchor(0)],
            policy: coherencePolicy(absolute: 0, relative: 0)
        )
        #expect(result.evaluations.isEmpty)
        #expect(result.rejectedAnchors.first?.reason == .nonFiniteReferenceRelationship)
    }

    @Test("policy and marker bounds are explicit and fail closed")
    func validatesPolicyAndMarkerBounds() throws {
        #expect(throws: TuyaCandidateDPElectricalCoherenceError.invalidMarkerIndex(role: .voltage, index: -1)) {
            try TuyaCandidateDPElectricalAnchor(
                voltageMarkerIndex: -1,
                currentMarkerIndex: 0,
                powerMarkerIndex: 0
            )
        }
        #expect(throws: TuyaCandidateDPElectricalCoherenceError.invalidMaximumAnchorCount) {
            try TuyaCandidateDPElectricalCoherencePolicy(
                maximumAnchorCount: 0,
                maximumEvidenceSpanNanoseconds: 0,
                absolutePowerTolerance: 0,
                relativePowerTolerance: 0
            )
        }
        #expect(throws: TuyaCandidateDPElectricalCoherenceError.invalidAbsolutePowerTolerance) {
            try TuyaCandidateDPElectricalCoherencePolicy(
                maximumAnchorCount: 1,
                maximumEvidenceSpanNanoseconds: 0,
                absolutePowerTolerance: .nan,
                relativePowerTolerance: 0
            )
        }
        #expect(throws: TuyaCandidateDPElectricalCoherenceError.invalidRelativePowerTolerance) {
            try TuyaCandidateDPElectricalCoherencePolicy(
                maximumAnchorCount: 1,
                maximumEvidenceSpanNanoseconds: 0,
                absolutePowerTolerance: 0,
                relativePowerTolerance: -0.1
            )
        }
    }
}
