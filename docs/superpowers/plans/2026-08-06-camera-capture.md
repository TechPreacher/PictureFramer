# In-App Camera Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Take Photo" button that shoots a picture with the system camera UI and feeds it into the existing detection/correction pipeline.

**Architecture:** Extract a `load(data:)` funnel from `EditorViewModel.load(item:)` so both the photo picker and the camera share one tested load path. A logic-free `UIViewControllerRepresentable` wraps `UIImagePickerController` (`.camera`) and converts the capture to JPEG `Data`. `ContentView` gains the button, a `fullScreenCover`, and a camera-denied Settings link. Zero changes to `Sources/Core/`.

**Tech Stack:** SwiftUI, UIKit (`UIImagePickerController`), AVFoundation (permission status only), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-08-06-camera-capture-design.md`

## Global Constraints

- Swift only; no Objective-C.
- The Xcode project is generated: edit `project.yml`, then run `xcodegen generate`. New files under `Sources/` require a regenerate before they compile.
- Unit tests use Swift Testing (`import Testing`, `@Test`/`#expect`/`#require`).
- `Sources/Core/` stays UI-free and untouched by this feature.
- Build/test destination: `platform=iOS Simulator,name=iPhone 17 Pro`.
- Work on branch `feature/camera-capture` (already created; spec is committed there).
- Camera wrapper must contain no logic beyond UIImage→Data conversion — everything testable lives in `EditorViewModel`.
- The original capture is never written to the photo library; the only library write remains the normal export.

Full test command (used by several steps):

```sh
xcodebuild -project PictureFramer.xcodeproj -scheme PictureFramer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

---

### Task 1: Extract `load(data:)` funnel in EditorViewModel

**Files:**
- Modify: `Sources/UI/EditorViewModel.swift:156-180` (the `// MARK: Loading` section)
- Test: `Tests/EditorViewModelTests.swift`

**Interfaces:**
- Consumes: existing `EditorViewModel.normalizedCGImage(from:)`, `runDetection()`, `downscaled(_:maxDimension:)`.
- Produces: `func load(data: Data) async` (internal, `@MainActor` via class) — decodes, downscales, detects; on undecodable data sets `errorMessage = "Couldn't load that photo."` and `stage = .picking`. Also `func loadCapturedPhoto(_ data: Data)` — non-async wrapper that cancels `loadTask` and spawns `Task { await load(data:) }`; this is what the UI calls. Task 3 relies on both names exactly.

- [ ] **Step 1: Write two failing tests**

Append inside `struct EditorViewModelTests` in `Tests/EditorViewModelTests.swift`:

```swift
@Test @MainActor func loadDataReachesAdjustingWithDetectedQuad() async throws {
    let (defaults, cleanup) = makeDefaults()
    defer { cleanup() }
    let model = EditorViewModel(defaults: defaults)
    let size = CGSize(width: 1200, height: 900)
    let outer = FixtureImageFactory.axisAlignedQuad(in: size, inset: 150)
    let inner = try #require(outer.expanded(by: -120))
    let image = FixtureImageFactory.framedPaintingImage(
        size: size, outerQuad: outer, innerQuad: inner)
    let data = try PhotoLibraryExporter().encodeJPEG(image)

    await model.load(data: data)

    #expect(model.stage == .adjusting)
    let detected = try #require(model.quad)
    // Default framed mode: quad must land near the outer (frame) edge.
    let allowed = max(size.width, size.height) * 0.035
    for corner in detected.perimeterCorners {
        let nearest = outer.perimeterCorners
            .map { hypot(corner.x - $0.x, corner.y - $0.y) }
            .min()!
        #expect(nearest <= allowed)
    }
}

@Test @MainActor func loadGarbageDataShowsErrorAndReturnsToPicking() async {
    let (defaults, cleanup) = makeDefaults()
    defer { cleanup() }
    let model = EditorViewModel(defaults: defaults)

    await model.load(data: Data([0xDE, 0xAD, 0xBE, 0xEF]))

    #expect(model.stage == .picking)
    #expect(model.errorMessage == "Couldn't load that photo.")
    #expect(model.sourceImage == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```sh
