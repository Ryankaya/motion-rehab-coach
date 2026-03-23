# Motion Rehab Coach

Motion Rehab Coach is a production-oriented iOS rehabilitation assistant built with SwiftUI + MVVM. It provides on-device movement tracking, personalized targets, voice coaching, and therapist-friendly reporting.

## Production feature set

- Real-time camera tracking with Vision pose estimation and robust tracking-state feedback.
- Multi-program rehab protocols:
  - Bodyweight Squat
  - Sit to Stand
  - Forward Lunge
  - Mini Squat
  - Calf Raise
- Personalized calibration wizard that captures baseline stance and camera framing.
- Adaptive target zones that update from recent high-quality reps.
- Symmetry scoring with compensation alerts.
- Tempo coaching (eccentric/concentric timing) with optional metronome cues.
- Pain + RPE intake before sessions with protocol auto-adjustment.
- Watch telemetry bridge (heart-rate ingest and live session payloads).
- Session history with trend charts and exportable PDF clinical report.

## Architecture

- `Domain`: entities, protocols, and exercise analysis services.
- `Application`: MVVM view models coordinating session state and workflows.
- `Infrastructure`: camera, Vision pose estimation, voice engine, watch sync, and persistence.
- `Presentation`: SwiftUI feature screens and reusable components.
- `Tests`: analyzer-focused unit tests.

## Apple technologies used

- [Vision](https://developer.apple.com/documentation/vision)
- [Detecting Human Body Poses in Images](https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images)
- [AVFoundation](https://developer.apple.com/documentation/avfoundation)
- [WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity)
- [Swift Charts](https://developer.apple.com/documentation/charts)
- [UIKit PDF Renderer](https://developer.apple.com/documentation/uikit/uigraphicspdfrenderer)

## Build

```bash
xcodegen generate
xcodebuild -project motion-rehab-coach.xcodeproj -scheme motion-rehab-coach -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```
