# Camera Pinch Zoom Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two-finger pinch on the in-app camera preview zooms through the phone's physical lenses (ultra-wide → wide → telephoto), capped at the longest lens, with a small factor label.

**Architecture:** A pure `CameraZoomRange` struct in `Sources/Core/Camera/` holds all zoom math (clamping, pinch scaling, display factor, label). `CameraSession` opens the device's virtual multi-camera instead of the bare wide-angle camera, builds the range from the device after configuration, hands it to the view through one main-queue callback, and exposes `setZoom(_:)`. `CameraCaptureView` adds a `MagnifyGesture` and a label overlay on the existing preview — no layout branch, so the preview keeps its single identity.

**Tech Stack:** SwiftUI (`MagnifyGesture`, iOS 17), AVFoundation (`videoZoomFactor`, virtual devices), Swift Testing, XCUITest.

**Spec:** `docs/superpowers/specs/2026-10-15-camera-zoom-design.md`

## Global Constraints

- Swift only; no Objective-C.
- Deployment target iOS 17.0 — do not use `displayVideoZoomFactorMultiplier` (iOS 18+).
- The Xcode project is generated: edit `project.yml` / add files, then run `xcodegen generate`. New files under `Sources/` or `Tests/` require a regenerate before they compile.
- Unit tests use Swift Testing (`import Testing`, `@Test`/`#expect`/`#require`).
- `Sources/Core/` stays free of SwiftUI/UIKit/AVFoundation imports (`CoreGraphics` + `Foundation` only).
- Build/test destination: `platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0`.
- Work on GitButler branch `feature/camera-zoom` (already created; spec committed there). Commit with `but diff` → `but commit -b feature/camera-zoom -m "…" <ids>`; never plain `git commit`. The untracked `AGENTS.md` is not ours — never commit or touch it.
- `CameraCaptureView` must keep switching its arrangement with `AnyLayout`; the preview `CameraPreview` must stay one instance (gesture and label are modifiers on it, not a layout branch).
- Setting `videoZoomFactor` outside `[minAvailableVideoZoomFactor, maxAvailableVideoZoomFactor]` raises an Objective-C exception — the session must clamp to the device's own bounds before every set.
- Label uses the multiplication sign `×` (U+00D7), not the letter x.

Full unit-test command (used by several steps):

```sh
xcodebuild -project PictureFramer.xcodeproj -scheme PictureFramer \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  test -only-testing:PictureFramerTests/CameraZoomRangeTests 2>&1 | tail -30
```

## Review Focus

1. **Single-lens device / simulator**: pinch must be a no-op and the label hidden — covered by `singleLensIsNotZoomable` (Task 1) and the UI-test pinch (Task 3).
2. **Zero / negative / NaN magnification** from the gesture must not move the zoom or produce NaN for `videoZoomFactor` — `degenerateMagnificationKeepsStart` (Task 1).
3. **Device limits below the last switch-over factor** (e.g. a format that restricts `maxAvailableVideoZoomFactor`) must cap the range — `maxAvailableBelowLongestLensWins` (Task 1) plus the device-bound clamp in `apply(zoomFactor:to:)` (Task 2).
4. **Degenerate device numbers** (0 / non-finite minimum) must yield a sane unit range rather than divide-by-zero or NaN — `degenerateInputsFallBackToUnitRange` (Task 1).
5. **Dual camera without ultra-wide** (wide + telephoto): factor 1.0 is already the wide lens, label must read `1×` not `0.5×` — `dualWithoutUltraWideKeepsFactorOneAsWide` (Task 1).

---

### Task 1: `CameraZoomRange` pure zoom math

