import Foundation

@MainActor
final class SessionHistoryViewModel: ObservableObject {
    @Published private(set) var sessions: [ExerciseSession] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let sessionStore: any SessionStore

    init(sessionStore: any SessionStore) {
        self.sessionStore = sessionStore
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            sessions = try await sessionStore.fetchSessions()
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load sessions: \(error.localizedDescription)"
        }
    }
}
