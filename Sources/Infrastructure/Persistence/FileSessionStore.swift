import Foundation

actor FileSessionStore: SessionStore {
    enum PersistenceError: Error {
        case malformedData
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            fileManager.temporaryDirectory
        let directory = appSupport.appendingPathComponent("MotionRehabCoach", isDirectory: true)
        self.fileURL = directory.appendingPathComponent("sessions.json")

        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func fetchSessions() async throws -> [ExerciseSession] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }

        return try decoder.decode([ExerciseSession].self, from: data)
            .sorted(by: { $0.startedAt > $1.startedAt })
    }

    func append(_ session: ExerciseSession) async throws {
        var sessions = try await fetchSessions()
        sessions.append(session)
        let trimmed = Array(sessions.sorted(by: { $0.startedAt > $1.startedAt }).prefix(500))

        let data = try encoder.encode(trimmed)
        try data.write(to: fileURL, options: .atomic)
    }
}
