EyeTrackKit
====
Eye tracking framework for iOS that uses the TrueDepth camera (Face ID hardware)
through ARKit. Designed to be embedded in third-party apps:

- Multi-source gaze fusion (raycast + Apple's lookAtPoint + blend-shape angles)
- Per-axis Kalman filter, outlier-robust
- User calibration with JSON import/export
- Combine `Publisher` and Swift `AsyncStream` for gaze and tracking events
- Video recording with optional CSV sidecar synchronised to video timestamps
- Zero third-party dependencies — only Apple frameworks

## Compatibility
- iOS 16+, Swift 5.9+
- TrueDepth camera required (`EyeTrackKit.isSupported`)

## Installation (Swift Package Manager)
```
File > Add Package Dependencies… > <repository URL>
```

### Required Info.plist usage descriptions
```xml
<key>NSCameraUsageDescription</key>
<string>AR face tracking</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Save AR session recordings</string>
<key>NSMicrophoneUsageDescription</key>
<string>(only if you add audio recording)</string>
```

## Quick start

```swift
import EyeTrackKit

guard EyeTrackKit.isSupported else { /* fail-fast */ return }
try await EyeTrackKit.requestAuthorization()

let controller = EyeTrackController(
    device: Device(type: .iPhone15Pro),
    smoothingRange: 5,
    blinkThreshold: 0.5,
    coordinateSpace: .screenPoints,
    autoPauseInBackground: true
)

// Modern event APIs
let cancellable = controller.gazeEvents.publisher.sink { event in
    print(event.point, event.confidence)
}

Task {
    for await event in controller.events.stream {
        switch event {
        case .fixation(let point, let duration, _):
            print("fixation at \(point) for \(duration)s")
        case .blink(let side):
            print("blink \(side)")
        case .faceLost: print("face lost")
        default: break
        }
    }
}
```

## Calibration

```swift
let calibrator = Calibrator(
    eyeTrack: controller.eyeTrack,
    targets: Calibrator.standardTargets(.nineGrid, in: screenSize)
)
calibrator.start()
// Drive the calibrator from your UI: show the target at calibrator.state's
// targetIndex, wait until calibrator.collectedCount >= samplesPerTarget,
// then call calibrator.advance().
let profile = try calibrator.finish()
let url = try CalibrationStore.shared.save(profile)
controller.calibrationProfile = profile

// Later, in another session:
try controller.loadCalibrationProfile(from: url)
```

A `CalibrationProfile` is a Codable JSON file with:
- schema version, profile UUID
- device type and screen size at calibration time
- the raw samples
- the fitted 2D affine transform
- per-target residual error in screen points (`meanResidual`, `maxResidual`)

## Configuration bundle

All tunable parameters can be encoded to a single JSON file, ideal for
shipping per-app defaults:

```swift
var config = EyeTrackKit.Configuration.default
config.smoothingRange = 7
config.coordinateSpace = .normalized
config.recorder.codec = .hevc
config.recorder.writeSidecarCSV = true
try config.write(to: url)

let loaded = try EyeTrackKit.Configuration.read(from: url)
let controller = EyeTrackController(configuration: loaded)
```

## Recording

`EyeTrackRecorder` captures the rendered ARSCNView via `SCNRenderer` into a
zero-copy Metal texture, encoded with `AVAssetWriter` (HEVC at 6 Mbps by
default). When `writeSidecarCSV` is enabled, a `<video>.csv` is written
alongside the MP4, with one row per encoded frame and the same time
origin as the video.

```swift
controller.startRecord()
// …
controller.stopRecord(finished: { url in
    print("video at \(url)")
}, isExport: false)
```

## SwiftUI gaze targeting

```swift
import EyeTrackKit

Button("Activate") { activate() }
    .onGazeEnter(eyeTrack: controller.eyeTrack, dwell: 0.5) {
        activate()
    }
    .onGazeExit(eyeTrack: controller.eyeTrack) {
        // …
    }
```

## UIKit gaze hit-testing

```swift
let hit = view.gazeHitTest(controller.eyeTrack.lookAtPoint)
let inside = view.gazeContains(controller.eyeTrack.lookAtPoint)
```

## Background / foreground

When `autoPauseInBackground: true` (default), the controller pauses the
ARSession on `UIApplication.didEnterBackgroundNotification` and resumes
on `willEnterForegroundNotification`. Filters and the Kalman state are
reset on resume to avoid stale predictions.

## Licence
[MIT](LICENSE)

## Original author
Yuki Yamato [[ukitomato](https://github.com/ukitomato)]
