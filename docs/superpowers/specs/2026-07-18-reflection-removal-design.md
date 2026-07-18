# Reflection Removal — Design Spec

Date: 2026-07-18
Status: Approved (design dialogue 2026-07-18)

## Problem

Photos of framed artwork behind glass often carry reflections: ceiling-light
streaks, skylight glare, exit-sign glow (see `Design/Test Pictures
Reflections/`). These pixels hide the real artwork. Reconstructing what the
painting shows under the glare is a generative-AI inpainting task — no Apple
framework (Vision, Core Image) offers reflection removal or inpainting, and
classical CV cannot invent occluded content.

## Decisions Made

- **AI route:** cloud image-editing APIs, configured by the user.
- **Providers (v1):** OpenAI (`gpt-image-1`, true mask-based edit) and
  Google Gemini (Gemini 2.5 Flash Image). Provider layer is pluggable for
  future additions. Anthropic excluded — Claude does not generate images.
- **Masking UX:** on-device auto-detection proposes a glare mask; user
  refines with brush/eraser. Mirrors the existing pattern (auto-detect quad →
  user adjusts corners).
- **Pipeline position:** after perspective correction, before export. The AI
  operates on the rectified artwork; the mask is drawn on the straightened
  image.
- **Fidelity guarantee:** only masked pixels may change. Everything outside
  the mask stays bit-identical to the corrected original (enforced by
  client-side compositing, not by trusting the provider).

## User Flow

1. Straighten photo as today (detect quad → adjust → margin → correct).
2. New optional step **Remove Reflections** on the corrected image.
3. App proposes a glare mask, shown as a tinted overlay.
4. User refines mask with finger brush / eraser (adjustable radius); can
   re-run auto-detection.
5. Tap **Remove** → progress indicator → before/after comparison.
6. Accept (replaces working image) or revert.
7. Export full-res as today.

If no provider/API key is configured, the step shows a disabled state with a
"Set up AI provider" link to Settings. The feature is fully optional — the
existing pipeline is unchanged when unused.

## Architecture

All new logic lives in `Sources/Core` (UI-free, unit-tested), thin UI on top.
Canonical coordinate invariant unchanged: masks live in the corrected image's
pixel space, lower-left origin; UI coordinates map through `DisplayMapper`.

### Core/Reflection

- `ReflectionMaskDetector` — heuristic, on-device, no ML. Combines high
  luminance, low saturation, and soft local contrast (Core Image ops) into a
  binary mask over the corrected image. Output is a proposal only.
- `ReflectionMask` — mask model: detector raster + ordered brush strokes
  (add/erase, radius). Rasterizes at any target resolution so the same mask
  renders at preview resolution for UI and full resolution for compositing.

### Core/Inpainting

- `InpaintingProvider` protocol:
  `func inpaint(image: CGImage, mask: CGImage) async throws -> CGImage`.
- `OpenAIInpainter` — `POST /v1/images/edits`, model `gpt-image-1`, mask
  image with transparent pixels marking regions to repaint.
- `GeminiInpainter` — Gemini 2.5 Flash Image. No native mask parameter:
  sends image + mask image + strict instruction prompt. Compositor still
  guarantees the outside-mask invariant regardless of provider behavior.
- `PatchCompositor` — the fidelity core:
  1. Compute mask bounding box + context padding on the full-res corrected
     image.
  2. Crop, downscale to the provider's size limit, send with the
     correspondingly scaled mask.
  3. Upscale the returned patch to bounding-box size.
  4. Feather-blend into the full-res image **only inside the mask**.
  Pixels outside the mask are copied from the original — bit-identical.
  This also sidesteps provider output-resolution caps for large photos.

### Core/Config

- `AIProvider` enum: `.openAI`, `.gemini` (+ model identifier per provider).
- `ProviderSettings` — selected provider, persisted via `UserDefaults`
  (non-secret parts only).
- `KeychainStore` behind a `SecretStoring` protocol — API keys live in the
  Keychain only, never UserDefaults. In-memory fake for tests.

### UI (Sources/UI)

- `SettingsView` — reached via gear icon on the main screen. Provider
  picker, one `SecureField` per provider key, "Validate key" button (cheap
  authenticated ping), privacy/cost note ("selected image region is sent to
  the provider; usage billed to your API key").
- `ReflectionEditView` — tinted mask overlay, brush/eraser toggle, radius
  slider, re-detect button, Remove button, before/after compare,
  accept/revert.
- `EditorViewModel` gains reflection-step state; all heavy work delegated to
  tested Core types.

## Error Handling

- No key configured → route to Settings, step disabled.
- Network/API failure, timeout, refusal → alert; working image untouched.
- Provider returns unexpected size → compositor rescales; on impossible
  geometry, fail cleanly with original preserved.
- Wide-gamut/HEIC input converted to sRGB JPEG/PNG for transport; composite
  performed in the working color space.

## Testing (Swift Testing, no live network)

- Detector: synthetic fixtures via `FixtureImageFactory` — glare blobs drawn
  on textured quads; assert mask covers blob within tolerance, misses clean
  areas.
- `ReflectionMask`: stroke rasterization at two scales agrees (scaled IoU);
  erase removes; empty mask → empty raster.
- `PatchCompositor`: **outside-mask pixels bit-identical** (strongest
  invariant test); inside-mask pixels come from patch; feather bounded to
  mask; oversized/undersized patch handling.
- Providers: request encoding + response decoding against `URLProtocol`
  stubs; error mapping (401, 429, refusal payloads).
- Config: Keychain fake round-trips; settings persistence; no secret ever in
  UserDefaults (test asserts).
- Edge cases: empty mask (Remove disabled), mask covering entire image,
  1×1 image, provider switch mid-session.

## Out of Scope (v1)

- On-device Core ML inpainting fallback (possible later behind
  `InpaintingProvider`).
- Stability or other additional providers.
- Automatic no-touch removal without user mask review.
- Batch processing.