**Files:**
- Create: `Sources/Core/Camera/CameraZoomRange.swift`
- Create: `Tests/CameraZoomRangeTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (Tasks 2 and 3 rely on these exact names):
  - `struct CameraZoomRange: Equatable, Sendable`
  - `init(minimum: CGFloat, maxAvailable: CGFloat, switchOverFactors: [CGFloat], hasUltraWide: Bool)`
  - `let minimum: CGFloat`, `let maximum: CGFloat`, `let displayMultiplier: CGFloat`
  - `var isZoomable: Bool`, `var defaultFactor: CGFloat`
  - `func clamped(_ factor: CGFloat) -> CGFloat`
  - `func pinched(from start: CGFloat, by magnification: CGFloat) -> CGFloat`
  - `func displayFactor(for factor: CGFloat) -> CGFloat`
  - `func displayLabel(for factor: CGFloat) -> String`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CameraZoomRangeTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import PictureFramer

@Suite struct CameraZoomRangeTests {
    /// iPhone Pro triple camera: ultra-wide at 1, wide at 2, telephoto at 6.
    static let triple = CameraZoomRange(
        minimum: 1, maxAvailable: 123, switchOverFactors: [2, 6], hasUltraWide: true)
    /// Ultra-wide + wide only.
    static let dualWide = CameraZoomRange(
        minimum: 1, maxAvailable: 60, switchOverFactors: [2], hasUltraWide: true)
    /// Wide + telephoto, no ultra-wide: factor 1 is already the wide lens.
    static let dual = CameraZoomRange(
        minimum: 1, maxAvailable: 60, switchOverFactors: [2], hasUltraWide: false)
    /// Single wide lens.
    static let single = CameraZoomRange(
        minimum: 1, maxAvailable: 16, switchOverFactors: [], hasUltraWide: false)

    @Test func tripleCameraDefaultsToWideLensAndCapsAtTelephoto() {
        let range = Self.triple
        #expect(range.minimum == 1)
        #expect(range.maximum == 6)
        #expect(range.defaultFactor == 2)
        #expect(range.isZoomable)
    }

    @Test func tripleCameraDisplayFactors() {
        let range = Self.triple
        #expect(range.displayMultiplier == 0.5)
        #expect(range.displayFactor(for: 1) == 0.5)
        #expect(range.displayFactor(for: 2) == 1)
        #expect(range.displayFactor(for: 6) == 3)
    }

    @Test func dualWideCapsAtWideLens() {
        let range = Self.dualWide
        #expect(range.maximum == 2)
        #expect(range.defaultFactor == 2)
        #expect(range.isZoomable)
        #expect(range.displayLabel(for: 2) == "1×")
    }

    @Test func dualWithoutUltraWideKeepsFactorOneAsWide() {
        let range = Self.dual
        #expect(range.displayMultiplier == 1)
        #expect(range.defaultFactor == 1)
        #expect(range.maximum == 2)
        #expect(range.displayLabel(for: 1) == "1×")
        #expect(range.displayLabel(for: 2) == "2×")
    }

    @Test func singleLensIsNotZoomable() {
        let range = Self.single
        #expect(!range.isZoomable)
        #expect(range.maximum == range.minimum)
        #expect(range.defaultFactor == 1)
        #expect(range.pinched(from: 1, by: 3) == 1)
        #expect(range.pinched(from: 1, by: 0.2) == 1)
    }

    @Test func maxAvailableBelowLongestLensWins() {
        let range = CameraZoomRange(
            minimum: 1, maxAvailable: 4, switchOverFactors: [2, 6], hasUltraWide: true)
        #expect(range.maximum == 4)
        #expect(range.pinched(from: 2, by: 10) == 4)
    }

    @Test func pinchScalesAndClampsBothEnds() {
        let range = Self.triple
        #expect(range.pinched(from: 2, by: 1.5) == 3)
        #expect(range.pinched(from: 2, by: 10) == 6)
        #expect(range.pinched(from: 2, by: 0.1) == 1)
    }

    @Test func degenerateMagnificationKeepsStart() {
        let range = Self.triple
        #expect(range.pinched(from: 3, by: 0) == 3)
        #expect(range.pinched(from: 3, by: -1) == 3)
        #expect(range.pinched(from: 3, by: .nan) == 3)
        #expect(range.pinched(from: 3, by: .infinity) == 3)
    }

    @Test func clampedHandlesOutOfRangeAndNonFinite() {
        let range = Self.triple
        #expect(range.clamped(0) == 1)
        #expect(range.clamped(100) == 6)
        #expect(range.clamped(.nan) == 1)
        #expect(range.clamped(.infinity) == 1)
    }

    @Test func labelsRoundToOneDecimalAndDropTrailingZero() {
        let range = Self.triple
        #expect(range.displayLabel(for: 1) == "0.5×")
        #expect(range.displayLabel(for: 2) == "1×")
        #expect(range.displayLabel(for: 5) == "2.5×")
        #expect(range.displayLabel(for: 2.4) == "1.2×")
        #expect(range.displayLabel(for: 5.92) == "3×")   // 2.96 rounds to 3.0
    }

    @Test func degenerateInputsFallBackToUnitRange() {
        let zero = CameraZoomRange(
            minimum: 0, maxAvailable: 0, switchOverFactors: [], hasUltraWide: false)
        #expect(zero.minimum == 1)
        #expect(zero.maximum == 1)
        #expect(!zero.isZoomable)
        #expect(zero.displayLabel(for: zero.defaultFactor) == "1×")

        let nan = CameraZoomRange(
            minimum: .nan, maxAvailable: .nan, switchOverFactors: [0], hasUltraWide: true)
        #expect(nan.minimum == 1)
        #expect(nan.maximum == 1)
        #expect(nan.displayMultiplier == 1)
    }
}
```