xcodebuild -project PictureFramer.xcodeproj -scheme PictureFramer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:PictureFramerTests/EditorViewModelTests
```

Expected: BUILD FAILS — `value of type 'EditorViewModel' has no member 'load'` (the existing `load(item:)` is `private`, and `load(data:)` doesn't exist yet). A compile failure is the expected "red" here.

- [ ] **Step 3: Refactor — extract `load(data:)`, add `loadCapturedPhoto(_:)`**

In `Sources/UI/EditorViewModel.swift`, replace the existing `private func load(item: PhotosPickerItem) async` (lines 158–180) with:

```swift
private func load(item: PhotosPickerItem) async {
    stage = .loading
    errorMessage = nil
    do {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            errorMessage = "Couldn't load that photo."
            stage = .picking
            return
        }
        await load(data: data)
    } catch {
        guard !Task.isCancelled else { return }
        errorMessage = "Couldn't load that photo."
        stage = .picking
    }
}

/// Shared load funnel for both photo-picker and camera captures. Decodes
/// with EXIF orientation baked in, prepares the preview base, and runs
/// detection. Internal (not private) so tests can drive it directly.
func load(data: Data) async {
    stage = .loading
    errorMessage = nil
    guard let image = Self.normalizedCGImage(from: data) else {
        errorMessage = "Couldn't load that photo."
        stage = .picking
        return
    }
    sourceImage = image
    let base = await Task.detached(priority: .userInitiated) {
        downscaled(image, maxDimension: 1600)
    }.value
    previewBase = base
    previewScale = CGFloat(base.width) / CGFloat(image.width)
    await runDetection()
}

/// Entry point for the in-app camera: hand over a fresh capture exactly
/// as if it had been picked from the library. The capture is never
/// written to the photo library.
func loadCapturedPhoto(_ data: Data) {
    loadTask?.cancel()
    loadTask = Task { await load(data: data) }
}
```

Note the behavior is identical to the old code for the picker path: same stage transitions, same error copy, same downscale. `load(data:)` contains no throwing calls, so it needs no `do/catch`.

- [ ] **Step 4: Run the two new tests to verify they pass**

Same command as Step 2. Expected: both new tests PASS, all pre-existing `EditorViewModelTests` still PASS.

- [ ] **Step 5: Run the full unit test suite**

Run the full test command from Global Constraints. Expected: all tests pass (UITests may be skipped/slow; unit suite must be green).

- [ ] **Step 6: Commit**

```sh
git add Sources/UI/EditorViewModel.swift Tests/EditorViewModelTests.swift
git commit -m "refactor: extract load(data:) funnel shared by picker and camera"
```

---

### Task 2: CameraPicker wrapper + camera Info.plist key

**Files:**
- Create: `Sources/UI/CameraPicker.swift`
- Modify: `project.yml` (Info properties block, after `NSPhotoLibraryAddUsageDescription`)

**Interfaces:**
- Consumes: nothing from Task 1 (pure UIKit glue).
- Produces: `struct CameraPicker: UIViewControllerRepresentable` with `init(onCapture: @escaping (Data) -> Void)`, plus `static var isAvailable: Bool` and `static var isAccessDenied: Bool`. Task 3 relies on all three exactly.

No unit tests: this file is logic-free UIKit glue per the spec; it cannot run in the simulator-hosted test bundle anyway (no camera).

- [ ] **Step 1: Create `Sources/UI/CameraPicker.swift`**

```swift
import AVFoundation
import SwiftUI
import UIKit

/// Logic-free glue around the system camera UI. All real work happens in
/// `EditorViewModel.load(data:)` — this only converts the capture to JPEG
/// data and hands it to the callback. The capture is never written to the
/// photo library.
struct CameraPicker: UIViewControllerRepresentable {
    /// Called with the JPEG data of the confirmed capture ("Use Photo").
    let onCapture: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    /// False in the simulator and on devices without a camera; the UI
    /// hides the Take Photo button entirely.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// True when camera access is denied or restricted — the caller shows
    /// an error with a Settings link instead of presenting the camera.
    static var isAccessDenied: Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted: return true
        default: return false
        }
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
        UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // 0.95 keeps the EXIF orientation tag and near-lossless pixels;
            // normalizedCGImage(from:) bakes the orientation in downstream.
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.95) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
```

- [ ] **Step 2: Add the camera usage description to `project.yml`**

In the `info.properties` block (directly after the `NSPhotoLibraryAddUsageDescription` entry, keeping the same `>-` folded style):

```yaml
        NSCameraUsageDescription: >-
          PictureFramer uses the camera to shoot pictures of framed paintings
          for straightening.
```

- [ ] **Step 3: Regenerate the project and build**

```sh
xcodegen generate
xcodebuild -project PictureFramer.xcodeproj -scheme PictureFramer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Expected: BUILD SUCCEEDED (new file picked up; nothing references it yet).

