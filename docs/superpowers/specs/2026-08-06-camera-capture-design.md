# In-App Camera Capture — Design

**Date:** 2026-08-06
**Status:** Approved

## Summary

Add a "Take Photo" option to the picker screen that shoots a picture with the
system camera UI and hands it directly to the existing detection/correction
pipeline. Plain `UIImagePickerController` camera — no custom viewfinder, no
live rectangle overlay.

## Goals

- Shoot a framed picture inside the app and land in the editor exactly as if
  the photo had been chosen from the library.
- Zero changes to `Sources/Core/` — the pipeline does not care where pixels
  come from.
- Keep all logic in the tested view-model path; the camera wrapper is dumb glue.

## Non-Goals

- Custom `AVCaptureSession` viewfinder or live Vision rectangle overlay.
- Saving the original (uncorrected) capture to the photo library. The capture
  exists only in memory; the only library write remains the normal export.
- XCUITest coverage of the capture flow (simulator has no camera).

## Design

### 1. Data flow (view-model refactor)

Extract `load(data: Data) async` from `EditorViewModel.load(item:)` — the
portion after `loadTransferable`: `normalizedCGImage` → downscale →
`runDetection()`, including the stage transitions and error handling.
`load(item:)` becomes a thin wrapper that resolves the `PhotosPickerItem` to
`Data` and calls `load(data:)`. The camera path calls `load(data:)` directly.

EXIF orientation is already baked in by `normalizedCGImage(from:)`
(`.applyOrientationProperty`), so camera rotation is handled with no new code.

### 2. Camera wrapper

New file `Sources/UI/CameraPicker.swift`:

- `UIViewControllerRepresentable` wrapping `UIImagePickerController`.
- `sourceType = .camera`, `allowsEditing = false`.
- System UI provides shutter, flash, and retake/use-photo confirmation.
- Coordinator delegate reads `info[.originalImage]`, converts with
  `jpegData(compressionQuality: 0.95)` (preserves the EXIF orientation tag),
  invokes a `(Data) -> Void` callback, and dismisses.
- Cancel dismisses with no callback; app stays on the picker screen.
- No other logic — nothing in this file needs unit tests.

### 3. UI

`ContentView.pickerScreen`:

- "Take Photo" button (`camera` SF Symbol, `.bordered` style) below the
  existing "Choose Photo" `PhotosPicker` button.
- Rendered only when `UIImagePickerController.isSourceTypeAvailable(.camera)`
  — automatically hidden in the simulator.
- Presented via `fullScreenCover` (sheet-presented camera pickers are
  known-glitchy).

### 4. Permission and error handling

- Add `NSCameraUsageDescription` to `project.yml`; regenerate the project.
- On tap, check `AVCaptureDevice.authorizationStatus(for: .video)`:
  - `.denied` / `.restricted` → set `errorMessage` with a link to app
    Settings, mirroring the existing export-denial pattern. Do not present.
  - Otherwise present; iOS prompts automatically on first use.
- Undecodable capture data flows into the existing
  "Couldn't load that photo." path in `load(data:)`.

### 5. Testing

- Unit (Swift Testing): `load(data:)` with a JPEG-encoded
  `FixtureImageFactory` image reaches `.adjusting` with a detected quad;
  garbage data produces the error message and returns to `.picking`.
- Camera wrapper: not unit tested (UIKit glue, no logic).
- E2E: unchanged. Capture flow verified manually on device via TestFlight.

### 6. Chores

- Branch: `feature/camera-capture`, PR to `main`.
- Version bump to 1.4.0 (build 7) in `project.yml` at TestFlight time.
- README + CLAUDE.md: mention the in-app camera option.

## Decisions

- **Discard original capture** — no library write until normal export; avoids
  cluttering the library with skewed shots.
- **Test split** — all logic in the tested `load(data:)` path; wrapper stays
  logic-free; manual device verification via TestFlight.
