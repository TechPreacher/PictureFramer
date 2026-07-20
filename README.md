# PictureFramer

An iPhone app that turns crooked photos of framed paintings into perfectly straight ones.

Photograph a painting in a museum or at home — the photo is usually shot at an angle, tilted and keystoned. PictureFramer imports it from your photo library, automatically finds the outer edge of the artwork including its frame, corrects perspective and rotation in one transform, keeps a configurable strip of the real background wall around the frame, and saves the result back to your photo library.

## Features

- **Crop mode**: choose upfront (and switch any time in the editor) between **With Frame & Wall** — the framed picture plus a strip of real background — and **Painting Only**, which crops to just the painting inside the frame. The choice is remembered across launches.
- **Automatic detection** of the painting/frame outline (Vision), with draggable corner handles as fallback when detection misses. In Painting Only mode, detection targets the painting *inside* the frame (nested-rectangle detection), falling back to the outer edge when it can't find an inner one.
- **Perspective correction** (Core Image `CIPerspectiveCorrection`) — fixes rotation and horizontal/vertical keystone in one step.
- **Background margin**: in With Frame & Wall mode, a user-configurable number of pixels (0–500, equal on all four sides) of *real background pixels* kept outside the frame — never synthetic padding. (Hidden in Painting Only mode, where there's no wall to keep.)
- **Pan to recenter**: drag the corrected preview when a shadow skewed the detected bounds off-center.
- **Live preview** on a downscaled copy for speed; export renders from the original full-resolution pixels.
- **AI reflection removal** (optional): brush over glass glare on a pinch-zoomable canvas (or tap Auto-detect for an on-device suggested mask); a cloud inpainting model (OpenAI `gpt-image-1` or Gemini 2.5 Flash Image, your own API key) reconstructs the artwork underneath. Only masked pixels can change — everything outside the mask stays bit-identical to the original, enforced client-side and covered by tests.
- **Settings** page for choosing the AI provider and storing API keys — keys live in the iOS Keychain, never in UserDefaults, and images are only sent when you tap Remove.
  - OpenAI: any API key with image access works.
  - Google Gemini: the key's project must be on a **paid/billed tier** — the image model has no free-tier quota, so free AI Studio keys validate fine but every removal fails with a quota (HTTP 429) error. Enable billing in Google AI Studio / Cloud Console first.
- Works with unframed canvases too — anything with a detectable rectangular outline.

## Requirements

- Xcode 26+ (iOS 26.5 simulator platform; run `xcodebuild -downloadPlatform iOS` if destinations come up empty)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- iOS 17.0+ deployment target, iPhone only
- Optional: an OpenAI or Google Gemini API key (entered in the app's Settings) to use reflection removal — everything else works without it

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
    Reflection/    glare-mask heuristic detector + brush-editable mask model
    Inpainting/    provider protocol (OpenAI / Gemini), crop→inpaint→composite
                   orchestrator; compositor guarantees outside-mask pixels
                   stay bit-identical
    Config/        provider settings; API keys behind a Keychain seam
  UI/              SwiftUI shell: picker → editor (quad overlay, margin, pan)
                   → optional reflection removal (mask brush, before/after)
                   → export; settings sheet for AI providers
Tests/             Swift Testing unit suites + fixture/pixel-sampling helpers
UITests/           XCUITest end-to-end flows
```

See `CLAUDE.md` for detailed engineering conventions and platform gotchas.