- [ ] **Step 4: Verify the Info.plist key landed**

```sh
grep -A2 NSCameraUsageDescription Sources/Info.plist
```

Expected: the key with the usage string. (xcodegen writes `Sources/Info.plist` from `project.yml` — never edit the plist directly.)

- [ ] **Step 5: Commit**

```sh
git add Sources/UI/CameraPicker.swift project.yml Sources/Info.plist PictureFramer.xcodeproj
git commit -m "feat: add CameraPicker wrapper and camera usage description"
```

(If `PictureFramer.xcodeproj` is gitignored, drop it from the add — check `git status` first.)

---

### Task 3: Take Photo button in ContentView

**Files:**
- Modify: `Sources/UI/ContentView.swift` (state vars at top of `ContentView`, `pickerScreen`, and the `NavigationStack` body for the cover)

**Interfaces:**
- Consumes: `CameraPicker(onCapture:)`, `CameraPicker.isAvailable`, `CameraPicker.isAccessDenied` (Task 2); `EditorViewModel.loadCapturedPhoto(_:)` (Task 1).
- Produces: user-facing button; nothing downstream depends on this task.

- [ ] **Step 1: Add state and the fullScreenCover**

In `Sources/UI/ContentView.swift`, add two state vars below `@State private var showSettings = false`:

```swift
@State private var showCamera = false
@State private var cameraDenied = false
```

On the `NavigationStack`'s content (directly after the existing `.sheet(isPresented: $showSettings, ...)` modifier), add:

```swift
.fullScreenCover(isPresented: $showCamera) {
    CameraPicker { data in
        model.loadCapturedPhoto(data)
    }
    .ignoresSafeArea()
}
```

(`fullScreenCover`, not `sheet` — sheet-presented camera pickers have long-standing layout glitches.)

- [ ] **Step 2: Add the Take Photo button and denied-state link to `pickerScreen`**

Directly after the existing `PhotosPicker { Label("Choose Photo", ...) }.buttonStyle(.borderedProminent)` block, add:

```swift
if CameraPicker.isAvailable {
    Button {
        if CameraPicker.isAccessDenied {
            cameraDenied = true
        } else {
            cameraDenied = false
            showCamera = true
        }
    } label: {
        Label("Take Photo", systemImage: "camera")
    }
    .buttonStyle(.bordered)
}
if cameraDenied, let settingsURL = URL(string: UIApplication.openSettingsURLString) {
    HStack {
        Text("Camera access is off.")
            .font(.footnote)
            .foregroundStyle(.red)
        Link("Open Settings", destination: settingsURL)
            .font(.footnote)
    }
}
```

This mirrors the export-denied pattern in `EditorView.swift:127-138`. `UIApplication` resolves via SwiftUI's UIKit re-export, same as in `EditorView.swift`.

- [ ] **Step 3: Build and run the full unit test suite**

Run the full test command from Global Constraints. Expected: build succeeds, all unit tests pass. In the simulator the button is absent (`isAvailable == false`), so existing UI behavior — including the XCUITest flow — is unchanged.

- [ ] **Step 4: Commit**

```sh
git add Sources/UI/ContentView.swift
git commit -m "feat: Take Photo button feeds camera captures into the pipeline"
```

---

### Task 4: Docs

**Files:**
- Modify: `README.md` (feature list / usage section)
- Modify: `CLAUDE.md` ("What This App Is" paragraph)

**Interfaces:** none.

- [ ] **Step 1: README**

In the feature/usage description, add one sentence alongside the photo-import description, e.g.:

> Photos can also be shot directly in the app with the system camera ("Take Photo"); the capture goes straight into detection and is never saved to the library — only the straightened export is.

Match the README's existing tone and placement (read it first; exact wording may be adapted to fit).

- [ ] **Step 2: CLAUDE.md**

In the "What This App Is" paragraph, extend the first sentence's import clause: after "imports photos of framed paintings/pictures from the photo library", add "or shoots them in-app with the system camera (capture feeds the same `load(data:)` funnel; original never saved)".

- [ ] **Step 3: Commit**

```sh
git add README.md CLAUDE.md
git commit -m "docs: describe in-app camera capture"
```

---

### Out of scope for this plan

- Version bump to 1.4.0 (build 7) in `project.yml` happens at TestFlight time, per the spec — not part of this implementation.
- Manual on-device verification via TestFlight (camera flow, permission prompt, denial path) happens after merge, by the user.
