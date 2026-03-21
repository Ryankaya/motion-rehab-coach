import Foundation

protocol SessionStore {
    func fetchSessions() async throws -> [ExerciseSession]
    func append(_ session: ExerciseSession) async throws
}
