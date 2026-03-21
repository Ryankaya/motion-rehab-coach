# Motion Rehab Coach

Motion Rehab Coach is a production-oriented iOS app foundation for guided rehab exercise sessions with on-device pose tracking.

## Product goals

- Real-time movement feedback during rehab exercises.
- Session summaries with repetition and form quality metrics.
- Local-first storage with privacy-preserving architecture.
- Expandable platform for therapist-prescribed protocols.

## Technical architecture

- `Domain`: Core entities, protocols, and movement analysis logic.
- `Infrastructure`: Camera capture, Vision pose estimation, and persistence adapters.
- `Application`: MVVM view models and orchestration.
- `Presentation`: SwiftUI screens/components.
- `Tests`: Domain behavior tests (rep counting, scoring).

## Current production-ready baseline

- Live camera capture with iOS permissions handling.
- On-device pose estimation via Vision human body pose request.
- Squat repetition analysis with quality scoring.
- Session history persisted locally in app support directory.
- Unit tests for repetition analyzer logic.

## Apple technologies

- Vision framework for body pose detection.
- AVFoundation for camera capture pipeline.
- SwiftUI + MVVM for presentation and state management.

## Build

```bash
xcodegen generate
xcodebuild -project motion-rehab-coach.xcodeproj -scheme motion-rehab-coach -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
