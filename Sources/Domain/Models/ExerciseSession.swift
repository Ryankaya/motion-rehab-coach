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

    init(
        id: UUID = UUID(),
        exerciseType: ExerciseType,
        startedAt: Date,
        endedAt: Date,
        repetitionCount: Int,
        averageKneeAngle: Double,
        qualityScore: Double,
        notes: String
    ) {
        self.id = id
        self.exerciseType = exerciseType
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.repetitionCount = repetitionCount
        self.averageKneeAngle = averageKneeAngle
        self.qualityScore = qualityScore
        self.notes = notes
    }

    var durationSeconds: Int {
        Int(endedAt.timeIntervalSince(startedAt))
    }
}