- [ ] **Step 2: Regenerate the project and run the tests to verify they fail**

Run: `xcodegen generate` then the full unit-test command from Global Constraints.
Expected: build FAILS with `cannot find 'CameraZoomRange' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Core/Camera/CameraZoomRange.swift`:

```swift
import CoreGraphics
import Foundation

/// Pure zoom math for the in-app camera. All factors are AVFoundation
/// `videoZoomFactor` values of the (virtual) capture device; this type never
/// touches AVFoundation so it stays unit-testable in Core.
///
/// On a virtual device that includes the ultra-wide lens, factor 1.0 is the
/// ultra-wide lens and the wide lens sits at the first switch-over factor —
/// the one the Camera app labels "1×". `displayMultiplier` converts between
/// the device's factor and that user-facing factor.
struct CameraZoomRange: Equatable, Sendable {
    /// Smallest allowed `videoZoomFactor` (the widest lens).
    let minimum: CGFloat
    /// Largest allowed `videoZoomFactor`: the longest lens's native factor,
    /// or the device limit if that is lower. No digital zoom past it.
    let maximum: CGFloat
    /// Multiply a device factor by this to get the user-facing factor.
    let displayMultiplier: CGFloat

    /// - Parameters:
    ///   - minimum: `minAvailableVideoZoomFactor`.
    ///   - maxAvailable: `maxAvailableVideoZoomFactor`.
    ///   - switchOverFactors: `virtualDeviceSwitchOverVideoZoomFactors`,
    ///     ascending; empty on a single-lens device.
    ///   - hasUltraWide: whether the constituent devices include the
    ///     ultra-wide lens (then factor 1.0 is ultra-wide, not wide).
    init(minimum: CGFloat, maxAvailable: CGFloat, switchOverFactors: [CGFloat], hasUltraWide: Bool) {
        let lower = minimum.isFinite && minimum > 0 ? minimum : 1
        let longestLens = switchOverFactors.last ?? 1
        let upper = maxAvailable.isFinite ? min(maxAvailable, longestLens) : longestLens
        self.minimum = lower
        self.maximum = max(lower, upper)
        let wide = hasUltraWide ? (switchOverFactors.first ?? 1) : 1
        self.displayMultiplier = wide.isFinite && wide > 0 ? 1 / wide : 1
    }

    /// False on a single-lens device: pinching does nothing and the UI
    /// hides the factor label.
    var isZoomable: Bool { maximum > minimum }

    /// The wide lens — what the Camera app shows as "1×".
    var defaultFactor: CGFloat { clamped(1 / displayMultiplier) }

    func clamped(_ factor: CGFloat) -> CGFloat {
        guard factor.isFinite else { return minimum }
        return min(max(factor, minimum), maximum)
    }

    /// Zoom after a pinch that began at `start`; degenerate magnifications
    /// (zero, negative, non-finite) leave the zoom where it started.
    func pinched(from start: CGFloat, by magnification: CGFloat) -> CGFloat {
        guard magnification.isFinite, magnification > 0 else { return clamped(start) }
        return clamped(start * magnification)
    }

    func displayFactor(for factor: CGFloat) -> CGFloat {
        factor * displayMultiplier
    }

    /// "0.5×", "1×", "2.5×" — one decimal, trailing ".0" dropped.
    func displayLabel(for factor: CGFloat) -> String {
        let rounded = (displayFactor(for: factor) * 10).rounded() / 10
        let text = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", Double(rounded))
        return text + "×"
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: the full unit-test command from Global Constraints.
Expected: `Test Suite 'CameraZoomRangeTests' passed`, 11 tests, 0 failures.

- [ ] **Step 5: Commit**

```sh
but diff            # note the ids of the two new files (not AGENTS.md)
but commit -b feature/camera-zoom -m "feat(core): CameraZoomRange pure zoom math

