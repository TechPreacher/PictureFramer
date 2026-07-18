# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This App Is

**PictureFramer** — an iOS (iPhone-only) SwiftUI app that imports photos of framed paintings/pictures from the photo library, auto-detects the outer edge of the artwork including its frame (Vision), perspective-corrects it so it appears perfectly straight (Core Image), adds a user-configurable pixel margin of *real background* equally on all four sides, and exports the result to the photo library. An optional AI step removes glass reflections: an on-device heuristic proposes a glare mask, the user refines it with a brush, and a cloud inpainting provider (OpenAI or Gemini, user's own API key) repaints only the masked pixels.

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

### TestFlight .ipa

First bump `CFBundleShortVersionString`/`CFBundleVersion` in `project.yml` (App Store Connect rejects duplicate build numbers), commit, `xcodegen generate`. Then:

```sh
# 1. Archive UNSIGNED — do not use normal automatic signing (see why below)
xcodebuild -project PictureFramer.xcodeproj -scheme PictureFramer \
  -destination 'generic/platform=iOS' -archivePath /tmp/PictureFramer.xcarchive \
  archive CODE_SIGNING_ALLOWED=NO

# 2. Export re-signs via Apple cloud signing (needs network + Xcode's Apple ID session)
xcodebuild -exportArchive -archivePath /tmp/PictureFramer.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath /tmp/export -allowProvisioningUpdates
# → /tmp/export/PictureFramer.ipa; copy to ~/Temp/PictureFramer-<version>-b<build>.ipa —
#   the user uploads from there with Transporter (do not attempt the upload yourself).
```

`ExportOptions.plist` (not checked in — recreate as needed): keys `method=app-store-connect`, `teamID=M9Y77E7ZX5`, `signingStyle=automatic`, `uploadSymbols=true`.

Why unsigned-then-export: the team has **no registered devices** (user's iPhone is MDM-locked, no Developer Mode), so a normal automatically-signed archive fails with "Your team has no devices" — archive signing wants a *development* profile, which requires a device. Forcing `CODE_SIGN_IDENTITY="Apple Distribution"` on an automatic-signing archive fails with "conflicting provisioning settings" instead. App Store *distribution* signing needs no devices, and the team's Apple Distribution certificate is **cloud-managed** — it does NOT appear in `security find-identity`, so don't conclude it's missing; `-exportArchive -allowProvisioningUpdates` finds and uses it. Direct-to-device installs are impossible on the user's phone (MDM) — TestFlight is the only route onto hardware.

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
- **Reflection removal** (optional, after correction): `Core/Reflection/ReflectionMaskDetector.swift` proposes a glare mask (bright + unsaturated heuristic, no ML); `Core/Reflection/ReflectionMask.swift` holds proposal + brush strokes and rasterizes at any scale; `Core/Inpainting/ReflectionRemover.swift` crops the mask's padded bbox, sends it to an `InpaintingProvider` (OpenAI `gpt-image-1` via true mask edit, or Gemini 2.5 Flash Image via prompt+mask image), and `PatchCompositor` blends the returned patch back **only inside the mask** — pixels outside the mask are bit-identical (pure CoreGraphics clip-mask compositing; this is the tested fidelity invariant). Provider + API keys configured in `SettingsView`; keys live in the Keychain (`Core/Config/KeychainStore.swift`), never UserDefaults. All provider tests use `Tests/Support/StubURLProtocol.swift` — no live network.

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
- `CGImage.cropping(to:)` takes a TOP-LEFT-origin rect — always crop through `croppedCanonical` (`Core/Inpainting/ImageCoding.swift`), never call `cropping` directly with canonical coords.
- OpenAI's images/edits mask marks repaint regions with TRANSPARENT pixels; app masks are white-=repaint grayscale. `OpenAIInpainter.transparentWhereWhitePNG` converts.

## Process notes

- Feature work: spec in `docs/superpowers/specs/`, plan in `docs/superpowers/plans/`, then implement on a `feature/*` branch; PRs to `main` on github.com/TechPreacher/PictureFramer (switch gh account to `TechPreacher` for PR operations).
- `.superpowers/` is local scratch (gitignored) — session ledgers and reports live there.
