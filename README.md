EyeTrackCollisionGame
=====================

A small iOS sample app that uses [EyeTrackKit](../EyeTrackKit) to drive a
gaze-controlled collision game inspired by the WebGazer.js collision demo.
Bouncing balls fly around the screen; you pop them by looking at them.

This project is intentionally **separate** from the EyeTrackKit repository
so the library stays clean.

```
EyeTrackKit/                ← the library
EyeTrackCollisionGame/      ← this app (sibling directory)
```

## Requirements

- iPhone or iPad with a **TrueDepth camera** (iPhone X or newer, iPad Pro
  11"/12.9")
- iOS 16+
- Xcode 15+
- Swift 5.9+

## Project layout

```
EyeTrackCollisionGame/
├── project.yml                     # XcodeGen description
├── EyeTrackCollisionGame/
│   ├── EyeTrackCollisionGameApp.swift
│   ├── Resources/Info.plist
│   ├── Services/EyeTrackingService.swift
│   ├── Game/
│   │   ├── Ball.swift
│   │   └── GameEngine.swift
│   └── Views/
│       ├── ContentView.swift
│       ├── HomeView.swift
│       ├── CalibrationView.swift
│       └── GameView.swift
└── README.md
```

## Build (recommended path: XcodeGen)

XcodeGen produces a fresh `.xcodeproj` from `project.yml`, so the project
file does not have to be committed.

```bash
brew install xcodegen          # one-time
cd EyeTrackCollisionGame
xcodegen generate
open EyeTrackCollisionGame.xcodeproj
```

In Xcode:
1. Select your development team in **Signing & Capabilities**.
2. Plug in a TrueDepth device.
3. Run.

## Build (manual path)

If you'd rather not use XcodeGen:

1. In Xcode, **File ▸ New ▸ Project ▸ App** (iOS, SwiftUI).
2. Replace the generated source files with the ones in `EyeTrackCollisionGame/`
   (drag `Game/`, `Services/`, `Views/`, `EyeTrackCollisionGameApp.swift`).
3. Replace the project's `Info.plist` with the one in
   `EyeTrackCollisionGame/Resources/Info.plist`.
4. **File ▸ Add Package Dependencies… ▸ Add Local…** and pick the sibling
   `EyeTrackKit/` folder.
5. Make sure the deployment target is iOS 16 and the device family is iPhone+iPad.

## How the game works

```
HomeView ─► CalibrationView (9-point calibration, saves JSON to Documents/)
        ─► GameView         (the actual collision game)
```

- `EyeTrackingService` is a `@MainActor` class that owns the
  `EyeTrackController`. It auto-detects the device type, requests camera
  authorization, and loads any previously saved calibration profile from
  disk on launch.

- `CalibrationView` runs `Calibrator` against a `.nineGrid` layout. Once
  every target has been sampled, the fitted profile is applied to the
  controller and saved as `current.json` in the app's Documents directory.
  The reported mean residual gives you a quality readout (lower = better).

- `GameView` subscribes to `controller.gazeEvents.publisher` to feed the
  gaze position into `GameEngine`. The engine runs a `CADisplayLink`-driven
  60 Hz loop: balls move, bounce off the screen edges, and explode when the
  gaze cursor overlaps them. Score and remaining time are shown in the HUD.

- The `EyeTrackView` from EyeTrackKit is added with `.frame(1×1).opacity(0)`
  in both calibration and game screens — the AR session must run for face
  tracking to produce gaze events, but the SceneKit canvas itself is
  invisible.

## Tunables

`GameEngine.Tuning` exposes everything game-related:

```swift
struct Tuning {
    var ballCount: Int = 12
    var minRadius: CGFloat = 28
    var maxRadius: CGFloat = 44
    var minSpeed: CGFloat = 90    // pt/s
    var maxSpeed: CGFloat = 220
    var gazeRadius: CGFloat = 22
    var roundDuration: TimeInterval? = 60   // nil = endless
    // ...
}
```

EyeTrackKit-side tuning lives in `EyeTrackingService.init()` via
`EyeTrackKit.Configuration.default` (smoothing, blink threshold, Kalman
noise, fixation dispersion).

## Differences from the WebGazer collision demo

- Native iOS / SwiftUI rendering instead of HTML5 canvas
- TrueDepth-based gaze (sub-degree accuracy after calibration) instead of
  webcam regression
- 60-second rounds with score-based end screen (the WebGazer demo is endless)
- Proper user calibration with a saveable JSON profile

## Licence

The sample app code is released under the MIT licence (see EyeTrackKit's
LICENSE file). The WebGazer.js project is © Brown University and is not
bundled or copied here.