Clamps, pinch-scales and labels camera zoom factors; derives the wide-lens
display multiplier from the virtual device's switch-over factors so it
works on iOS 17 without displayVideoZoomFactorMultiplier.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>" <id1> <id2>
```

---

### Task 2: `CameraSession` — virtual device, zoom range, `setZoom`

**Files:**
- Modify: `Sources/UI/Camera/CameraSession.swift` (device lookup in `configure()`, new zoom members)

**Interfaces:**
- Consumes: `CameraZoomRange` from Task 1.
- Produces (Task 3 relies on these exact names):
  - `var onZoomRangeReady: ((CameraZoomRange) -> Void)?` — called once on the main queue after the session configures; never called in the simulator.
  - `func setZoom(_ factor: CGFloat)` — asynchronous, clamps, safe to call before configuration (no-op).

- [ ] **Step 1: Add the back-camera lookup**

In `CameraSession`, replace the `configure()` guard's device lookup and add a static helper. Replace

```swift
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
```

with

```swift
        guard let device = Self.backCamera,
              let input = try? AVCaptureDeviceInput(device: device) else { return }
```

and add, directly above `private func configure()`:

```swift
    /// The most capable back camera: a virtual multi-camera device where
    /// available, so `videoZoomFactor` switches physical lenses (ultra-wide
    /// → wide → telephoto); the bare wide-angle camera otherwise.
    private static var backCamera: AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera,
        ]
        for type in types {
            if let device = AVCaptureDevice.default(type, for: .video, position: .back) { return device }
        }
        return nil
    }
```

Leave `isAvailable` unchanged (it checks the wide-angle camera, which every back camera includes).

- [ ] **Step 2: Add zoom state, the range callback and `setZoom`**

Add these stored properties next to `private var isConfigured = false`:

```swift
    private var zoomRange: CameraZoomRange?

    /// Delivered once on the main queue after the session configures, so the
    /// view can show the zoom label and bound the pinch gesture. Set it before
    /// `start()`. Never called when no camera configures (simulator).
    var onZoomRangeReady: ((CameraZoomRange) -> Void)?
```

In `configure()`, after `isConfigured = true` and before `makeRotationCoordinatorIfReady()`, insert:

```swift
        let range = CameraZoomRange(
            minimum: device.minAvailableVideoZoomFactor,
            maxAvailable: device.maxAvailableVideoZoomFactor,
            switchOverFactors: device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat($0.doubleValue) },
            hasUltraWide: device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera })
        zoomRange = range
        apply(zoomFactor: range.defaultFactor, to: device)
        let onZoomRangeReady = onZoomRangeReady
        DispatchQueue.main.async { onZoomRangeReady?(range) }
