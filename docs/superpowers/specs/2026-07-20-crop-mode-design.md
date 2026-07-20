# Crop Mode Selection — Design

**Date:** 2026-07-20
**Status:** Approved

## Summary

Add a user-selectable crop mode: keep the current behavior (crop the framed
picture plus a configurable strip of wall) or crop the painting itself,
excluding the frame. The mode is chosen upfront on the picker screen and can
be switched in the editor. In painting-only mode the margin control disappears
and the effective margin is zero — a wall margin makes no sense when the frame
itself is being cropped away.

## Decisions (from brainstorming)

- **Mode selection location:** segmented control on the picker screen sets the
  mode before choosing a photo; the editor shows the same control so a wrong
  guess doesn't force starting over. Switching modes in the editor re-runs
  detection (corner tweaks and pan are intentionally dropped — the quad
  changes wholesale).
- **Painting-edge detection:** nested-rectangle detection. Ask Vision for
  multiple rectangle candidates and pick one nested inside the largest — that
  is usually the painting inside its frame. Fallback: the outer quad if
  nothing qualifies (user drags corners inward; no error state).
- **Persistence:** the last-used mode is remembered across launches
  (UserDefaults).
- **Architecture:** mode is a `CropMode` enum threaded through Core. No
  separate pipeline path — the pipeline is unchanged; margin 0 means no
  expansion and `effectiveQuad` degenerates cleanly.

## Design

### 1. Core: `CropMode` + detection

- New file `Sources/Core/Config/CropMode.swift`:
  `enum CropMode: String, CaseIterable, Sendable { case framed, paintingOnly }`.
  String raw value is the persistence format.
- `RectangleDetector.detectQuad` gains a `mode` parameter with default
  `.framed` so existing callers are untouched. Internally:
  - Raise `maximumObservations` to ~8 and convert all candidates to full-res
    canonical quads.
  - **Framed mode:** current selection logic (unchanged behavior).
  - **Painting-only mode:** among candidates, identify the largest (the outer
    frame). Select the largest other candidate whose corners all sit inside
    the outer candidate by a minimum inset of ~1.5% of the image's max
    dimension — the inset requirement rejects Vision near-duplicate
    detections of the same edge. If no candidate qualifies, return the outer
    quad.
  - The existing two-pass strategy (default config, then permissive fallback)
    is preserved in both modes.
- `FramingPipeline.detectQuad` forwards the mode. All other pipeline methods
  are untouched.

### 2. ViewModel

- `EditorViewModel.cropMode: CropMode` — loaded from UserDefaults at init,
  persisted on change. `didSet`: persist; if a photo is loaded, invalidate the
  cleaned (AI) image and re-run detection.
- Effective margin: a private helper returns `0` when
  `cropMode == .paintingOnly`, else `marginPixels`. Every call site that
  currently reads `marginPixels` for rendering/detection goes through it
  (`marginQuad`, `regeneratePreview`, `beginReflectionRemoval`,
  `redetectReflections`'s `excludingBorder`, `export`). The slider value
  itself is preserved so switching back to framed mode restores it.
- `marginQuad` returns the same as `quad` in painting mode (no second dashed
  outline; the overlay draws one quad).

### 3. UI

- **Picker screen (`ContentView`):** segmented control with
  "With Frame & Wall" / "Painting Only" above the Choose Photo button, bound
  to `model.cropMode`. Caption text switches to match the mode.
- **Editor (`EditorView`):** the same segmented control in the controls
  stack. `MarginControlView` is hidden in painting-only mode. Pan, corner
  drag, preview toggle, reflection removal, and export are unchanged.

### 4. Testing

- **Detector:** extend `Tests/Support/FixtureImageFactory` to draw a
  painting-in-frame fixture (nested quads in distinct colors). Assert:
  - painting mode finds the inner quad (nearest-neighbor corner matching,
    generous Vision tolerance ~2.5–3.5% of max dimension);
  - framed mode finds the outer quad on the same fixture;
  - a single-rectangle fixture makes painting mode fall back to the outer
    quad.
- **ViewModel:** painting mode ignores the margin slider (effective margin 0
  in rendered output); switching modes re-runs detection; mode persistence
  round-trips through UserDefaults.
- **Pipeline:** untouched, existing tests stand.

## Out of scope

- Detecting mat/passe-partout as a third boundary.
- Per-photo mode memory (mode is global, last-used).
- Any change to the reflection-removal flow beyond the `excludingBorder`
  value.
