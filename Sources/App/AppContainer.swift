import Foundation
import WatchConnectivity

protocol WatchSessionSyncing: AnyObject {
    var isReachable: Bool { get }
    var onHeartRateUpdate: ((Double) -> Void)? { get set }
    func sendLiveUpdate(_ payload: WatchLivePayload)
    func sendSessionSummary(_ payload: WatchSessionSummaryPayload)
}

struct WatchLivePayload: Codable {
    let exerciseType: String
    let reps: Int
    let qualityScore: Double
    let symmetryScore: Double
    let tempoScore: Double
    let paceLabel: String
}

struct WatchSessionSummaryPayload: Codable {
    let exerciseType: String
    let reps: Int
    let qualityScore: Double
    let durationSeconds: Int
}

private struct HeartRatePayload: Codable {
    let heartRate: Double
}

final class WatchConnectivityBridge: NSObject, WatchSessionSyncing {
    var onHeartRateUpdate: ((Double) -> Void)?

    private let session: WCSession? = WCSession.isSupported() ? .default : nil

    var isReachable: Bool {
        session?.isReachable ?? false
    }

    override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func sendLiveUpdate(_ payload: WatchLivePayload) {
        guard let session else { return }
        guard let data = try? JSONEncoder().encode(payload) else { return }

        if session.isReachable {
            session.sendMessageData(data, replyHandler: nil, errorHandler: nil)
        } else {
            try? session.updateApplicationContext([
                "livePayload": data
            ])
        }
    }

    func sendSessionSummary(_ payload: WatchSessionSummaryPayload) {
        guard let session else { return }
        guard let data = try? JSONEncoder().encode(payload) else { return }

        if session.isReachable {
            session.sendMessageData(data, replyHandler: nil, errorHandler: nil)
        } else {
            try? session.updateApplicationContext([
                "sessionSummaryPayload": data
            ])
        }
    }
}

extension WatchConnectivityBridge: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        guard let heartRatePayload = try? JSONDecoder().decode(HeartRatePayload.self, from: messageData) else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onHeartRateUpdate?(heartRatePayload.heartRate)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let heartRate = applicationContext["heartRate"] as? Double else { return }

        DispatchQueue.main.async { [weak self] in
            self?.onHeartRateUpdate?(heartRate)
        }
    }
}

@MainActor
final class AppContainer: ObservableObject {
    private let sessionStore: any SessionStore
    private let watchSync: any WatchSessionSyncing

    init(
        sessionStore: any SessionStore = FileSessionStore(),
        watchSync: any WatchSessionSyncing = WatchConnectivityBridge()
    ) {
        self.sessionStore = sessionStore
        self.watchSync = watchSync
    }

    func makeLiveSessionViewModel(
        exerciseType: ExerciseType,
        painScore: Int,
        rpeGoal: Int,
        clinicianSharingMode: Bool,
        metronomeEnabled: Bool
    ) -> LiveSessionViewModel {
        LiveSessionViewModel(
            exerciseType: exerciseType,
            painScore: painScore,
            rpeGoal: rpeGoal,
            clinicianSharingMode: clinicianSharingMode,
            metronomeEnabled: metronomeEnabled,
            sessionStore: sessionStore,
            poseEstimator: VisionPoseEstimator(),
            cameraService: CameraCaptureService(),
            voiceCoach: SystemVoiceCoach(),
            watchSync: watchSync
        )
    }

    func makeSessionHistoryViewModel() -> SessionHistoryViewModel {
        SessionHistoryViewModel(sessionStore: sessionStore)
    }
}
