# Corner Magnifier Loupe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While dragging a quad corner handle in the editor, show a magnifier loupe — a zoomed circle of the source image centered on the corner's landing point, parked clear of the finger, with a crosshair and the two converging frame edges.

**Architecture:** A pure, unit-tested `LoupeGeometry` struct in `Sources/Core/` computes the loupe's coordinate projection and its parked side. A thin SwiftUI `MagnifierLoupeView` renders the magnified image + crosshair + edges using that geometry. `QuadOverlayView` reports drag begin/end so `EditorView` can show/hide the loupe. No pipeline or coordinate-invariant changes — the loupe consumes the existing `DisplayMapper`.

**Tech Stack:** Swift 6, SwiftUI, CoreGraphics, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-07-20-corner-loupe-design.md`

## Global Constraints

- Swift only, no Objective-C.
- `Sources/Core/` is UI-free — `LoupeGeometry` imports only CoreGraphics, no SwiftUI/UIKit.
- Canonical coordinate space = full-res source pixels, lower-left origin; the only y-flip stays in `DisplayMapper`. The loupe adds no new flip.
- Constants: **magnification 2.5×**, **loupe diameter 120 pt**, **margin 16 pt**.
- Loupe placement: parked at the top (`y = margin`); horizontally **opposite** the focus's half — focus on the right half → loupe on the left (`x = margin`); focus on the left half → loupe on the right (`x = areaSize.width - diameter - margin`); a focus exactly on the vertical midline resolves to the left.
- Active in both crop modes (the loupe lives on the corner-drag path, which is identical in framed and painting-only).
- The Xcode project is generated: after ADDING any file under `Sources/` or `Tests/`, run `xcodegen generate` before building. Never edit `PictureFramer.xcodeproj`.
- Build / test command (iPhone 17 Pro simulator):
  ```sh
  xcodebuild -project PictureFramer.xcodeproj -scheme PictureFramer \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test \
    -only-testing:<suite>
  ```
- Unit tests use Swift Testing (`import Testing`, `@Test`/`#expect`). SwiftUI views are not unit-tested in this app — they are build-verified.

---

### Task 1: `LoupeGeometry` (pure geometry)

**Files:**
- Create: `Sources/Core/Coordinates/LoupeGeometry.swift`
- Create: `Tests/LoupeGeometryTests.swift`

**Interfaces:**
- Produces:
  - `struct LoupeGeometry: Equatable { let focusDisplay: CGPoint; let magnification: CGFloat; let diameter: CGFloat }`
  - `var center: CGPoint` — `(diameter/2, diameter/2)`
  - `func project(_ displayPoint: CGPoint) -> CGPoint` — `(displayPoint - focusDisplay) * magnification + center`
  - `static func placement(focusDisplay: CGPoint, areaSize: CGSize, diameter: CGFloat, margin: CGFloat) -> CGRect`

- [ ] **Step 1: Write the failing tests**

`Tests/LoupeGeometryTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import PictureFramer

struct LoupeGeometryTests {

    private let geom = LoupeGeometry(
        focusDisplay: CGPoint(x: 200, y: 150), magnification: 2.5, diameter: 120)

    @Test func focusProjectsToCenter() {
        let c = geom.project(geom.focusDisplay)
        #expect(c == geom.center)
        #expect(geom.center == CGPoint(x: 60, y: 60))
    }

    @Test func offsetScalesByMagnification() {
        let p = geom.project(CGPoint(x: 210, y: 130))  // +10 x, -20 y
        #expect(p.x == 60 + 10 * 2.5)
        #expect(p.y == 60 + (-20) * 2.5)
    }

    @Test func placementGoesLeftWhenFocusOnRightHalf() {
        let rect = LoupeGeometry.placement(
            focusDisplay: CGPoint(x: 300, y: 100),
            areaSize: CGSize(width: 400, height: 600), diameter: 120, margin: 16)
        #expect(rect.minX == 16)
        #expect(rect.minY == 16)
        #expect(rect.width == 120)
        #expect(rect.height == 120)
    }

    @Test func placementGoesRightWhenFocusOnLeftHalf() {
        let rect = LoupeGeometry.placement(
            focusDisplay: CGPoint(x: 100, y: 100),
            areaSize: CGSize(width: 400, height: 600), diameter: 120, margin: 16)
        #expect(rect.minX == 400 - 120 - 16)  // 264
        #expect(rect.minY == 16)
    }

    @Test func focusOnMidlineResolvesLeft() {
        let rect = LoupeGeometry.placement(
            focusDisplay: CGPoint(x: 200, y: 100),
            areaSize: CGSize(width: 400, height: 600), diameter: 120, margin: 16)
        #expect(rect.minX == 16)  // >= width/2 counts as right half → loupe left
    }

    @Test func placementStaysInsideAreaAtExtremes() {
        let size = CGSize(width: 400, height: 600)
        let left = LoupeGeometry.placement(
            focusDisplay: CGPoint(x: 0, y: 0), areaSize: size, diameter: 120, margin: 16)
        let right = LoupeGeometry.placement(
            focusDisplay: CGPoint(x: 400, y: 0), areaSize: size, diameter: 120, margin: 16)
        #expect(left.minX >= 0)
        #expect(left.maxX <= size.width)
        #expect(right.minX >= 0)
        #expect(right.maxX <= size.width)
    }
}
```

