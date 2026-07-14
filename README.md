# PictureFramer

An iPhone app that turns crooked photos of framed paintings into perfectly straight ones.

Photograph a painting in a museum or at home — the photo is usually shot at an angle, tilted and keystoned. PictureFramer imports it from your photo library, automatically finds the outer edge of the artwork including its frame, corrects perspective and rotation in one transform, keeps a configurable strip of the real background wall around the frame, and saves the result back to your photo library.

## Features

- **Automatic detection** of the painting/frame outline (Vision), with draggable corner handles as fallback when detection misses.
- **Perspective correction** (Core Image `CIPerspectiveCorrection`) — fixes rotation and horizontal/vertical keystone in one step.
- **Background margin**: a user-configurable number of pixels (0–500, equal on all four sides) of *real background pixels* kept outside the frame — never synthetic padding.
- **Pan to recenter**: drag the corrected preview when a shadow skewed the detected bounds off-center.
- **Live preview** on a downscaled copy for speed; export renders from the original full-resolution pixels.
- Works with unframed canvases too — anything with a detectable rectangular outline.

## Requirements

- Xcode 26+ (iOS 26.5 simulator platform; run `xcodebuild -downloadPlatform iOS` if destinations come up empty)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- iOS 17.0+ deployment target, iPhone only

## Building

The Xcode project is generated from `project.yml` and not checked in:

```sh
xcodegen generate
xcodebuild -project PictureFramer.xcodeproj -scheme PictureFramer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Or open `PictureFramer.xcodeproj` in Xcode after generating.

## Testing

```sh
# Full suite: unit tests (Swift Testing) + end-to-end UI test (XCUITest)
xcodebuild -project PictureFramer.xcodeproj -scheme PictureFramer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Unit tests generate synthetic fixture images headlessly (no bundled assets) and pixel-sample the outputs. The UI test drives the real photo picker; seed the simulator first:

```sh
xcrun simctl addmedia booted path/to/a-framed-picture.jpg
```

The permission-denial UI test self-skips unless you first run
`xcrun simctl privacy booted revoke photos-add com.corti.PictureFramer` (iOS 26 auto-grants add-only saves otherwise).

## Architecture

Canonical coordinate space everywhere: full-resolution source pixels, lower-left origin (= Core Image space). Vision output converts with a pure scale; the app's only y-flip lives in `DisplayMapper` at the SwiftUI boundary.

```
Sources/
  Core/            UI-free, fully unit-tested
    Geometry/      Quad model, margin expansion (edge offset + re-intersection)
    Coordinates/   Vision→canonical conversion, canonical↔display mapping
    Detection/     VNDetectRectanglesRequest wrapper (two-pass), downscaling
    Rendering/     Shared CIContext, CIPerspectiveCorrection wrapper
    Pipeline/      detect → margin → pan → correct; preview & export paths
    Export/        JPEG encode + PHPhotoLibrary add-only save (protocol seam)
  UI/              SwiftUI shell: picker → editor (quad overlay, margin, pan) → export
Tests/             Swift Testing unit suites + fixture/pixel-sampling helpers
UITests/           XCUITest end-to-end flows
```

See `CLAUDE.md` for detailed engineering conventions and platform gotchas.
