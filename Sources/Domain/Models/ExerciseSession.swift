import Foundation

struct ExerciseSession: Codable, Hashable, Identifiable {
    let id: UUID
    let exerciseType: ExerciseType
    let startedAt: Date
    let endedAt: Date
    let repetitionCount: Int
    let averageKneeAngle: Double
    let qualityScore: Double
    let notes: String
    let averageSymmetryScore: Double
    let averageEccentricTempo: Double
    let averageConcentricTempo: Double
    let painScore: Int
    let rpeGoal: Int
    let compensationAlertsCount: Int
    let clinicianSharingMode: Bool

    init(
        id: UUID = UUID(),
        exerciseType: ExerciseType,
        startedAt: Date,
        endedAt: Date,
        repetitionCount: Int,
        averageKneeAngle: Double,
        qualityScore: Double,
        notes: String,
        averageSymmetryScore: Double = 0,
        averageEccentricTempo: Double = 0,
        averageConcentricTempo: Double = 0,
        painScore: Int = 0,
        rpeGoal: Int = 5,
        compensationAlertsCount: Int = 0,
        clinicianSharingMode: Bool = false
    ) {
        self.id = id
        self.exerciseType = exerciseType
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.repetitionCount = repetitionCount
        self.averageKneeAngle = averageKneeAngle
        self.qualityScore = qualityScore
        self.notes = notes
        self.averageSymmetryScore = averageSymmetryScore
        self.averageEccentricTempo = averageEccentricTempo
        self.averageConcentricTempo = averageConcentricTempo
        self.painScore = painScore
        self.rpeGoal = rpeGoal
        self.compensationAlertsCount = compensationAlertsCount
        self.clinicianSharingMode = clinicianSharingMode
    }

    var durationSeconds: Int {
        Int(endedAt.timeIntervalSince(startedAt))
    }

    var averagePrimaryMetric: Double {
        averageKneeAngle
    }
}

private extension ExerciseSession {
    enum CodingKeys: String, CodingKey {
        case id
        case exerciseType
        case startedAt
        case endedAt
        case repetitionCount
        case averageKneeAngle
        case qualityScore
        case notes
        case averageSymmetryScore
        case averageEccentricTempo
        case averageConcentricTempo
        case painScore
        case rpeGoal
        case compensationAlertsCount
        case clinicianSharingMode
    }
}

extension ExerciseSession {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        exerciseType = try container.decode(ExerciseType.self, forKey: .exerciseType)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        repetitionCount = try container.decodeIfPresent(Int.self, forKey: .repetitionCount) ?? 0
        averageKneeAngle = try container.decodeIfPresent(Double.self, forKey: .averageKneeAngle) ?? 0
        qualityScore = try container.decodeIfPresent(Double.self, forKey: .qualityScore) ?? 0
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        averageSymmetryScore = try container.decodeIfPresent(Double.self, forKey: .averageSymmetryScore) ?? 0
        averageEccentricTempo = try container.decodeIfPresent(Double.self, forKey: .averageEccentricTempo) ?? 0
        averageConcentricTempo = try container.decodeIfPresent(Double.self, forKey: .averageConcentricTempo) ?? 0
        painScore = try container.decodeIfPresent(Int.self, forKey: .painScore) ?? 0
        rpeGoal = try container.decodeIfPresent(Int.self, forKey: .rpeGoal) ?? 5
        compensationAlertsCount = try container.decodeIfPresent(Int.self, forKey: .compensationAlertsCount) ?? 0
        clinicianSharingMode = try container.decodeIfPresent(Bool.self, forKey: .clinicianSharingMode) ?? false
    }
}