```

Add a new section after the `// MARK: Lifecycle` section (before `// MARK: Capture`):

```swift
    // MARK: Zoom

    /// Sets the device zoom (preview and capture alike). Clamped to the
    /// app's range and then to the device's own limits; no-op before the
    /// session has configured.
    func setZoom(_ factor: CGFloat) {
        sessionQueue.async { [self] in
            guard let device, let zoomRange else { return }
            apply(zoomFactor: zoomRange.clamped(factor), to: device)
        }
    }

    /// AVFoundation raises on a factor outside the device's available range,
    /// so clamp to the device's own bounds here regardless of the caller.
    private func apply(zoomFactor: CGFloat, to device: AVCaptureDevice) {
        let factor = min(max(zoomFactor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.videoZoomFactor = factor
        device.unlockForConfiguration()
    }
```

Also update the type's doc comment: after "in landscape as well." add "The session opens the virtual multi-camera device where available so that `videoZoomFactor` switches physical lenses; see `CameraZoomRange`."

- [ ] **Step 3: Build**

Run:

```sh
xcodebuild -project PictureFramer.xcodeproj -scheme PictureFramer \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```sh
but diff
but commit -b feature/camera-zoom -m "feat(camera): open virtual multi-camera and expose setZoom

Picks triple/dual-wide/dual/wide in that order so videoZoomFactor switches
lenses, derives the CameraZoomRange after configuration, starts on the
wide lens, and clamps every zoom set to the device's own limits.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>" <id>
```

---

### Task 3: Pinch gesture and zoom label in `CameraCaptureView` + UI test

**Files:**
- Modify: `Sources/UI/Camera/CameraCaptureView.swift` (state, `onAppear`, `preview`, new `zoomGesture` / `zoomLabel`)
- Modify: `UITests/PictureFramerUITests.swift` — `testCameraViewSurvivesRotation`

**Interfaces:**
- Consumes: `CameraZoomRange` (Task 1); `CameraSession.onZoomRangeReady`, `CameraSession.setZoom(_:)` (Task 2).
- Produces: a `Text` with accessibility identifier `Zoom factor`, present only when the range is zoomable.

- [ ] **Step 1: Extend the UI test**

In `testCameraViewSurvivesRotation`, directly after the line

```swift
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5), "camera view did not open")
```

insert:

```swift
        // No camera hardware → no zoom range: a pinch must be a harmless
        // no-op and the factor label must stay hidden.
        app.pinch(withScale: 2, velocity: 1)
        XCTAssertTrue(shutter.isHittable, "shutter unreachable after pinching the preview")
        XCTAssertFalse(app.staticTexts["Zoom factor"].exists, "zoom label must be hidden without a zoom range")
```

- [ ] **Step 2: Add zoom state and the callback**

In `CameraCaptureView`, next to `@State private var isCapturing = false` add:

```swift
    @State private var zoomRange: CameraZoomRange?
    @State private var zoomFactor: CGFloat = 1
    @State private var zoomAtGestureStart: CGFloat?
```

Replace `.onAppear { camera.start() }` with:

```swift
        .onAppear {
            camera.onZoomRangeReady = { range in
                zoomRange = range
                zoomFactor = range.defaultFactor
            }
            camera.start()
        }
