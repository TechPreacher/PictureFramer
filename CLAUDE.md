# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This App Is

**PictureFramer** — an iOS (iPhone-only) SwiftUI app that imports photos of framed paintings/pictures from the photo library, auto-detects the outer edge of the artwork including its frame (Vision), perspective-corrects it so it appears perfectly straight (Core Image), adds a user-configurable pixel margin of *real background* equally on all four sides, and exports the result to the photo library.

## Build / Run / Test Commands

The Xcode project is generated — **edit `project.yml`, then run `xcodegen generate`**; never edit `PictureFramer.xcodeproj` by hand. New source files under `Sources/`, `Tests/`, or `UITests/` also require a regenerate.

```sh
xcodegen generate

# Build
xcodebuild -project PictureFramer.xcodeproj -scheme PictureFramer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# All tests (unit = Swift Testing, E2E = XCUITest)
xcodebuild -project PictureFramer.xcodeproj -scheme PictureFramer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# One suite / one test
xcodebuild ... test -only-testing:PictureFramerTests/QuadExpansionTests
xcodebuild ... test -only-testing:PictureFramerTests/QuadExpansionTests/zeroMarginReturnsIdenticalQuad

# Manual run in simulator
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl install booted <DerivedData>/Build/Products/Debug-iphonesimulator/PictureFramer.app
xcrun simctl addmedia booted <some-framed-picture>.jpg   # seed the photo library
xcrun simctl launch booted com.corti.PictureFramer
```

Xcode 26.6 requires the iOS 26.5 simulator platform (`xcodebuild -downloadPlatform iOS` if destinations come up empty).

## Architecture

The load-bearing invariant: **canonical coordinate space = full-resolution source-image pixels, lower-left origin** — identical to Core Image space. Every `Quad` in the app stores corners in this space.

- Vision → canonical is a pure scale, **no flip** (`Sources/Core/Coordinates/VisionQuadConversion.swift` — the only place Vision-normalized coordinates are interpreted).
- Canonical → `CIPerspectiveCorrection` is identity (corners pass straight into the filter).
- The **only y-flip in the entire app** lives in `Sources/Core/Coordinates/DisplayMapper.swift`, which maps canonical ↔ SwiftUI display space of the aspect-fitted image. All UI gesture math goes through it.
- EXIF orientation is baked in at image load (`EditorViewModel.normalizedCGImage`), so canonical space never sees orientation.

Pipeline (`Sources/Core/Pipeline/FramingPipeline.swift`): detect → margin → correct.

- **Detection** (`Core/Detection/RectangleDetector.swift`): `VNDetectRectanglesRequest`, two-pass (default config, then permissive fallback), runs on a downscaled copy but always returns a full-res quad. Downscale helper lives here too.
- **Margin** (`Quad.expanded(by:)` in `Core/Geometry/Quad.swift`): offsets each edge outward along its outward normal in source space and re-intersects — so the margin band contains *real background pixels*, never synthetic padding. Clamped to image bounds; oversized margins degrade to the image edge. Winding-flip check rejects negative margins that cross.
- **Correction** (`Core/Rendering/PerspectiveCorrector.swift`): `CIPerspectiveCorrection` through the one shared `CIContext` (`RenderContext.shared`).
- **Preview vs export**: `previewImage` corrects a downscaled copy for interactive speed; `finalImage` applies the transform to the original full-res pixels. Both must agree on aspect ratio (tested).
- **Export** (`Core/Export/PhotoLibraryExporter.swift`): JPEG encode + `.addOnly` authorization behind the `PhotoLibraryWriting` protocol seam; only the thin `PHPhotoLibraryWriter` touches the real library.

`Sources/Core/` is UI-free (no SwiftUI/UIKit imports) — everything there is unit-tested. `Sources/UI/` is a thin shell: `EditorViewModel` (`@Observable @MainActor`) holds the quad + margin and calls tested pipeline methods; views map coordinates exclusively via `DisplayMapper`.

## Engineering Standards

- **Swift only** — no Objective-C.
- Follow Apple best practices: Swift API Design Guidelines, SwiftUI-first, structured concurrency (`async/await`), value types where sensible.
- **Meaningful tests for all non-UI code, including edge cases** (no rectangle detected, quad partially outside bounds, oversized/zero/negative margin, rotated/keystoned fixtures, extreme aspect ratios, 1×1 images). Assert behavior, not just execution.
- Unit tests use **Swift Testing** (`import Testing`, `@Test`/`#expect`/`#require`); the E2E flow test in `UITests/` uses XCUITest (drives the real photo picker and permission alert).
- Test fixtures are generated headlessly (`Tests/Support/FixtureImageFactory.swift` draws quads into a `CGBitmapContext`; `PixelSampler` reads output pixels) — no bundled image assets.
- Vision detection tests use nearest-neighbor corner matching with generous tolerances (~2.5–3.5% of max dimension) — Vision is not pixel-exact.

## Gotchas

- `CGBitmapContext` and Core Image are lower-left origin; `PixelSampler` takes canonical coordinates and flips internally.
- `CIPerspectiveCorrection` reconstructs true rectangle proportions via homography — output size can differ noticeably from raw quad edge lengths; tests assert neighborhoods, not exact sizes.
- The photo picker needs no permission string (out-of-process); export needs `NSPhotoLibraryAddUsageDescription` (set in `project.yml`).
- In the XCUITest, picker grid cells are `images` with identifier `PXGGridLayout-Info`, newest first; a first-run onboarding banner may cover the grid (close it), and cells may stay non-hittable while thumbnails load (coordinate-tap them).
- iOS 26 photo-permission behavior (affects the denial-path UI test): with the permission not-determined, add-only saves are **auto-granted with no prompt**; after `simctl privacy … revoke photos-add`, the first save re-prompts with a card-style dialog that is NOT reachable via springboard accessibility queries (coordinate-tap its Don't Allow), and iOS may kill the app on the in-flight TCC change. `testRevokedPermissionShowsErrorAndSettingsLink` therefore denies in phase 1, relaunches in phase 2, and **skips unless you first run** `xcrun simctl privacy booted revoke photos-add com.corti.PictureFramer`.