- [ ] **Step 2: Write the implementation**

`Sources/Core/Coordinates/LoupeGeometry.swift`:

```swift
import CoreGraphics

/// Pure coordinate math for the corner-drag magnifier loupe. Projects
/// image-display-space points into the loupe's own circle-space and decides
/// which top corner the loupe parks in (opposite the finger). UI-free so it
/// can be unit-tested; the SwiftUI `MagnifierLoupeView` renders using it.
struct LoupeGeometry: Equatable {
    /// The point in image-display space the loupe is centered on — the
    /// corner's current on-screen landing point.
    let focusDisplay: CGPoint
    let magnification: CGFloat
    let diameter: CGFloat

    /// Center of the loupe in its own coordinate space.
    var center: CGPoint { CGPoint(x: diameter / 2, y: diameter / 2) }

    /// Maps a point in image-display space into loupe circle-space. The
    /// focus point maps to `center`; everything else fans out by
    /// `magnification`.
    func project(_ displayPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (displayPoint.x - focusDisplay.x) * magnification + center.x,
            y: (displayPoint.y - focusDisplay.y) * magnification + center.y
        )
    }

    /// The loupe's frame within the image area. Pinned to the top; placed on
    /// the side opposite the focus's horizontal half so the finger never
    /// covers it. A focus on the midline (or right of it) parks the loupe
    /// on the left.
    static func placement(
        focusDisplay: CGPoint, areaSize: CGSize, diameter: CGFloat, margin: CGFloat
    ) -> CGRect {
        let focusOnRightHalf = focusDisplay.x >= areaSize.width / 2
        let x = focusOnRightHalf ? margin : areaSize.width - diameter - margin
        return CGRect(x: x, y: margin, width: diameter, height: diameter)
    }
}
```

- [ ] **Step 3: Regenerate project and run the tests**

Run:
```sh
xcodegen generate
xcodebuild -project PictureFramer.xcodeproj -scheme PictureFramer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test \
  -only-testing:PictureFramerTests/LoupeGeometryTests
```
Expected: PASS (6 tests).

- [ ] **Step 4: Commit**

```bash
git add Sources/Core/Coordinates/LoupeGeometry.swift Tests/LoupeGeometryTests.swift
git commit -m "feat: add LoupeGeometry for corner magnifier"
```

---

### Task 2: `MagnifierLoupeView`

**Files:**
- Create: `Sources/UI/MagnifierLoupeView.swift`

**Interfaces:**
- Consumes: `LoupeGeometry` (Task 1); `DisplayMapper` (existing — exposes `let fittedRect: CGRect` and `func displayPoint(fromPixel:) -> CGPoint`); `Quad` (existing — `subscript(Quad.Corner) -> CGPoint`, `enum Corner { topLeft, topRight, bottomLeft, bottomRight }`).
- Produces: `struct MagnifierLoupeView: View` with initializer
  `MagnifierLoupeView(image: CGImage, mapper: DisplayMapper, quad: Quad, corner: Quad.Corner, areaSize: CGSize)`.

This task creates a SwiftUI view. There is no unit test (app convention); the deliverable is a clean build. The view is exercised for real in Task 3.

- [ ] **Step 1: Write the view**

`Sources/UI/MagnifierLoupeView.swift`:

```swift
import SwiftUI
import UIKit  // Color(.systemBackground) resolves via UIColor

/// A magnifier loupe shown while a quad corner is being dragged. Renders a
/// zoomed circle of the source image centered on the corner's landing point,
/// parked at the top of the image area opposite the finger, with a crosshair
/// marking the exact point and the two frame edges that meet at the corner.
/// All coordinate math goes through `LoupeGeometry` and the shared
/// `DisplayMapper` — the loupe adds no new coordinate conventions.
struct MagnifierLoupeView: View {
    let image: CGImage
    let mapper: DisplayMapper
    let quad: Quad
    let corner: Quad.Corner
    let areaSize: CGSize

    private static let magnification: CGFloat = 2.5
    private static let diameter: CGFloat = 120
    private static let margin: CGFloat = 16
    private static let crosshairArm: CGFloat = 10

    private var focusDisplay: CGPoint {
        mapper.displayPoint(fromPixel: quad[corner])
    }

    private var geometry: LoupeGeometry {
        LoupeGeometry(
            focusDisplay: focusDisplay,
            magnification: Self.magnification,
            diameter: Self.diameter
        )
    }

    var body: some View {
        let frame = LoupeGeometry.placement(
            focusDisplay: focusDisplay, areaSize: areaSize,
            diameter: Self.diameter, margin: Self.margin)
        content
            .frame(width: Self.diameter, height: Self.diameter)
            .clipShape(Circle())
            .overlay(Circle().stroke(.blue.opacity(0.6), lineWidth: 1.5))
            .shadow(radius: 4, y: 2)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
    }

    private var content: some View {
        ZStack {
            Color(.systemBackground)
            magnifiedImage
            edgesPath.stroke(.blue, lineWidth: 2)
            crosshairPath.stroke(.blue.opacity(0.9), lineWidth: 1)
        }
    }

    /// The source image drawn at `magnification`× the fitted size, positioned
    /// so the focus point lands at the loupe center.
    private var magnifiedImage: some View {
        let fitted = mapper.fittedRect
        let magW = fitted.width * Self.magnification
        let magH = fitted.height * Self.magnification
        let focusInMagX = (focusDisplay.x - fitted.minX) * Self.magnification
        let focusInMagY = (focusDisplay.y - fitted.minY) * Self.magnification
        // .position sets the subview's CENTER. Solve for the center that puts
        // the focus point at the loupe center (diameter/2).
        let centerX = Self.diameter / 2 + magW / 2 - focusInMagX
        let centerY = Self.diameter / 2 + magH / 2 - focusInMagY
        return Image(decorative: image, scale: 1)
            .resizable()
            .frame(width: magW, height: magH)
            .position(x: centerX, y: centerY)
    }

    private var edgesPath: Path {
        Path { p in
            let c = geometry.center
            for adjacent in adjacentCorners {
                let adjacentDisplay = mapper.displayPoint(fromPixel: quad[adjacent])
                p.move(to: c)
                p.addLine(to: geometry.project(adjacentDisplay))
            }
        }
    }

    private var crosshairPath: Path {
        Path { p in
            let c = geometry.center
            let a = Self.crosshairArm
            p.move(to: CGPoint(x: c.x - a, y: c.y))
            p.addLine(to: CGPoint(x: c.x + a, y: c.y))
            p.move(to: CGPoint(x: c.x, y: c.y - a))
            p.addLine(to: CGPoint(x: c.x, y: c.y + a))
        }
    }

    /// The two perimeter neighbors of `corner` (top/bottom edge + side edge).
    private var adjacentCorners: [Quad.Corner] {
        switch corner {
        case .topLeft: [.topRight, .bottomLeft]
        case .topRight: [.topLeft, .bottomRight]
        case .bottomLeft: [.topLeft, .bottomRight]
        case .bottomRight: [.topRight, .bottomLeft]
        }
    }
}
```

- [ ] **Step 2: Regenerate and build**

Run:
```sh
xcodegen generate
xcodebuild -project PictureFramer.xcodeproj -scheme PictureFramer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/MagnifierLoupeView.swift
git commit -m "feat: add MagnifierLoupeView"
```

---

### Task 3: Wire loupe into the editor

**Files:**
- Modify: `Sources/UI/QuadOverlayView.swift`
- Modify: `Sources/UI/EditorView.swift:20-47` (the `imageArea` non-preview branch)

**Interfaces:**
- Consumes: `MagnifierLoupeView(image:mapper:quad:corner:areaSize:)` (Task 2).
- Produces (on `QuadOverlayView`): two new closure parameters
  `onDragBegan: (Quad.Corner) -> Void` and `onDragEnded: () -> Void`, each
  defaulting to a no-op so the type stays source-compatible.

- [ ] **Step 1: Refactor `QuadOverlayView` — extract `CornerHandle`, add drag callbacks**

Replace the whole body of `Sources/UI/QuadOverlayView.swift` with:

```swift
import SwiftUI

/// Draws the detected/adjustable quad over the aspect-fitted source image
/// and lets the user drag its corners. All gesture math converts through
/// the one `DisplayMapper`. Reports drag begin/end so the editor can show a
/// magnifier loupe for the active corner.
struct QuadOverlayView: View {
    let quad: Quad
    let marginQuad: Quad?
    let mapper: DisplayMapper
    let onCornerMoved: (Quad.Corner, CGPoint) -> Void
    var onDragBegan: (Quad.Corner) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    private static let handleDiameter: CGFloat = 44

    var body: some View {
        let displayQuad = mapper.displayQuad(from: quad)
        ZStack {
            if let marginQuad {
                path(for: mapper.displayQuad(from: marginQuad))
                    .stroke(
                        .yellow.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
            }
            path(for: displayQuad)
                .stroke(.blue, lineWidth: 2)

            ForEach(Quad.Corner.allCases, id: \.self) { corner in
                CornerHandle(
                    position: displayQuad[corner],
                    diameter: Self.handleDiameter,
                    accessibilityName: accessibilityName(for: corner),
                    onMoved: { onCornerMoved(corner, $0) },
                    onBegan: { onDragBegan(corner) },
                    onEnded: onDragEnded
                )
            }
        }
    }

    private func path(for displayQuad: Quad) -> Path {
        Path { p in
            p.addLines(displayQuad.perimeterCorners)
            p.closeSubpath()
        }
    }

    private func accessibilityName(for corner: Quad.Corner) -> String {
        switch corner {
        case .topLeft: "Top left corner"
        case .topRight: "Top right corner"
        case .bottomLeft: "Bottom left corner"
        case .bottomRight: "Bottom right corner"
        }
    }
}

/// One draggable corner handle. Owns its own drag state so drag begin/end is
/// detected per corner without a flag shared across handles.
private struct CornerHandle: View {
    let position: CGPoint
    let diameter: CGFloat
    let accessibilityName: String
    let onMoved: (CGPoint) -> Void
    let onBegan: () -> Void
    let onEnded: () -> Void

    @State private var isDragging = false

    var body: some View {
        Circle()
            .fill(.blue.opacity(0.35))
            .overlay(Circle().stroke(.blue, lineWidth: 2))
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .position(position)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            onBegan()
                        }
                        onMoved(value.location)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEnded()
                    }
            )
            .accessibilityLabel(accessibilityName)
            .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
```

- [ ] **Step 2: Wire the loupe into `EditorView.imageArea`**

In `Sources/UI/EditorView.swift`, add the active-corner state. After the existing `@State private var lastPanTranslation: CGSize = .zero` (near the top of the struct), add:

```swift
    /// The corner currently being dragged — drives the magnifier loupe.
    @State private var activeCorner: Quad.Corner?
```

Then replace the `if let quad = model.quad { … }` block inside the `imageArea` non-preview branch with:

```swift
                    if let quad = model.quad {
                        QuadOverlayView(
                            quad: quad,
                            marginQuad: model.cropMode == .framed ? model.marginQuad : nil,
                            mapper: mapper,
                            onCornerMoved: { corner, displayPoint in
                                model.moveCorner(corner, toDisplayPoint: displayPoint, mapper: mapper)
                            },
                            onDragBegan: { activeCorner = $0 },
                            onDragEnded: { activeCorner = nil }
                        )
                        if let activeCorner {
                            MagnifierLoupeView(
                                image: sourceImage,
                                mapper: mapper,
                                quad: quad,
                                corner: activeCorner,
                                areaSize: proxy.size
                            )
                        }
                    }
```

(The surrounding `GeometryReader { proxy in … }`, the `mapper` binding, the `Image(decorative: sourceImage …)`, and the `else if let sourceImage = model.sourceImage` binding are unchanged — `sourceImage` and `proxy` are already in scope here.)

- [ ] **Step 3: Regenerate and build**

Run:
```sh
xcodegen generate
xcodebuild -project PictureFramer.xcodeproj -scheme PictureFramer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run the existing unit suite (guard against regressions)**

The overlay refactor touches no tested logic, but confirm the Core/UI suites still pass:
```sh
xcodebuild -project PictureFramer.xcodeproj -scheme PictureFramer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test \
  -only-testing:PictureFramerTests
```
Expected: all unit tests pass (the new `LoupeGeometryTests` included).

- [ ] **Step 5: Manual verification (simulator)**

Boot the simulator, install, seed a framed-picture photo, launch, pick the photo, and on the Straighten screen press-drag a corner handle. Confirm: a circular loupe appears at the top of the image area on the side opposite the finger; it shows the magnified image under the corner with a crosshair at the exact point and the blue frame edges converging; it moves as you drag; it disappears on release. Repeat with a corner on the other half to confirm the loupe flips sides. (Commands per `CLAUDE.md` Build/Run: `xcrun simctl boot`, `install`, `addmedia`, `launch`.)

Note in the task report that this check is visual and cannot be asserted headlessly; describe what you observed.

- [ ] **Step 6: Commit**

```bash
git add Sources/UI/QuadOverlayView.swift Sources/UI/EditorView.swift
git commit -m "feat: show magnifier loupe while dragging a corner"
```
