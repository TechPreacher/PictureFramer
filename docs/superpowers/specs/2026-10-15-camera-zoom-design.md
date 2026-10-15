# Camera Pinch Zoom — Design

**Date:** 2026-10-15
**Status:** Approved

## Summary

Two-finger pinch on the in-app camera preview zooms the viewfinder using the
phone's physical lenses. The session opens the device's virtual multi-camera
(triple / dual-wide / dual) instead of the bare wide-angle camera, so changing
`videoZoomFactor` makes AVFoundation switch between the ultra-wide, wide and
telephoto lenses. Zoom is continuous (Apple Camera style) and capped at the
longest lens's native factor — no digital zoom past the last lens. A small
"1×"-style label over the preview shows the current factor.

## Goals

- Pinch to zoom out to the ultra-wide lens and in to the telephoto lens,
  where the hardware has them; the capture uses the same zoom as the preview.
- Keep every bit of zoom math pure and unit-tested in `Sources/Core/`.
- Preserve the capture view's `AnyLayout` single-identity invariant for the
  preview (`testCameraViewSurvivesRotation`).
- Devices with one back lens (and the simulator) are unchanged: the gesture
  is a no-op and the label is hidden.

## Non-Goals

- Digital zoom beyond the longest lens.
- Lens buttons (0.5× / 1× / 2×), snapping, or zoom ramps/animation.
- Persisting the zoom factor between camera sessions.
- Front camera, flash, focus/exposure controls.

## Design

### 1. Pure zoom math — `Sources/Core/Camera/CameraZoomRange.swift`

`Sources/Core/` stays UI- and AVFoundation-free; the struct speaks only in
`videoZoomFactor` numbers that the session extracts from the device.

```swift
struct CameraZoomRange: Equatable, Sendable {
    let minimum: CGFloat            // device.minAvailableVideoZoomFactor
    let maximum: CGFloat            // see init
    let displayMultiplier: CGFloat  // display factor = videoZoomFactor × this

    /// - switchOverFactors: `virtualDeviceSwitchOverVideoZoomFactors`,
    ///   ascending (empty on a single-lens device).
    /// - hasUltraWide: whether the constituent devices include the
    ///   ultra-wide lens — on those devices factor 1.0 is the ultra-wide
    ///   lens and the wide lens sits at `switchOverFactors.first`, which
    ///   the Camera app shows as "1×".
    init(minimum: CGFloat, maxAvailable: CGFloat,
         switchOverFactors: [CGFloat], hasUltraWide: Bool)

    var isZoomable: Bool                     // maximum > minimum
    var defaultFactor: CGFloat               // wide lens ("1×"), clamped
    func clamped(_ factor: CGFloat) -> CGFloat
    func pinched(from start: CGFloat, by magnification: CGFloat) -> CGFloat
    func displayFactor(for factor: CGFloat) -> CGFloat
    func displayLabel(for factor: CGFloat) -> String   // "0.5×", "1×", "2.5×"
}
```

Rules:

- `maximum = min(maxAvailable, switchOverFactors.last ?? 1)`, never below
  `minimum`. On a triple camera that is the telephoto factor; on a dual-wide
  (ultra-wide + wide) it is the wide factor; on a single lens it equals the
  minimum, so `isZoomable` is false.
- `displayMultiplier = hasUltraWide ? 1 / (switchOverFactors.first ?? 1) : 1`.
- `defaultFactor = clamped(1 / displayMultiplier)` — the wide lens.
- `pinched` = `clamped(start × magnification)`; non-finite or non-positive
  magnification returns `clamped(start)`.
- `displayLabel` rounds to one decimal and drops a trailing `.0`
  (`0.5×`, `1×`, `2.5×`, `3×`); uses the `×` multiplication sign.

### 2. `CameraSession` (`Sources/UI/Camera/CameraSession.swift`)

- Device selection: first available of `.builtInTripleCamera`,
  `.builtInDualWideCamera`, `.builtInDualCamera`, then
  `.builtInWideAngleCamera`. `isAvailable` keeps checking the wide-angle
  camera (every multi-camera device has one).
