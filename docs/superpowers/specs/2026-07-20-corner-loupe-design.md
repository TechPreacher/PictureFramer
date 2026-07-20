# Corner Magnifier Loupe — Design

**Date:** 2026-07-20
**Status:** Approved

## Summary

While the user drags a quad corner handle in the editor, the finger covers
the exact spot the corner is being placed on. This feature adds a magnifier
**loupe**: a circular, zoomed view of the source image centered on the
corner's landing point, parked at the top of the image area (clear of the
finger), with a crosshair marking the exact landing point and the two frame
edges that meet at the corner. It removes the guesswork of placing a corner
under your own finger.

## Decisions (from brainstorming)

- **Placement:** fixed at the top of the image area, on the side *opposite*
  the finger's horizontal half (top-leading when the corner is on the right
  half, top-trailing when on the left). Never under the finger, never
  follows the finger around.
- **Content:** magnified source pixels + a crosshair reticle at the exact
  landing point + the two blue quad edges meeting at the dragged corner
  (so the user can align the corner to the frame).
- **Modes:** active in **both** crop modes (framed and painting-only) —
  corner dragging exists in both Adjust views and the loupe helps equally.
- **Magnification:** 2.5×. **Loupe diameter:** 120 pt. Both are single
  constants, tunable later.
- **Architecture:** the loupe's coordinate math lives in a pure,
  unit-tested `LoupeGeometry` struct in `Sources/Core/` (UI-free); the
  SwiftUI rendering is a thin `MagnifierLoupeView`.

## Design

### Components

1. **`Sources/Core/Coordinates/LoupeGeometry.swift`** (pure, tested)

   A value type computing loupe coordinate math. No SwiftUI/UIKit.

   - `init(focusDisplay: CGPoint, magnification: CGFloat, diameter: CGFloat)`
   - `var center: CGPoint` — the loupe's own-space center, `(diameter/2, diameter/2)`.
   - `func project(_ displayPoint: CGPoint) -> CGPoint` — maps a point in
     image-display space into loupe circle-space:
     `(displayPoint - focusDisplay) * magnification + center`.
     By construction `project(focusDisplay) == center`.
   - `static func placement(focusDisplay: CGPoint, areaSize: CGSize, diameter: CGFloat, margin: CGFloat) -> CGRect`
     — the loupe's frame in image-area coordinates. Vertical: pinned near
     the top (`y = margin`). Horizontal: **opposite** the focus's half —
     if `focusDisplay.x >= areaSize.width / 2` the loupe goes left
     (`x = margin`), else right (`x = areaSize.width - diameter - margin`).
     A focus exactly on the midline resolves to the leading (left) side
     deterministically.

2. **`Sources/UI/MagnifierLoupeView.swift`** (SwiftUI, build-verified)

   Inputs: `image: CGImage`, `mapper: DisplayMapper`, `quad: Quad`,
   `corner: Quad.Corner`, `areaSize: CGSize`. Renders, clipped to a circle
   of the loupe diameter:
   - **Backing:** a solid `Color(.systemBackground)` fill so the circle is
     never transparent when the magnified crop extends past the image edge.
   - **Magnified image:** `Image(decorative: image, scale: 1).resizable()`
     drawn at `fittedRect.size * magnification`, offset so the focus display
     point lands at the loupe center. The focus display point is
     `mapper.displayPoint(fromPixel: quad[corner])`.
   - **Frame edges:** for each of the two corners adjacent to `corner`, a
     blue line from `geometry.project(focusDisplay)` (= center) to
     `geometry.project(mapper.displayPoint(fromPixel: quad[adjacentCorner]))`,
     stroked to match the on-image quad style.
   - **Crosshair:** a short vertical + horizontal tick centered at the loupe
     center, in the same blue.
   - **Ring:** a thin circular stroke around the loupe edge for definition.

   The view positions itself via
   `LoupeGeometry.placement(...)` inside its parent.

3. **`Sources/UI/QuadOverlayView.swift`** (modified)

   - Extract the per-corner handle into a `CornerHandle` subview owning its
     own `@State private var isDragging` so drag start/end is detected
     per corner without a shared flag.
   - `QuadOverlayView` gains two closures:
     `onDragBegan: (Quad.Corner) -> Void` and `onDragEnded: () -> Void`.
   - In the handle gesture (`DragGesture(minimumDistance: 0)`):
     - `onChanged`: if not already dragging, set `isDragging = true` and
       call `onDragBegan(corner)`; always call the existing
       `onCornerMoved(corner, value.location)`.
     - `onEnded`: set `isDragging = false` and call `onDragEnded()`.

4. **`Sources/UI/EditorView.swift`** (modified)

   - Add `@State private var activeCorner: Quad.Corner?`.
   - Pass `onDragBegan: { activeCorner = $0 }` and
     `onDragEnded: { activeCorner = nil }` to `QuadOverlayView`.
   - Inside the same `GeometryReader` (the non-preview branch that draws the
     source image + `QuadOverlayView`), when `activeCorner` and
     `model.sourceImage` and `model.quad` are all present, overlay
     `MagnifierLoupeView(image:mapper:quad:corner:areaSize:)`.

### Data flow

1. Finger drags a `CornerHandle`. First `onChanged` → `onDragBegan(corner)`
   → `EditorView.activeCorner = corner`. Every `onChanged` also runs the
   existing `onCornerMoved`, updating `model.quad[corner]`.
2. `MagnifierLoupeView` derives the focus point from `model.quad[corner]`
   via `mapper` — the model update *is* the live signal; no separate
   point channel.
3. `LoupeGeometry` picks the parked side from the focus point and projects
   focus, adjacent corners, and the image offset into circle-space.
4. `onEnded` → `onDragEnded` → `activeCorner = nil` → loupe disappears.

### Adjacency

The two corners adjacent to each corner (for drawing the converging edges):
- `topLeft` ↔ `topRight`, `bottomLeft`
- `topRight` ↔ `topLeft`, `bottomRight`
- `bottomLeft` ↔ `topLeft`, `bottomRight`
- `bottomRight` ↔ `topRight`, `bottomLeft`

(These are the perimeter neighbors: top edge, left/right edge.)

## Testing

- **`LoupeGeometry` — Swift Testing unit tests:**
  - `project(focusDisplay)` equals `center`.
  - a display point offset by δ maps to `center + δ * magnification`
    (both axes, positive and negative δ).
  - `placement` puts the loupe on the **left** when focus is on the right
    half, on the **right** when focus is on the left half, and on the left
    for a focus exactly on the midline.
  - `placement` pins the loupe to `y = margin` and keeps it fully inside
    `areaSize` horizontally for focus at either extreme.
- **`MagnifierLoupeView`, `CornerHandle`, `EditorView` wiring —
  build-verified** (SwiftUI views are not unit-tested in this app). The
  gesture callbacks are trivial state toggles; the load-bearing math is in
  `LoupeGeometry`.

## Constraints / invariants preserved

- `Sources/Core/` stays UI-free — `LoupeGeometry` imports only CoreGraphics.
- No new y-flip: the loupe consumes the existing `DisplayMapper`; all
  canonical↔display conversion stays in `DisplayMapper`.
- No change to the framing pipeline, detection, export, or crop-mode logic.

## Out of scope

- Loupe for the corrected-preview pan gesture (that view has no corner
  handles).
- Haptics / animation polish beyond appear/disappear.
- User-configurable zoom or loupe size (single constants for now).
