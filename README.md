EyeTrackKit
====
- An iOS Framework that enables developers to use eye track information with ARKit content.

## Key Features
- Acquire eye tracking info
    - face position & rotation
    - eyes position
    - lookAtPosition in World
    - lookAtPoint on device screen
    - blink
    - distance
    - tracking confidence (multi-source gaze fusion)
- Record AR scene to video (built-in `AVAssetWriter` + Metal pipeline, no third-party dependency)

## Compatibility
`EyeTrackKit` is compatible on iOS devices that support [`ARKit`](https://developer.apple.com/documentation/arkit) face tracking (TrueDepth camera required).

`EyeTrackKit` requires:
- SwiftUI
- iOS 16+
- Swift 5.9 or higher

## Installation
### Swift Package Manager

1. In Xcode, select File > Add Package Dependencies…
2. Use this repository's URL.

EyeTrackKit has **zero external dependencies** — only Apple frameworks
(`ARKit`, `SceneKit`, `AVFoundation`, `Metal`, `Photos`, `SwiftUI`).

### Required Info.plist usage descriptions
```
<key>NSCameraUsageDescription</key>
<string>AR face tracking</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Save AR session recordings</string>
<key>NSMicrophoneUsageDescription</key>
<string>(only if you add audio recording)</string>
```

## Recording

The built-in `EyeTrackRecorder` captures the rendered `ARSCNView` content
directly via `SCNRenderer` and `AVAssetWriter`. Frames are pulled from a
pre-warmed IOSurface-backed `CVPixelBufferPool` and rendered to a
zero-copy Metal texture, so capture is GPU-bound and does not stall the
main thread.

Default codec is HEVC at 6 Mbps. Override via
`EyeTrackRecorder.Configuration` when constructing the view:

```swift
EyeTrackController(
    device: Device(type: .iPhone15Pro),
    smoothingRange: 5,
    blinkThreshold: 0.5,
    isHidden: false
)
```

## Gaze tracking

`GazeEstimator` fuses three TrueDepth-derived signals per frame:

1. Geometric raycast through each pupil (legacy method)
2. `ARFaceAnchor.lookAtPoint` — Apple's native gaze hint
3. Eye yaw/pitch reconstructed from `eyeLookIn/Out/Up/Down` blend shapes

Each estimate is fed to a per-axis 1-D Kalman filter, and outliers are
down-weighted using the inter-source median distance. The resulting
`trackingConfidence` (0…1) is exposed on `EyeTrack` and `EyeTrackInfo`.

## Develop Environment
- Language: [Swift](https://developer.apple.com/swift/)
- Frameworks: [ARKit](https://developer.apple.com/documentation/arkit/), AVFoundation, Metal, SceneKit

## Licence
[MIT](https://github.com/ukitomato/EyeTrackKit/blob/master/LICENSE)

## Author
Yuki Yamato [[ukitomato](https://github.com/ukitomato)]