```

- [ ] **Step 3: Attach the gesture and label to the preview**

Replace the `preview` property with:

```swift
    private var preview: some View {
        CameraPreview(session: camera)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Camera preview")
            .gesture(zoomGesture)
            .overlay(alignment: .bottom) { zoomLabel }
    }

    /// Pinch to zoom. The first change of a gesture records the starting
    /// zoom; every update scales from that start so the pinch feels
    /// absolute. Without a range (single lens, simulator) it does nothing.
    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard let range = zoomRange else { return }
                let start = zoomAtGestureStart ?? zoomFactor
                zoomAtGestureStart = start
                zoomFactor = range.pinched(from: start, by: value.magnification)
                camera.setZoom(zoomFactor)
            }
            .onEnded { _ in zoomAtGestureStart = nil }
    }

    @ViewBuilder
    private var zoomLabel: some View {
        if let range = zoomRange, range.isZoomable {
            Text(range.displayLabel(for: zoomFactor))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.5), in: Capsule())
                .padding(.bottom, 12)
                .accessibilityIdentifier("Zoom factor")
        }
    }
```

Update the type's doc comment: append a paragraph "Pinching the preview zooms through the device's lenses (`CameraZoomRange`); the gesture and the factor label are modifiers on the one `CameraPreview`, never a layout branch."

- [ ] **Step 4: Build and run the camera UI test**

Run:

```sh
xcodebuild -project PictureFramer.xcodeproj -scheme PictureFramer \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  test -only-testing:PictureFramerUITests/PictureFramerUITests/testCameraViewSurvivesRotation 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`; the test passes including the pinch assertions.

- [ ] **Step 5: Commit**

```sh
but diff
but commit -b feature/camera-zoom -m "feat(camera): pinch to zoom with factor label

MagnifyGesture on the preview scales from the gesture's starting zoom via
CameraZoomRange and pushes it to the session; a capsule label shows the
user-facing factor and is hidden on single-lens devices. UI test pinches
without hardware to guard the no-op path.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>" <id1> <id2>
```

---

### Task 4: Docs

**Files:**
- Modify: `README.md` (the "In-app camera" feature bullet, line ~10)
- Modify: `CLAUDE.md` (the `**Camera**` paragraph under Architecture)

- [ ] **Step 1: README**

In the `**In-app camera**` bullet, after "handy for wide paintings —" keep the sentence and append before the closing parenthesis sentence: " Pinch the preview to zoom through the phone's lenses, from ultra-wide to telephoto." Final bullet:

```markdown
- **In-app camera** ("Take Photo"): shoot the painting directly instead of importing — in landscape too, handy for wide paintings — the capture feeds the same detection pipeline and is never saved to the library; only the straightened export is. Pinch the preview to zoom through the phone's lenses, from ultra-wide to telephoto. (The button appears only on devices with a camera.)
```

- [ ] **Step 2: CLAUDE.md**

In the `**Camera**` paragraph, after "output is JPEG data into `EditorViewModel.loadCapturedPhoto`." insert:

```
Zoom: the session opens the virtual multi-camera (`builtInTripleCamera` → dual-wide → dual → wide) so `videoZoomFactor` switches physical lenses; pinch on the preview goes through the pure, tested `Core/Camera/CameraZoomRange.swift` (clamp to the longest lens — no digital zoom past it — and the wide-lens display multiplier derived from the switch-over factors because `displayVideoZoomFactorMultiplier` is iOS 18+). The session clamps every set to the device's own limits because AVFoundation raises on out-of-range factors. Lens switching is hardware-only (TestFlight); the UI test only pinches the no-range path.
```

- [ ] **Step 3: Commit**

```sh
but diff
but commit -b feature/camera-zoom -m "docs: describe camera pinch zoom

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>" <id1> <id2>
```

---

### Task 5: Full verification

- [ ] **Step 1: Run the whole unit suite**

```sh
xcodebuild -project PictureFramer.xcodeproj -scheme PictureFramer \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  test -only-testing:PictureFramerTests 2>&1 | grep -E "Test Suite|passed|failed|error:" | tail -20
```

Expected: all suites pass, 0 failures.

- [ ] **Step 2: Confirm Core has no new framework imports**

```sh
grep -rn "import" Sources/Core/Camera/
```

Expected: only `CoreGraphics` and `Foundation`.

- [ ] **Step 3: Confirm branch state**

`but status` shows four commits on `feature/camera-zoom` above the spec commit and `AGENTS.md` still uncommitted.