- After `configure()` succeeds, build the `CameraZoomRange` from the device
  (`minAvailableVideoZoomFactor`, `maxAvailableVideoZoomFactor`,
  `virtualDeviceSwitchOverVideoZoomFactors`, and whether
  `constituentDevices` contains `.builtInUltraWideCamera`), set
  `videoZoomFactor = range.defaultFactor` under `lockForConfiguration`, and
  deliver the range to the UI on the main queue via `onZoomRangeReady`.
  The virtual device's default zoom factor is not relied on.
- `func setZoom(_ factor: CGFloat)`: on the session queue, clamp to the
  device's `[minAvailableVideoZoomFactor, maxAvailableVideoZoomFactor]`
  (AVFoundation raises on out-of-range values), lock, set
  `videoZoomFactor`, unlock. Direct set, no ramp.
- `videoZoomFactor` applies to the photo output as well as the preview, so
  `capture` needs no change.

### 3. `CameraCaptureView` (`Sources/UI/Camera/CameraCaptureView.swift`)

- State: `zoomRange: CameraZoomRange?`, `zoomFactor: CGFloat`,
  `zoomAtGestureStart: CGFloat?`.
- `onAppear` sets `camera.onZoomRangeReady` (stores range, resets
  `zoomFactor` to `defaultFactor`) before `camera.start()`.
- `MagnifyGesture` on the preview: the first `onChanged` captures
  `zoomAtGestureStart`; each update computes
  `range.pinched(from: start, by: value.magnification)`, stores it and calls
  `camera.setZoom`. `onEnded` clears the start value. With no range (single
  lens, simulator) the gesture does nothing.
- Label: `Text(range.displayLabel(for: zoomFactor))` in a capsule, bottom
  centre of the preview, shown only when `range.isZoomable`. Accessibility
  identifier `Zoom factor`.
- The preview stays the same `CameraPreview` instance; the gesture and label
  are modifiers/overlays on it, not a layout branch.

### 4. Testing

- Unit (Swift Testing, `Tests/CameraZoomRangeTests.swift`): triple-camera
  fixture (min 1, switch-over `[2, 6]`, ultra-wide) → default 2, maximum 6,
  display `0.5×`/`1×`/`3×`; dual-wide → maximum = wide factor; dual
  (wide + tele, no ultra-wide) → multiplier 1, default 1; single lens →
  not zoomable, pinch is identity; `maxAvailable` below the last
  switch-over wins; pinch clamps at both ends; zero/NaN/negative
  magnification; label formatting (`1×`, `0.5×`, `2.5×`, rounding `2.96` →
  `3×`).
- UI (`UITests`, inside `testCameraViewSurvivesRotation` which already opens
  the camera with `-ShowCameraWithoutHardware`): pinch on the app, assert the
  shutter remains hittable and no zoom label appears (no hardware → no
  range).
- Lens switching and the capture's zoom are verified on hardware via
  TestFlight; the simulator has no camera.

### 5. Chores

- Branch `feature/camera-zoom`, PR to `main`.
- README feature bullet and CLAUDE.md camera paragraph mention pinch zoom.
- `xcodegen generate` for the new source and test files.
- Version bump deferred to TestFlight time.

## Decisions

- **Continuous, capped at the longest lens** rather than snapping to lens
  factors: matches the Camera app's feel; between lenses AVFoundation crops
  the nearer lens, which is what the user asked for in practice. Digital
  zoom past the telephoto would only lower the resolution handed to
  rectangle detection.
- **Display multiplier derived from constituent lenses** instead of
  `displayVideoZoomFactorMultiplier`: that API is iOS 18+, the app targets
  iOS 17, and the derivation keeps the logic in a testable pure struct.
- **Callback, not observation, for the range**: `CameraSession` is an
  `NSObject` delegate owned by the view; one main-queue callback after
  configuration is the smallest change that keeps all zoom state in the
  view.
