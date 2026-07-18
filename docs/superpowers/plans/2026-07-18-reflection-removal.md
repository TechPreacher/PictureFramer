# Reflection Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional AI-powered step that removes glass reflections from the perspective-corrected artwork image, with on-device mask detection + brush refinement, cloud inpainting via OpenAI `gpt-image-1` or Gemini 2.5 Flash Image, and a Settings page for provider + Keychain-stored API keys.

**Architecture:** All logic in `Sources/Core` (UI-free, Swift Testing). A `ReflectionMask` (detector raster + brush strokes) rasterizes at any scale; `ReflectionRemover` crops the mask's bounding box, sends it to an `InpaintingProvider`, and `PatchCompositor` blends the returned patch back **only inside the mask** — pixels outside the mask stay bit-identical. UI adds a `.reflection` stage to `EditorViewModel`, a `ReflectionEditView`, and a `SettingsView`.

**Tech Stack:** SwiftUI, Core Graphics/Core Image, ImageIO, URLSession (stubbed with `URLProtocol` in tests), Keychain Services, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-07-18-reflection-removal-design.md`

## Global Constraints

- Xcode project is generated: after creating ANY new file under `Sources/` or `Tests/`, run `xcodegen generate` before building. Never edit `PictureFramer.xcodeproj`.
- Build/test destination: `platform=iOS Simulator,name=iPhone 17 Pro`.
- Full unit-test command (used below as "RUN UNIT TESTS"):
  `xcodebuild -project PictureFramer.xcodeproj -scheme PictureFramer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:PictureFramerTests`
- Canonical coordinate space everywhere: image pixels, **lower-left origin** (Core Image space). `CGBitmapContext` drawing is lower-left too — draw canonical coords verbatim. The two exceptions that need a flip: `CGImage.cropping(to:)` (top-left origin — use the `croppedCanonical` helper from Task 4) and `DisplayMapper` (already exists).
- Swift only, Swift Testing for unit tests (`import Testing`, `@Test`, `#expect`, `#require`).
- No live network in tests — all provider tests go through `StubURLProtocol`.
- API keys: Keychain only, never `UserDefaults`.
- Commit after every green task with the exact message given in the task.
- iOS deployment target 17.0; don't use newer-only APIs.

## File Structure

| File | Responsibility |
|---|---|
| `Sources/Core/Config/AIProvider.swift` | Provider enum + display names |
| `Sources/Core/Config/SecretStoring.swift` | Secret-store protocol + in-memory impl (prod file, used by tests too) |
| `Sources/Core/Config/KeychainStore.swift` | Keychain-backed `SecretStoring` |
| `Sources/Core/Config/ProviderSettingsStore.swift` | Selected provider (UserDefaults) + keys (SecretStoring) |
| `Sources/Core/Reflection/ReflectionMask.swift` | Mask model: detected raster + strokes, rasterize at scale |
| `Sources/Core/Reflection/ReflectionMaskDetector.swift` | Heuristic glare proposal (luminance/saturation + dilation) |
| `Sources/Core/Inpainting/ImageCoding.swift` | PNG encode/decode, resize, canonical crop helpers |
| `Sources/Core/Inpainting/PatchCompositor.swift` | Mask bbox, feathering, outside-mask-untouched compositing |
| `Sources/Core/Inpainting/InpaintingProvider.swift` | Provider protocol + `InpaintingError` |
| `Sources/Core/Inpainting/OpenAIInpainter.swift` | `gpt-image-1` images/edits (multipart, true mask) |
| `Sources/Core/Inpainting/GeminiInpainter.swift` | Gemini 2.5 Flash Image generateContent |
| `Sources/Core/Inpainting/ProviderKeyValidator.swift` | Cheap authenticated ping per provider |
| `Sources/Core/Inpainting/ReflectionRemover.swift` | Orchestrator: mask → crop → provider → composite |
| `Sources/UI/SettingsView.swift` | Provider picker + key entry + validation |
| `Sources/UI/ReflectionEditView.swift` | Mask overlay, brush/eraser, run/accept UI |
| Modify: `Sources/UI/EditorViewModel.swift` | `.reflection` stage, mask state, removal + export wiring |
| Modify: `Sources/UI/EditorView.swift` | "Remove Reflections" entry point |
| Modify: `Sources/UI/ContentView.swift` | Gear icon → Settings sheet, `.reflection` routing |
| Modify: `Tests/Support/FixtureImageFactory.swift` | Glare fixture |
| Tests | One test file per Core type (paths per task) |

---

### Task 1: Provider config + secret storage

**Files:**
- Create: `Sources/Core/Config/AIProvider.swift`
- Create: `Sources/Core/Config/SecretStoring.swift`
- Create: `Sources/Core/Config/KeychainStore.swift`
- Create: `Sources/Core/Config/ProviderSettingsStore.swift`
- Test: `Tests/ProviderSettingsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum AIProvider: String, CaseIterable, Codable, Sendable { case openAI, gemini }` with `var displayName: String`
  - `protocol SecretStoring: Sendable { func setSecret(_ value: String?, forKey key: String) throws; func secret(forKey key: String) throws -> String? }`
  - `final class InMemorySecretStore: SecretStoring`
  - `final class KeychainStore: SecretStoring`
  - `final class ProviderSettingsStore: @unchecked Sendable` with `init(defaults: UserDefaults = .standard, secrets: any SecretStoring = KeychainStore())`, `var selectedProvider: AIProvider?` (get/set), `func apiKey(for provider: AIProvider) -> String?`, `func setAPIKey(_ key: String?, for provider: AIProvider)`, `var isConfigured: Bool`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ProviderSettingsTests.swift`:

```swift
import Foundation
import Testing
@testable import PictureFramer

@Suite struct ProviderSettingsTests {

    private func makeStore() -> (ProviderSettingsStore, UserDefaults, InMemorySecretStore) {
        let defaults = UserDefaults(suiteName: "ProviderSettingsTests-\(UUID().uuidString)")!
        let secrets = InMemorySecretStore()
        return (ProviderSettingsStore(defaults: defaults, secrets: secrets), defaults, secrets)
    }

    @Test func selectedProviderRoundTrips() {
        let (store, _, _) = makeStore()
        #expect(store.selectedProvider == nil)
        store.selectedProvider = .gemini
        #expect(store.selectedProvider == .gemini)
        store.selectedProvider = nil
        #expect(store.selectedProvider == nil)
    }

    @Test func apiKeyRoundTripsPerProvider() {
        let (store, _, _) = makeStore()
        store.setAPIKey("sk-open", for: .openAI)
        store.setAPIKey("gm-key", for: .gemini)
        #expect(store.apiKey(for: .openAI) == "sk-open")
        #expect(store.apiKey(for: .gemini) == "gm-key")
        store.setAPIKey(nil, for: .openAI)
        #expect(store.apiKey(for: .openAI) == nil)
    }

    @Test func secretsNeverTouchUserDefaults() {
        let (store, defaults, _) = makeStore()
        store.setAPIKey("sk-supersecret-123", for: .openAI)
        let values = defaults.dictionaryRepresentation().values.map { "\($0)" }
        #expect(!values.contains { $0.contains("sk-supersecret-123") })
    }

    @Test func isConfiguredRequiresProviderAndKey() {
        let (store, _, _) = makeStore()
        #expect(!store.isConfigured)
        store.selectedProvider = .openAI
        #expect(!store.isConfigured)
        store.setAPIKey("sk-x", for: .openAI)
        #expect(store.isConfigured)
        store.setAPIKey("", for: .openAI)
        #expect(!store.isConfigured)
    }

    @Test func keychainStoreRoundTrips() throws {
        let store = KeychainStore(service: "com.corti.PictureFramer.tests")
        try store.setSecret("hunter2", forKey: "unit-test-key")
        #expect(try store.secret(forKey: "unit-test-key") == "hunter2")
        try store.setSecret(nil, forKey: "unit-test-key")
        #expect(try store.secret(forKey: "unit-test-key") == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen generate` then RUN UNIT TESTS with `-only-testing:PictureFramerTests/ProviderSettingsTests`
Expected: BUILD FAILURE — `cannot find 'ProviderSettingsStore' in scope` etc.

- [ ] **Step 3: Implement**

Create `Sources/Core/Config/AIProvider.swift`:

```swift
import Foundation

/// Cloud inpainting providers the user can configure in Settings.
enum AIProvider: String, CaseIterable, Codable, Sendable {
    case openAI
    case gemini

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .gemini: "Google Gemini"
        }
    }
}
```

Create `Sources/Core/Config/SecretStoring.swift`:

```swift
import Foundation

/// Seam over secret persistence so tests never touch the real Keychain.
protocol SecretStoring: Sendable {
    /// nil value deletes the secret.
    func setSecret(_ value: String?, forKey key: String) throws
    func secret(forKey key: String) throws -> String?
}

final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    func setSecret(_ value: String?, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = value
    }

    func secret(forKey key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }
}
```

Create `Sources/Core/Config/KeychainStore.swift`:

```swift
import Foundation
import Security

/// Generic-password Keychain items, one per key, scoped by service.
final class KeychainStore: SecretStoring, @unchecked Sendable {
    enum KeychainError: Error { case unexpectedStatus(OSStatus) }

    private let service: String

    init(service: String = "com.corti.PictureFramer") {
        self.service = service
    }

    private func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    func setSecret(_ value: String?, forKey key: String) throws {
        let deleteStatus = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(deleteStatus)
        }
        guard let value else { return }
        var query = baseQuery(forKey: key)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    func secret(forKey key: String) throws -> String? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
```

Create `Sources/Core/Config/ProviderSettingsStore.swift`:

```swift
import Foundation

/// Non-secret settings in UserDefaults, API keys in the secret store.
final class ProviderSettingsStore: @unchecked Sendable {
    private static let providerKey = "selectedAIProvider"

    private let defaults: UserDefaults
    private let secrets: any SecretStoring

    init(defaults: UserDefaults = .standard, secrets: any SecretStoring = KeychainStore()) {
        self.defaults = defaults
        self.secrets = secrets
    }

    var selectedProvider: AIProvider? {
        get { defaults.string(forKey: Self.providerKey).flatMap(AIProvider.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: Self.providerKey) }
    }

    func apiKey(for provider: AIProvider) -> String? {
        (try? secrets.secret(forKey: "apiKey.\(provider.rawValue)")) ?? nil
    }

    func setAPIKey(_ key: String?, for provider: AIProvider) {
        try? secrets.setSecret(key, forKey: "apiKey.\(provider.rawValue)")
    }

    /// True when a provider is chosen AND it has a non-empty key.
    var isConfigured: Bool {
        guard let provider = selectedProvider,
              let key = apiKey(for: provider) else { return false }
        return !key.isEmpty
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate` then RUN UNIT TESTS with `-only-testing:PictureFramerTests/ProviderSettingsTests`
Expected: 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Config Tests/ProviderSettingsTests.swift
git commit -m "feat: provider settings with Keychain-backed API key storage"
```

---

### Task 2: ReflectionMask model

**Files:**
- Create: `Sources/Core/Reflection/ReflectionMask.swift`
- Test: `Tests/ReflectionMaskTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:

```swift
struct ReflectionMask: Sendable {
    struct Stroke: Equatable, Sendable {
        enum Mode: Equatable, Sendable { case add, erase }
        var mode: Mode
        var radius: CGFloat      // canonical pixels
        var points: [CGPoint]    // canonical coords (lower-left origin)
    }
    let imageSize: CGSize        // full-res corrected image size, pixels
    var detectedRaster: CGImage? // grayscale proposal (any resolution, white = glare)
    var strokes: [Stroke]
    init(imageSize: CGSize, detectedRaster: CGImage? = nil, strokes: [Stroke] = [])
    var isEmpty: Bool            // no raster and no add strokes
    mutating func add(_ stroke: Stroke)
    mutating func clear()        // drops raster and strokes
    /// Grayscale (DeviceGray, 8-bit, no alpha) raster, white = repaint.
    /// Output size = imageSize * scale (rounded, min 1). nil when isEmpty.
    func rasterize(scale: CGFloat) -> CGImage?
}
```

Canonical coords draw verbatim into `CGBitmapContext` (lower-left origin) — no flip.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ReflectionMaskTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import PictureFramer

@Suite struct ReflectionMaskTests {

    private let size = CGSize(width: 400, height: 300)

    private func gray(_ image: CGImage, atCanonical p: CGPoint) -> CGFloat {
        PixelSampler(image: image).grayValue(atCanonical: p)
    }

    @Test func emptyMaskRasterizesToNil() {
        let mask = ReflectionMask(imageSize: size)
        #expect(mask.isEmpty)
        #expect(mask.rasterize(scale: 1) == nil)
    }

    @Test func addStrokePaintsWhiteAlongPath() throws {
        var mask = ReflectionMask(imageSize: size)
        mask.add(.init(mode: .add, radius: 20,
                       points: [CGPoint(x: 100, y: 150), CGPoint(x: 200, y: 150)]))
        let raster = try #require(mask.rasterize(scale: 1))
        #expect(raster.width == 400 && raster.height == 300)
        #expect(gray(raster, atCanonical: CGPoint(x: 150, y: 150)) > 0.9)   // on the path
        #expect(gray(raster, atCanonical: CGPoint(x: 150, y: 145)) > 0.9)   // inside radius
        #expect(gray(raster, atCanonical: CGPoint(x: 150, y: 100)) < 0.1)   // far away
        #expect(gray(raster, atCanonical: CGPoint(x: 20, y: 20)) < 0.1)
    }

    @Test func eraseStrokeRemovesAddedArea() throws {
        var mask = ReflectionMask(imageSize: size)
        mask.add(.init(mode: .add, radius: 30, points: [CGPoint(x: 200, y: 150)]))
        mask.add(.init(mode: .erase, radius: 30, points: [CGPoint(x: 200, y: 150)]))
        let raster = try #require(mask.rasterize(scale: 1))
        #expect(gray(raster, atCanonical: CGPoint(x: 200, y: 150)) < 0.1)
    }

    @Test func singlePointStrokePaintsDot() throws {
        var mask = ReflectionMask(imageSize: size)
        mask.add(.init(mode: .add, radius: 15, points: [CGPoint(x: 50, y: 50)]))
        let raster = try #require(mask.rasterize(scale: 1))
        #expect(gray(raster, atCanonical: CGPoint(x: 50, y: 50)) > 0.9)
        #expect(gray(raster, atCanonical: CGPoint(x: 90, y: 50)) < 0.1)
    }

    @Test func rasterizationAgreesAcrossScales() throws {
        var mask = ReflectionMask(imageSize: size)
        mask.add(.init(mode: .add, radius: 40,
                       points: [CGPoint(x: 150, y: 100), CGPoint(x: 250, y: 200)]))
        let full = try #require(mask.rasterize(scale: 1))
        let half = try #require(mask.rasterize(scale: 0.5))
        #expect(half.width == 200 && half.height == 150)
        // Sample a grid; scaled mask must agree with full-res mask.
        for x in stride(from: 10, to: 390, by: 20) {
            for y in stride(from: 10, to: 290, by: 20) {
                let f = gray(full, atCanonical: CGPoint(x: x, y: y)) > 0.5
                let h = gray(half, atCanonical: CGPoint(x: x / 2, y: y / 2)) > 0.5
                // Allow disagreement only near the stroke boundary (within 4 px).
                let boundaryBand = abs(gray(full, atCanonical: CGPoint(x: x, y: y)) - 0.5) < 0.45
                if !boundaryBand {
                    #expect(f == h, "mismatch at (\(x), \(y))")
                }
            }
        }
    }

    @Test func detectedRasterScalesToTargetSize() throws {
        // 40×30 proposal with a white block lower-left quadrant.
        let proposal = FixtureImageFactory.solidImage(size: CGSize(width: 40, height: 30), gray: 0)
        var maskBytes = [UInt8](repeating: 0, count: 40 * 30)
        for y in 0..<15 { for x in 0..<20 { maskBytes[y * 40 + x] = 255 } }
        // Proposal bytes are row-major top-first; white block occupies the TOP rows
        // of memory, which is canonical y in 15..<30. Build via helper below.
        let raster = try #require(ReflectionMask.grayImage(from: maskBytes, width: 40, height: 30))
        var mask = ReflectionMask(imageSize: size, detectedRaster: raster)
        #expect(!mask.isEmpty)
        let full = try #require(mask.rasterize(scale: 1))
        // Memory top rows = canonical top → white in upper-left quadrant.
        #expect(gray(full, atCanonical: CGPoint(x: 100, y: 250)) > 0.9)
        #expect(gray(full, atCanonical: CGPoint(x: 300, y: 50)) < 0.1)
        mask.clear()
        #expect(mask.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen generate` then RUN UNIT TESTS with `-only-testing:PictureFramerTests/ReflectionMaskTests`
Expected: BUILD FAILURE — `cannot find 'ReflectionMask' in scope`.

- [ ] **Step 3: Implement**

Create `Sources/Core/Reflection/ReflectionMask.swift`:

```swift
import CoreGraphics

/// User-editable repaint mask over the corrected image: an optional
/// detector proposal raster plus ordered brush strokes. Coordinates are
/// canonical (corrected-image pixels, lower-left origin); CGBitmapContext
/// shares that origin, so drawing needs no flip.
struct ReflectionMask: Sendable {

    struct Stroke: Equatable, Sendable {
        enum Mode: Equatable, Sendable { case add, erase }
        var mode: Mode
        /// Brush radius in canonical pixels.
        var radius: CGFloat
        /// Path points in canonical coordinates.
        var points: [CGPoint]
    }

    /// Full-resolution corrected image size the mask refers to.
    let imageSize: CGSize
    /// Grayscale proposal from the detector (white = suspected glare).
    /// May be any resolution; it is scaled to the target on rasterize.
    var detectedRaster: CGImage?
    var strokes: [Stroke]

    init(imageSize: CGSize, detectedRaster: CGImage? = nil, strokes: [Stroke] = []) {
        self.imageSize = imageSize
        self.detectedRaster = detectedRaster
        self.strokes = strokes
    }

    /// True when rasterizing could not produce any repaint pixels.
    var isEmpty: Bool {
        detectedRaster == nil && !strokes.contains { $0.mode == .add }
    }

    mutating func add(_ stroke: Stroke) {
        guard !stroke.points.isEmpty else { return }
        strokes.append(stroke)
    }

    mutating func clear() {
        detectedRaster = nil
        strokes.removeAll()
    }

    /// Renders raster + strokes to a DeviceGray 8-bit image of size
    /// `imageSize * scale`. White = repaint. nil when the mask is empty.
    func rasterize(scale: CGFloat) -> CGImage? {
        guard !isEmpty, scale > 0 else { return nil }
        let width = max(Int((imageSize.width * scale).rounded()), 1)
        let height = max(Int((imageSize.height * scale).rounded()), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let detectedRaster {
            context.interpolationQuality = .high
            context.draw(detectedRaster, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            let gray: CGFloat = stroke.mode == .add ? 1 : 0
            context.setStrokeColor(gray: gray, alpha: 1)
            context.setFillColor(gray: gray, alpha: 1)
            let scaled = stroke.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
            let radius = stroke.radius * scale
            if scaled.count == 1, let p = scaled.first {
                context.fillEllipse(in: CGRect(
                    x: p.x - radius, y: p.y - radius,
                    width: radius * 2, height: radius * 2
                ))
            } else {
                context.setLineWidth(radius * 2)
                context.addLines(between: scaled)
                context.strokePath()
            }
        }
        return context.makeImage()
    }

    /// Builds a DeviceGray CGImage from row-major (top row first) bytes.
    /// Shared by the detector and tests.
    static func grayImage(from bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard bytes.count == width * height else { return nil }
        var copy = bytes
        return copy.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return nil }
            return context.makeImage()
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: RUN UNIT TESTS with `-only-testing:PictureFramerTests/ReflectionMaskTests`
Expected: 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Reflection/ReflectionMask.swift Tests/ReflectionMaskTests.swift
git commit -m "feat: reflection mask model with strokes and scale-independent rasterization"
```

---

### Task 3: ReflectionMaskDetector + glare fixture

**Files:**
- Create: `Sources/Core/Reflection/ReflectionMaskDetector.swift`
- Modify: `Tests/Support/FixtureImageFactory.swift` (add glare fixture)
- Test: `Tests/ReflectionMaskDetectorTests.swift`

**Interfaces:**
- Consumes: `downscaled(_:maxDimension:)` (global, `RectangleDetector.swift:102`), `ReflectionMask.grayImage(from:width:height:)` (Task 2).
- Produces:

```swift
struct ReflectionMaskDetector: Sendable {
    var analysisMaxDimension: CGFloat = 1024
    var luminanceThreshold: CGFloat = 0.82   // pixel counts as glare above this…
    var saturationThreshold: CGFloat = 0.30  // …and below this saturation
    var dilationRadius: Int = 2
    /// Grayscale proposal at analysis resolution (≤ analysisMaxDimension),
    /// white = suspected glare. nil when nothing detected.
    func detectMask(in image: CGImage) -> CGImage?
}
```

Also new fixture:

```swift
/// Dark "artwork" with a white glare ellipse — for detector tests.
static func glareImage(size: CGSize, artworkGray: CGFloat = 0.3, glareRect: CGRect) -> CGImage
```

- [ ] **Step 1: Add the glare fixture**

Append to `Tests/Support/FixtureImageFactory.swift` (inside the enum, after `solidImage`):

```swift
    /// Dark "artwork" with a bright glare ellipse — detector fixture.
    /// glareRect is in canonical coordinates.
    static func glareImage(
        size: CGSize,
        artworkGray: CGFloat = 0.3,
        glareRect: CGRect
    ) -> CGImage {
        drawImage(size: size) { context in
            context.setFillColor(gray: artworkGray, alpha: 1)
            context.fill(CGRect(origin: .zero, size: size))
            context.setFillColor(gray: 0.98, alpha: 1)
            context.fillEllipse(in: glareRect)
        }
    }
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/ReflectionMaskDetectorTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import PictureFramer

@Suite struct ReflectionMaskDetectorTests {

    private let detector = ReflectionMaskDetector()

    @Test func findsBrightGlareOnDarkArtwork() throws {
        let size = CGSize(width: 600, height: 400)
        let glare = CGRect(x: 200, y: 250, width: 150, height: 80)
        let image = FixtureImageFactory.glareImage(size: size, glareRect: glare)
        let mask = try #require(detector.detectMask(in: image))
        // Analysis size ≤ 1024, so no downscale here: mask is 600×400.
        let sampler = PixelSampler(image: mask)
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 275, y: 290)) > 0.9)  // glare center
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 50, y: 50)) < 0.1)    // clean corner
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 550, y: 350)) < 0.1)  // clean corner
    }

    @Test func cleanDarkImageYieldsNil() {
        let image = FixtureImageFactory.solidImage(size: CGSize(width: 300, height: 200), gray: 0.3)
        #expect(detector.detectMask(in: image) == nil)
    }

    @Test func largeImageMaskIsDownscaled() throws {
        let size = CGSize(width: 2048, height: 1536)
        let glare = CGRect(x: 800, y: 900, width: 300, height: 200)
        let image = FixtureImageFactory.glareImage(size: size, glareRect: glare)
        let mask = try #require(detector.detectMask(in: image))
        #expect(max(mask.width, mask.height) <= 1024)
        // Scale glare center into mask space.
        let scale = CGFloat(mask.width) / size.width
        let sampler = PixelSampler(image: mask)
        #expect(sampler.grayValue(
            atCanonical: CGPoint(x: 950 * scale, y: 1000 * scale)) > 0.9)
    }

    @Test func saturatedBrightColorIsNotGlare() {
        // Pure saturated red at high luminance-ish brightness — not glare.
        let size = CGSize(width: 300, height: 200)
        let image = FixtureImageFactory.drawnImage(size: size) { context in
            context.setFillColor(CGColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            context.setFillColor(CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 1))
            context.fillEllipse(in: CGRect(x: 100, y: 60, width: 100, height: 80))
        }
        #expect(detector.detectMask(in: image) == nil)
    }
}
```

This needs `drawnImage` exposed. In `Tests/Support/FixtureImageFactory.swift` rename the private `drawImage` helper to an internal `drawnImage` used by tests too — change:

```swift
    private static func drawImage(size: CGSize, draw: (CGContext) -> Void) -> CGImage {
```

to:

```swift
    static func drawnImage(size: CGSize, draw: (CGContext) -> Void) -> CGImage {
```

and update the three existing internal call sites (`image`, `noiseImage`, `solidImage`) plus the new `glareImage` from `drawImage(` to `drawnImage(`.

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodegen generate` then RUN UNIT TESTS with `-only-testing:PictureFramerTests/ReflectionMaskDetectorTests`
Expected: BUILD FAILURE — `cannot find 'ReflectionMaskDetector' in scope`.

- [ ] **Step 4: Implement**

Create `Sources/Core/Reflection/ReflectionMaskDetector.swift`:

```swift
import CoreGraphics

/// Heuristic glare proposal — no ML. A pixel is "glare" when it is bright
/// AND nearly unsaturated (specular highlights wash out color). The blob
/// map is dilated so the proposal generously covers halo edges; the user
/// refines with the brush afterwards.
struct ReflectionMaskDetector: Sendable {
    var analysisMaxDimension: CGFloat = 1024
    var luminanceThreshold: CGFloat = 0.82
    var saturationThreshold: CGFloat = 0.30
    var dilationRadius: Int = 2

    /// Grayscale mask at analysis resolution (white = suspected glare),
    /// or nil when no pixel qualifies.
    func detectMask(in image: CGImage) -> CGImage? {
        let small = downscaled(image, maxDimension: analysisMaxDimension)
        let width = small.width
        let height = small.height
        guard width > 0, height > 0 else { return nil }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(small, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hits = [Bool](repeating: false, count: width * height)
        var hitCount = 0
        for i in 0..<(width * height) {
            let r = CGFloat(rgba[i * 4]) / 255
            let g = CGFloat(rgba[i * 4 + 1]) / 255
            let b = CGFloat(rgba[i * 4 + 2]) / 255
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let maxC = max(r, g, b)
            let saturation = maxC == 0 ? 0 : (maxC - min(r, g, b)) / maxC
            if luminance >= luminanceThreshold && saturation <= saturationThreshold {
                hits[i] = true
                hitCount += 1
            }
        }
        guard hitCount > 0 else { return nil }

        // Box dilation: generous coverage of halo edges.
        var dilated = [UInt8](repeating: 0, count: width * height)
        let radius = dilationRadius
        for y in 0..<height {
            for x in 0..<width where hits[y * width + x] {
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let nx = x + dx
                        let ny = y + dy
                        if nx >= 0, nx < width, ny >= 0, ny < height {
                            dilated[ny * width + nx] = 255
                        }
                    }
                }
            }
        }
        return ReflectionMask.grayImage(from: dilated, width: width, height: height)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: RUN UNIT TESTS with `-only-testing:PictureFramerTests/ReflectionMaskDetectorTests` and `-only-testing:PictureFramerTests/RectangleDetectorTests` (fixture rename touched shared code — verify no regressions), then the full RUN UNIT TESTS.
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Reflection/ReflectionMaskDetector.swift Tests/ReflectionMaskDetectorTests.swift Tests/Support/FixtureImageFactory.swift
git commit -m "feat: heuristic glare detector proposing reflection masks"
```

---

### Task 4: Image coding helpers + PatchCompositor

**Files:**
- Create: `Sources/Core/Inpainting/ImageCoding.swift`
- Create: `Sources/Core/Inpainting/PatchCompositor.swift`
- Test: `Tests/ImageCodingTests.swift`
- Test: `Tests/PatchCompositorTests.swift`

**Interfaces:**
- Consumes: `ReflectionMask.grayImage` (Task 2), `RenderContext.shared` (existing).
- Produces (all in `ImageCoding.swift`, free functions matching the existing `downscaled` style):

```swift
func pngData(from image: CGImage) -> Data?
func cgImage(fromEncoded data: Data) -> CGImage?
/// Non-uniform resize (aspect may change; callers resize back so it cancels).
func resized(_ image: CGImage, to size: CGSize) -> CGImage?
/// Crop using CANONICAL (lower-left origin) rect. Wraps CGImage.cropping,
/// which takes a TOP-LEFT origin rect — the flip lives here only.
func croppedCanonical(_ image: CGImage, to rect: CGRect) -> CGImage?
```

and `PatchCompositor.swift`:

```swift
enum PatchCompositor {
    /// Canonical bbox of mask pixels > 127; nil when mask is black.
    static func maskBoundingBox(of mask: CGImage) -> CGRect?
    /// Gaussian-feathered copy of the mask, zeroed wherever the binary
    /// mask is black — feather only shrinks inward, never expands.
    static func featheredMask(from mask: CGImage, radius: CGFloat) -> CGImage?
    /// original + patch (drawn into patchRect) shown only where the
    /// full-image-sized mask is white. Pure Core Graphics — pixels where
    /// the mask is black are bit-identical to the original.
    static func composite(
        original: CGImage,
        patch: CGImage,
        patchRect: CGRect,          // canonical
        mask: CGImage               // full-image-sized grayscale
    ) -> CGImage?
}
```

- [ ] **Step 1: Write the failing tests**

Create `Tests/ImageCodingTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import PictureFramer

@Suite struct ImageCodingTests {

    @Test func pngRoundTripsPixels() throws {
        let image = FixtureImageFactory.noiseImage(size: CGSize(width: 64, height: 48), seed: 7)
        let data = try #require(pngData(from: image))
        let decoded = try #require(cgImage(fromEncoded: data))
        #expect(decoded.width == 64 && decoded.height == 48)
        let a = PixelSampler(image: image)
        let b = PixelSampler(image: decoded)
        for x in stride(from: 2, to: 64, by: 7) {
            for y in stride(from: 2, to: 48, by: 7) {
                let p = CGPoint(x: x, y: y)
                #expect(abs(a.grayValue(atCanonical: p) - b.grayValue(atCanonical: p)) < 0.02)
            }
        }
    }

    @Test func resizeChangesPixelSize() throws {
        let image = FixtureImageFactory.solidImage(size: CGSize(width: 100, height: 50), gray: 0.5)
        let out = try #require(resized(image, to: CGSize(width: 30, height: 40)))
        #expect(out.width == 30 && out.height == 40)
    }

    @Test func croppedCanonicalTakesLowerLeftRect() throws {
        // Image dark everywhere except a light square in the canonical
        // lower-left corner.
        let image = FixtureImageFactory.drawnImage(size: CGSize(width: 100, height: 80)) { ctx in
            ctx.setFillColor(gray: 0.1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
            ctx.setFillColor(gray: 0.9, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 30))   // canonical lower-left
        }
        let crop = try #require(croppedCanonical(image, to: CGRect(x: 0, y: 0, width: 40, height: 30)))
        #expect(crop.width == 40 && crop.height == 30)
        let sampler = PixelSampler(image: crop)
        #expect(sampler.isLight(atCanonical: CGPoint(x: 20, y: 15)))
    }
}
```

Create `Tests/PatchCompositorTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import PictureFramer

@Suite struct PatchCompositorTests {

    private let size = CGSize(width: 200, height: 160)

    /// Binary mask: white rectangle blob, black elsewhere.
    private func blobMask(white rect: CGRect) -> CGImage {
        var mask = ReflectionMask(imageSize: size)
        mask.add(.init(mode: .add, radius: min(rect.width, rect.height) / 2,
                       points: [CGPoint(x: rect.midX, y: rect.midY)]))
        return mask.rasterize(scale: 1)!
    }

    @Test func boundingBoxCoversWhitePixels() throws {
        let mask = blobMask(white: CGRect(x: 80, y: 60, width: 40, height: 40))
        let box = try #require(PatchCompositor.maskBoundingBox(of: mask))
        #expect(box.contains(CGPoint(x: 100, y: 80)))
        #expect(box.minX > 40 && box.maxX < 160)
        #expect(box.minY > 20 && box.maxY < 140)
    }

    @Test func blackMaskHasNoBoundingBox() {
        let black = ReflectionMask.grayImage(
            from: [UInt8](repeating: 0, count: 50 * 40), width: 50, height: 40)!
        #expect(PatchCompositor.maskBoundingBox(of: black) == nil)
    }

    @Test func compositeLeavesOutsideMaskBitIdentical() throws {
        let original = FixtureImageFactory.noiseImage(size: size, seed: 42)
        let mask = blobMask(white: CGRect(x: 80, y: 60, width: 40, height: 40))
        let patchRect = try #require(PatchCompositor.maskBoundingBox(of: mask))
        let patch = FixtureImageFactory.solidImage(
            size: CGSize(width: 50, height: 50), gray: 1.0)
        let result = try #require(PatchCompositor.composite(
            original: original, patch: patch, patchRect: patchRect, mask: mask))
        let maskSampler = PixelSampler(image: mask)
        let a = PixelSampler(image: original)
        let b = PixelSampler(image: result)
        for x in 0..<Int(size.width) {
            for y in 0..<Int(size.height) {
                let p = CGPoint(x: x, y: y)
                if maskSampler.grayValue(atCanonical: p) == 0 {
                    #expect(a.grayValue(atCanonical: p) == b.grayValue(atCanonical: p),
                            "pixel changed outside mask at (\(x), \(y))")
                }
            }
        }
        // Inside the mask (well inside, away from any antialiased edge):
        #expect(b.grayValue(atCanonical: CGPoint(x: 100, y: 80)) > 0.9)
        #expect(a.grayValue(atCanonical: CGPoint(x: 100, y: 80)) < 0.9
                || b.grayValue(atCanonical: CGPoint(x: 100, y: 80)) > 0.9)
    }

    @Test func featheredMaskNeverExpandsBeyondBinaryMask() throws {
        let mask = blobMask(white: CGRect(x: 80, y: 60, width: 40, height: 40))
        let feathered = try #require(PatchCompositor.featheredMask(from: mask, radius: 5))
        #expect(feathered.width == mask.width && feathered.height == mask.height)
        let binary = PixelSampler(image: mask)
        let soft = PixelSampler(image: feathered)
        for x in stride(from: 0, to: Int(size.width), by: 2) {
            for y in stride(from: 0, to: Int(size.height), by: 2) {
                let p = CGPoint(x: x, y: y)
                if binary.grayValue(atCanonical: p) == 0 {
                    #expect(soft.grayValue(atCanonical: p) == 0,
                            "feather leaked outside mask at (\(x), \(y))")
                }
            }
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen generate` then RUN UNIT TESTS with `-only-testing:PictureFramerTests/ImageCodingTests -only-testing:PictureFramerTests/PatchCompositorTests`
Expected: BUILD FAILURE — missing symbols.

- [ ] **Step 3: Implement**

Create `Sources/Core/Inpainting/ImageCoding.swift`:

```swift
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func pngData(from image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
}

func cgImage(fromEncoded data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// Non-uniform resize. Callers that distort aspect always resize back to
/// the source rect afterwards, so the distortion cancels.
func resized(_ image: CGImage, to size: CGSize) -> CGImage? {
    let width = max(Int(size.width.rounded()), 1)
    let height = max(Int(size.height.rounded()), 1)
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

/// Crop with a canonical (lower-left origin) rect. CGImage.cropping takes
/// a top-left-origin rect — this wrapper is the only place that flip
/// happens for crops.
func croppedCanonical(_ image: CGImage, to rect: CGRect) -> CGImage? {
    let flipped = CGRect(
        x: rect.minX,
        y: CGFloat(image.height) - rect.maxY,
        width: rect.width,
        height: rect.height
    )
    return image.cropping(to: flipped)
}
```

Create `Sources/Core/Inpainting/PatchCompositor.swift`:

```swift
import CoreGraphics
import CoreImage

/// Blends an AI-inpainted patch back into the original so that ONLY
/// masked pixels can change — the fidelity guarantee of the feature.
/// Compositing is pure Core Graphics: where the clip mask is black the
/// framebuffer keeps the already-drawn original bytes untouched.
enum PatchCompositor {

    /// Canonical bounding box of mask pixels > 127. nil for an all-black mask.
    static func maskBoundingBox(of mask: CGImage) -> CGRect? {
        let width = mask.width
        let height = mask.height
        var bytes = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, maxX = -1, minRow = height, maxRow = -1
        for row in 0..<height {
            for x in 0..<width where bytes[row * width + x] > 127 {
                minX = min(minX, x); maxX = max(maxX, x)
                minRow = min(minRow, row); maxRow = max(maxRow, row)
            }
        }
        guard maxX >= 0 else { return nil }
        // Bitmap rows count from the top; canonical y from the bottom.
        let minY = height - 1 - maxRow
        let maxY = height - 1 - minRow
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Gaussian blur of the mask, then zeroed wherever the binary mask is
    /// black — soft edge inside the blob, hard guarantee outside it.
    static func featheredMask(from mask: CGImage, radius: CGFloat) -> CGImage? {
        let width = mask.width
        let height = mask.height
        let blurred = CIImage(cgImage: mask)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: radius)
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        guard let blurredCG = RenderContext.shared.makeCGImage(from: blurred) else { return nil }

        func grayBytes(of image: CGImage) -> [UInt8]? {
            var bytes = [UInt8](repeating: 0, count: width * height)
            guard let context = CGContext(
                data: &bytes, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return bytes
        }
        guard let soft = grayBytes(of: blurredCG), let hard = grayBytes(of: mask) else {
            return nil
        }
        var out = [UInt8](repeating: 0, count: width * height)
        for i in 0..<out.count {
            out[i] = hard[i] > 127 ? soft[i] : 0
        }
        return ReflectionMask.grayImage(from: out, width: width, height: height)
    }

    /// Draws original, clips to the (full-image-sized) grayscale mask —
    /// white = paint — and draws the patch into patchRect. Canonical
    /// coordinates pass straight through: CGBitmapContext is lower-left.
    static func composite(
        original: CGImage,
        patch: CGImage,
        patchRect: CGRect,
        mask: CGImage
    ) -> CGImage? {
        let width = original.width
        let height = original.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: original.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.interpolationQuality = .high
        context.draw(original, in: fullRect)
        context.saveGState()
        // Grayscale image as clip mask: white samples paint, black are clipped.
        context.clip(to: fullRect, mask: mask)
        context.draw(patch, in: patchRect)
        context.restoreGState()
        return context.makeImage()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: RUN UNIT TESTS with `-only-testing:PictureFramerTests/ImageCodingTests -only-testing:PictureFramerTests/PatchCompositorTests`
Expected: 7 tests PASS. If `compositeLeavesOutsideMaskBitIdentical` fails with tiny deltas, the context color space differs from the original's — ensure the composite context uses `original.colorSpace`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Inpainting/ImageCoding.swift Sources/Core/Inpainting/PatchCompositor.swift Tests/ImageCodingTests.swift Tests/PatchCompositorTests.swift
git commit -m "feat: patch compositor guaranteeing pixels outside mask stay untouched"
```

---

### Task 5: InpaintingProvider protocol + OpenAI inpainter

**Files:**
- Create: `Sources/Core/Inpainting/InpaintingProvider.swift`
- Create: `Sources/Core/Inpainting/OpenAIInpainter.swift`
- Create: `Tests/Support/StubURLProtocol.swift`
- Test: `Tests/OpenAIInpainterTests.swift`

**Interfaces:**
- Consumes: `pngData`, `cgImage(fromEncoded:)` (Task 4), `AIProvider` (Task 1).
- Produces:

```swift
enum InpaintingError: Error, Equatable {
    case notConfigured        // no provider/key in settings
    case invalidKey           // HTTP 401/403
    case rateLimited          // HTTP 429
    case invalidResponse      // unparseable payload / no image returned
    case server(String)       // other HTTP error with message
    case emptyMask            // nothing to inpaint
    case renderingFailed      // local image op failed
}

protocol InpaintingProvider: Sendable {
    /// Pixel size the crop is resized to before upload (may change aspect;
    /// the caller resizes the result back so distortion cancels).
    func uploadSize(for cropSize: CGSize) -> CGSize
    /// Inpaints white-masked areas of `image`. `mask` is grayscale,
    /// same size as `image`, white = repaint. Result may be any size.
    func inpaint(image: CGImage, mask: CGImage, apiKey: String) async throws -> CGImage
}

struct OpenAIInpainter: InpaintingProvider {
    var session: URLSession = .shared
    var model: String = "gpt-image-1"
}

extension AIProvider {
    func makeInpainter(session: URLSession = .shared) -> any InpaintingProvider
}
```

Shared inpainting prompt (define once in `InpaintingProvider.swift`):

```swift
enum InpaintingPrompt {
    static let text = """
        This is a photograph of a painting. The masked region contains a \
        glass reflection or glare. Remove the reflection and reconstruct \
        the artwork underneath, matching the surrounding brushwork, colors, \
        texture and lighting exactly. Change nothing outside the masked \
        region. Return only the edited image.
        """
}
```

Test infra `Tests/Support/StubURLProtocol.swift`:

```swift
import Foundation

/// Intercepts URLSession requests in tests. Set `handler`, build a session
/// with `StubURLProtocol.session()`, assert on captured requests.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        // Body may arrive as a stream (multipart) — normalize to Data.
        var request = self.request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let bufferSize = 64 * 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate(); stream.close() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            request.httpBody = data
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
```

- [ ] **Step 1: Write the failing tests**

Create `Tests/OpenAIInpainterTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import PictureFramer

@Suite(.serialized) struct OpenAIInpainterTests {

    private let image = FixtureImageFactory.solidImage(size: CGSize(width: 64, height: 64), gray: 0.4)
    private let mask = ReflectionMask.grayImage(
        from: [UInt8](repeating: 255, count: 64 * 64), width: 64, height: 64)!

    private func inpainter() -> OpenAIInpainter {
        OpenAIInpainter(session: StubURLProtocol.session())
    }

    @Test func uploadSizePicksNearestAspect() {
        let sut = inpainter()
        #expect(sut.uploadSize(for: CGSize(width: 500, height: 480)) == CGSize(width: 1024, height: 1024))
        #expect(sut.uploadSize(for: CGSize(width: 900, height: 500)) == CGSize(width: 1536, height: 1024))
        #expect(sut.uploadSize(for: CGSize(width: 400, height: 800)) == CGSize(width: 1024, height: 1536))
    }

    @Test func sendsMultipartEditRequestAndDecodesImage() async throws {
        let returned = FixtureImageFactory.solidImage(size: CGSize(width: 64, height: 64), gray: 0.9)
        let b64 = pngData(from: returned)!.base64EncodedString()
        StubURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/images/edits")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
            let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
            #expect(contentType.hasPrefix("multipart/form-data; boundary="))
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            #expect(body.contains("name=\"model\""))
            #expect(body.contains("gpt-image-1"))
            #expect(body.contains("name=\"image[]\""))
            #expect(body.contains("name=\"mask\""))
            #expect(body.contains("name=\"prompt\""))
            let json = #"{"data":[{"b64_json":"\#(b64)"}]}"#
            return (200, Data(json.utf8))
        }
        let result = try await inpainter().inpaint(image: image, mask: mask, apiKey: "sk-test")
        #expect(result.width == 64 && result.height == 64)
    }

    @Test func maps401ToInvalidKey() async {
        StubURLProtocol.handler = { _ in (401, Data(#"{"error":{"message":"bad key"}}"#.utf8)) }
        await #expect(throws: InpaintingError.invalidKey) {
            _ = try await inpainter().inpaint(image: image, mask: mask, apiKey: "sk-bad")
        }
    }

    @Test func maps429ToRateLimited() async {
        StubURLProtocol.handler = { _ in (429, Data()) }
        await #expect(throws: InpaintingError.rateLimited) {
            _ = try await inpainter().inpaint(image: image, mask: mask, apiKey: "sk-test")
        }
    }

    @Test func mapsMalformedJSONToInvalidResponse() async {
        StubURLProtocol.handler = { _ in (200, Data("not json".utf8)) }
        await #expect(throws: InpaintingError.invalidResponse) {
            _ = try await inpainter().inpaint(image: image, mask: mask, apiKey: "sk-test")
        }
    }

    @Test func mapsServerErrorWithMessage() async {
        StubURLProtocol.handler = { _ in
            (500, Data(#"{"error":{"message":"boom"}}"#.utf8))
        }
        await #expect(throws: InpaintingError.server("boom")) {
            _ = try await inpainter().inpaint(image: image, mask: mask, apiKey: "sk-test")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen generate` then RUN UNIT TESTS with `-only-testing:PictureFramerTests/OpenAIInpainterTests`
Expected: BUILD FAILURE — missing `InpaintingProvider` / `OpenAIInpainter`.

- [ ] **Step 3: Implement**

Create `Sources/Core/Inpainting/InpaintingProvider.swift`:

```swift
import CoreGraphics
import Foundation

enum InpaintingError: Error, Equatable {
    case notConfigured
    case invalidKey
    case rateLimited
    case invalidResponse
    case server(String)
    case emptyMask
    case renderingFailed
}

/// A cloud service that repaints white-masked regions of an image.
protocol InpaintingProvider: Sendable {
    /// Pixel size the crop is resized to before upload. May change aspect;
    /// the caller resizes the result back so the distortion cancels.
    func uploadSize(for cropSize: CGSize) -> CGSize
    /// `mask` is grayscale, same size as `image`, white = repaint.
    /// The returned image may be any size; the caller rescales.
    func inpaint(image: CGImage, mask: CGImage, apiKey: String) async throws -> CGImage
}

enum InpaintingPrompt {
    static let text = """
        This is a photograph of a painting. The masked region contains a \
        glass reflection or glare. Remove the reflection and reconstruct \
        the artwork underneath, matching the surrounding brushwork, colors, \
        texture and lighting exactly. Change nothing outside the masked \
        region. Return only the edited image.
        """
}

extension AIProvider {
    func makeInpainter(session: URLSession = .shared) -> any InpaintingProvider {
        switch self {
        case .openAI: OpenAIInpainter(session: session)
        case .gemini: GeminiInpainter(session: session)
        }
    }
}
```

(The `GeminiInpainter` case won't compile until Task 6 — for THIS task, leave the extension out and add it in Task 6 instead. The `AIProvider.makeInpainter` extension is a Task 6 deliverable.)

Create `Sources/Core/Inpainting/OpenAIInpainter.swift`:

```swift
import CoreGraphics
import Foundation

/// OpenAI Images Edits API with a true inpainting mask: transparent mask
/// pixels mark the region to repaint.
struct OpenAIInpainter: InpaintingProvider {
    var session: URLSession = .shared
    var model: String = "gpt-image-1"

    /// gpt-image-1 accepts exactly these output sizes.
    private static let sizes = [
        CGSize(width: 1024, height: 1024),
        CGSize(width: 1536, height: 1024),
        CGSize(width: 1024, height: 1536),
    ]

    func uploadSize(for cropSize: CGSize) -> CGSize {
        guard cropSize.height > 0 else { return Self.sizes[0] }
        let aspect = cropSize.width / cropSize.height
        return Self.sizes.min {
            abs(log($0.width / $0.height) - log(aspect))
                < abs(log($1.width / $1.height) - log(aspect))
        }!
    }

    func inpaint(image: CGImage, mask: CGImage, apiKey: String) async throws -> CGImage {
        guard let imagePNG = pngData(from: image),
              let maskPNG = Self.transparentWhereWhitePNG(from: mask) else {
            throw InpaintingError.renderingFailed
        }
        var form = MultipartForm()
        form.addField(name: "model", value: model)
        form.addField(name: "prompt", value: InpaintingPrompt.text)
        form.addField(name: "size", value: "\(image.width)x\(image.height)")
        form.addFile(name: "image[]", filename: "image.png", mimeType: "image/png", data: imagePNG)
        form.addFile(name: "mask", filename: "mask.png", mimeType: "image/png", data: maskPNG)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/edits")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalized()

        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response: response, data: data)
        struct Payload: Decodable {
            struct Item: Decodable { let b64_json: String }
            let data: [Item]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let b64 = payload.data.first?.b64_json,
              let imageData = Data(base64Encoded: b64),
              let result = cgImage(fromEncoded: imageData) else {
            throw InpaintingError.invalidResponse
        }
        return result
    }

    /// OpenAI marks repaint regions with TRANSPARENT mask pixels; our masks
    /// use white. Convert: alpha = 255 - grayValue.
    static func transparentWhereWhitePNG(from mask: CGImage) -> Data? {
        let width = mask.width
        let height = mask.height
        var gray = [UInt8](repeating: 0, count: width * height)
        guard let grayContext = CGContext(
            data: &gray, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        grayContext.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            rgba[i * 4 + 3] = 255 &- gray[i]   // premultiplied black + inverse alpha
        }
        let out: CGImage? = rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return context.makeImage()
        }
        return out.flatMap(pngData(from:))
    }

    static func checkStatus(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw InpaintingError.invalidResponse
        }
        switch http.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw InpaintingError.invalidKey
        case 429:
            throw InpaintingError.rateLimited
        default:
            struct ErrorPayload: Decodable {
                struct Inner: Decodable { let message: String }
                let error: Inner
            }
            let message = (try? JSONDecoder().decode(ErrorPayload.self, from: data))?
                .error.message ?? "HTTP \(http.statusCode)"
            throw InpaintingError.server(message)
        }
    }
}

/// Minimal multipart/form-data builder.
struct MultipartForm {
    let boundary = "PictureFramer-\(UUID().uuidString)"
    private var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(name: String, value: String) {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        body.append(Data("\(value)\r\n".utf8))
    }

    mutating func addFile(name: String, filename: String, mimeType: String, data: Data) {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    func finalized() -> Data {
        var result = body
        result.append(Data("--\(boundary)--\r\n".utf8))
        return result
    }
}
```

Note: do NOT create the `AIProvider.makeInpainter` extension in this task (it references `GeminiInpainter`, which doesn't exist yet).

- [ ] **Step 4: Run tests to verify they pass**

Run: RUN UNIT TESTS with `-only-testing:PictureFramerTests/OpenAIInpainterTests`
Expected: 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Inpainting/InpaintingProvider.swift Sources/Core/Inpainting/OpenAIInpainter.swift Tests/Support/StubURLProtocol.swift Tests/OpenAIInpainterTests.swift
git commit -m "feat: inpainting provider protocol with OpenAI gpt-image-1 backend"
```

---

### Task 6: Gemini inpainter + provider factory + key validator

**Files:**
- Create: `Sources/Core/Inpainting/GeminiInpainter.swift`
- Create: `Sources/Core/Inpainting/ProviderKeyValidator.swift`
- Modify: `Sources/Core/Inpainting/InpaintingProvider.swift` (add factory extension)
- Test: `Tests/GeminiInpainterTests.swift`
- Test: `Tests/ProviderKeyValidatorTests.swift`

**Interfaces:**
- Consumes: `InpaintingProvider`, `InpaintingError`, `InpaintingPrompt`, `OpenAIInpainter.checkStatus` (Task 5), `pngData`/`cgImage(fromEncoded:)` (Task 4), `StubURLProtocol` (Task 5).
- Produces:

```swift
struct GeminiInpainter: InpaintingProvider {
    var session: URLSession = .shared
    var model: String = "gemini-2.5-flash-image"
}
extension AIProvider {
    func makeInpainter(session: URLSession = .shared) -> any InpaintingProvider
}
struct ProviderKeyValidator: Sendable {
    var session: URLSession = .shared
    /// True when the key authenticates (cheap GET, no generation).
    func validate(provider: AIProvider, apiKey: String) async -> Bool
}
```

- [ ] **Step 1: Write the failing tests**

Create `Tests/GeminiInpainterTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import PictureFramer

@Suite(.serialized) struct GeminiInpainterTests {

    private let image = FixtureImageFactory.solidImage(size: CGSize(width: 64, height: 64), gray: 0.4)
    private let mask = ReflectionMask.grayImage(
        from: [UInt8](repeating: 255, count: 64 * 64), width: 64, height: 64)!

    private func inpainter() -> GeminiInpainter {
        GeminiInpainter(session: StubURLProtocol.session())
    }

    @Test func uploadSizeCapsLongestSideAt1024PreservingAspect() {
        let sut = inpainter()
        #expect(sut.uploadSize(for: CGSize(width: 2048, height: 1024)) == CGSize(width: 1024, height: 512))
        #expect(sut.uploadSize(for: CGSize(width: 500, height: 400)) == CGSize(width: 500, height: 400))
    }

    @Test func sendsGenerateContentAndDecodesInlineImage() async throws {
        let returned = FixtureImageFactory.solidImage(size: CGSize(width: 64, height: 64), gray: 0.9)
        let b64 = pngData(from: returned)!.base64EncodedString()
        StubURLProtocol.handler = { request in
            #expect(request.url?.absoluteString ==
                "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent")
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "gm-test")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let json = try! JSONSerialization.jsonObject(
                with: request.httpBody ?? Data()) as! [String: Any]
            let contents = json["contents"] as! [[String: Any]]
            let parts = contents[0]["parts"] as! [[String: Any]]
            #expect(parts.count == 3)   // prompt text + image + mask
            #expect(parts[0]["text"] is String)
            let response = #"""
            {"candidates":[{"content":{"parts":[
              {"text":"done"},
              {"inlineData":{"mimeType":"image/png","data":"\#(b64)"}}
            ]}}]}
            """#
            return (200, Data(response.utf8))
        }
        let result = try await inpainter().inpaint(image: image, mask: mask, apiKey: "gm-test")
        #expect(result.width == 64 && result.height == 64)
    }

    @Test func responseWithoutImageIsInvalidResponse() async {
        StubURLProtocol.handler = { _ in
            (200, Data(#"{"candidates":[{"content":{"parts":[{"text":"no can do"}]}}]}"#.utf8))
        }
        await #expect(throws: InpaintingError.invalidResponse) {
            _ = try await inpainter().inpaint(image: image, mask: mask, apiKey: "gm-test")
        }
    }

    @Test func maps403ToInvalidKey() async {
        StubURLProtocol.handler = { _ in (403, Data()) }
        await #expect(throws: InpaintingError.invalidKey) {
            _ = try await inpainter().inpaint(image: image, mask: mask, apiKey: "gm-bad")
        }
    }

    @Test func factoryMakesMatchingInpainter() {
        #expect(AIProvider.openAI.makeInpainter() is OpenAIInpainter)
        #expect(AIProvider.gemini.makeInpainter() is GeminiInpainter)
    }
}
```

Create `Tests/ProviderKeyValidatorTests.swift`:

```swift
import Foundation
import Testing
@testable import PictureFramer

@Suite(.serialized) struct ProviderKeyValidatorTests {

    private func validator() -> ProviderKeyValidator {
        ProviderKeyValidator(session: StubURLProtocol.session())
    }

    @Test func openAIValidationHitsModelsEndpoint() async {
        StubURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/models")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-ok")
            return (200, Data("{}".utf8))
        }
        #expect(await validator().validate(provider: .openAI, apiKey: "sk-ok"))
    }

    @Test func geminiValidationHitsModelsEndpoint() async {
        StubURLProtocol.handler = { request in
            #expect(request.url?.absoluteString ==
                "https://generativelanguage.googleapis.com/v1beta/models")
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "gm-ok")
            return (200, Data("{}".utf8))
        }
        #expect(await validator().validate(provider: .gemini, apiKey: "gm-ok"))
    }

    @Test func badKeyFailsValidation() async {
        StubURLProtocol.handler = { _ in (401, Data()) }
        #expect(!(await validator().validate(provider: .openAI, apiKey: "sk-bad")))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen generate` then RUN UNIT TESTS with `-only-testing:PictureFramerTests/GeminiInpainterTests -only-testing:PictureFramerTests/ProviderKeyValidatorTests`
Expected: BUILD FAILURE — missing `GeminiInpainter` / `ProviderKeyValidator`.

- [ ] **Step 3: Implement**

Create `Sources/Core/Inpainting/GeminiInpainter.swift`:

```swift
import CoreGraphics
import Foundation

/// Gemini image editing via generateContent. Gemini has no native mask
/// parameter, so the mask goes along as a second inline image with strict
/// prompt instructions; PatchCompositor still enforces that only masked
/// pixels change regardless of what the model returns.
struct GeminiInpainter: InpaintingProvider {
    var session: URLSession = .shared
    var model: String = "gemini-2.5-flash-image"

    func uploadSize(for cropSize: CGSize) -> CGSize {
        let maxDimension: CGFloat = 1024
        let largest = max(cropSize.width, cropSize.height)
        guard largest > maxDimension else { return cropSize }
        let scale = maxDimension / largest
        return CGSize(
            width: (cropSize.width * scale).rounded(),
            height: (cropSize.height * scale).rounded()
        )
    }

    func inpaint(image: CGImage, mask: CGImage, apiKey: String) async throws -> CGImage {
        guard let imagePNG = pngData(from: image), let maskPNG = pngData(from: mask) else {
            throw InpaintingError.renderingFailed
        }
        let prompt = InpaintingPrompt.text + """
             The second image is the mask: repaint only areas that are \
            white in the mask.
            """
        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": "image/png",
                                     "data": imagePNG.base64EncodedString()]],
                    ["inline_data": ["mime_type": "image/png",
                                     "data": maskPNG.base64EncodedString()]],
                ],
            ]],
            "generationConfig": ["responseModalities": ["IMAGE"]],
        ]
        var request = URLRequest(url: URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try OpenAIInpainter.checkStatus(response: response, data: data)

        struct Payload: Decodable {
            struct Candidate: Decodable { let content: Content }
            struct Content: Decodable { let parts: [Part] }
            struct Part: Decodable { let inlineData: InlineData? }
            struct InlineData: Decodable { let data: String }
            let candidates: [Candidate]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let b64 = payload.candidates.first?.content.parts
                .compactMap(\.inlineData).first?.data,
              let imageData = Data(base64Encoded: b64),
              let result = cgImage(fromEncoded: imageData) else {
            throw InpaintingError.invalidResponse
        }
        return result
    }
}
```

Append to `Sources/Core/Inpainting/InpaintingProvider.swift`:

```swift
extension AIProvider {
    func makeInpainter(session: URLSession = .shared) -> any InpaintingProvider {
        switch self {
        case .openAI: OpenAIInpainter(session: session)
        case .gemini: GeminiInpainter(session: session)
        }
    }
}
```

Create `Sources/Core/Inpainting/ProviderKeyValidator.swift`:

```swift
import Foundation

/// Cheap authenticated GET per provider — verifies a key without paying
/// for a generation.
struct ProviderKeyValidator: Sendable {
    var session: URLSession = .shared

    func validate(provider: AIProvider, apiKey: String) async -> Bool {
        var request: URLRequest
        switch provider {
        case .openAI:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .gemini:
            request = URLRequest(url: URL(string:
                "https://generativelanguage.googleapis.com/v1beta/models")!)
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        }
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: RUN UNIT TESTS with `-only-testing:PictureFramerTests/GeminiInpainterTests -only-testing:PictureFramerTests/ProviderKeyValidatorTests`
Expected: 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Inpainting/GeminiInpainter.swift Sources/Core/Inpainting/ProviderKeyValidator.swift Sources/Core/Inpainting/InpaintingProvider.swift Tests/GeminiInpainterTests.swift Tests/ProviderKeyValidatorTests.swift
git commit -m "feat: Gemini inpainter, provider factory, and API key validator"
```

---

### Task 7: ReflectionRemover orchestrator

**Files:**
- Create: `Sources/Core/Inpainting/ReflectionRemover.swift`
- Test: `Tests/ReflectionRemoverTests.swift`

**Interfaces:**
- Consumes: `ReflectionMask` (Task 2), `PatchCompositor`, `croppedCanonical`, `resized` (Task 4), `InpaintingProvider`, `InpaintingError` (Task 5).
- Produces:

```swift
struct ReflectionRemover: Sendable {
    var paddingFraction: CGFloat = 0.12   // context border around the mask bbox
    var featherRadius: CGFloat = 6        // px at full res
    /// Full pipeline: rasterize mask → bbox+padding → crop → resize to
    /// provider upload size → inpaint → resize back → feather-composite.
    /// Throws InpaintingError.emptyMask / .renderingFailed / provider errors.
    func remove(
        from image: CGImage,
        mask: ReflectionMask,
        provider: any InpaintingProvider,
        apiKey: String
    ) async throws -> CGImage
}
```

- [ ] **Step 1: Write the failing tests**

Create `Tests/ReflectionRemoverTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import PictureFramer

/// Provider double: records what it was asked, returns a solid image at
/// the requested upload size.
private final class MockProvider: InpaintingProvider, @unchecked Sendable {
    var receivedImageSize: CGSize?
    var receivedMaskSize: CGSize?
    var resultGray: CGFloat = 1.0
    var errorToThrow: InpaintingError?

    func uploadSize(for cropSize: CGSize) -> CGSize {
        CGSize(width: 256, height: 256)   // fixed, aspect-distorting on purpose
    }

    func inpaint(image: CGImage, mask: CGImage, apiKey: String) async throws -> CGImage {
        if let errorToThrow { throw errorToThrow }
        receivedImageSize = CGSize(width: image.width, height: image.height)
        receivedMaskSize = CGSize(width: mask.width, height: mask.height)
        return FixtureImageFactory.solidImage(
            size: CGSize(width: image.width, height: image.height), gray: resultGray)
    }
}

@Suite struct ReflectionRemoverTests {

    private let size = CGSize(width: 640, height: 480)
    private let remover = ReflectionRemover()

    private func maskWithBlob(at center: CGPoint, radius: CGFloat) -> ReflectionMask {
        var mask = ReflectionMask(imageSize: size)
        mask.add(.init(mode: .add, radius: radius, points: [center]))
        return mask
    }

    @Test func emptyMaskThrows() async {
        let image = FixtureImageFactory.noiseImage(size: size, seed: 1)
        await #expect(throws: InpaintingError.emptyMask) {
            _ = try await remover.remove(
                from: image, mask: ReflectionMask(imageSize: size),
                provider: MockProvider(), apiKey: "k")
        }
    }

    @Test func cropIsResizedToProviderUploadSize() async throws {
        let image = FixtureImageFactory.noiseImage(size: size, seed: 2)
        let provider = MockProvider()
        _ = try await remover.remove(
            from: image, mask: maskWithBlob(at: CGPoint(x: 320, y: 240), radius: 60),
            provider: provider, apiKey: "k")
        #expect(provider.receivedImageSize == CGSize(width: 256, height: 256))
        #expect(provider.receivedMaskSize == CGSize(width: 256, height: 256))
    }

    @Test func resultChangesOnlyInsideMask() async throws {
        let image = FixtureImageFactory.solidImage(size: size, gray: 0.2)
        let mask = maskWithBlob(at: CGPoint(x: 320, y: 240), radius: 60)
        let provider = MockProvider()
        provider.resultGray = 1.0
        let result = try await remover.remove(
            from: image, mask: mask, provider: provider, apiKey: "k")
        #expect(result.width == Int(size.width) && result.height == Int(size.height))
        let sampler = PixelSampler(image: result)
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 320, y: 240)) > 0.9)  // repainted
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 50, y: 50)) < 0.3)    // untouched
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 600, y: 440)) < 0.3)  // untouched
    }

    @Test func maskCoveringWholeImageStillWorks() async throws {
        let image = FixtureImageFactory.solidImage(size: size, gray: 0.2)
        var mask = ReflectionMask(imageSize: size)
        mask.add(.init(mode: .add, radius: 500, points: [CGPoint(x: 320, y: 240)]))
        let result = try await remover.remove(
            from: image, mask: mask, provider: MockProvider(), apiKey: "k")
        let sampler = PixelSampler(image: result)
        #expect(sampler.grayValue(atCanonical: CGPoint(x: 320, y: 240)) > 0.9)
    }

    @Test func providerErrorPropagates() async {
        let image = FixtureImageFactory.noiseImage(size: size, seed: 3)
        let provider = MockProvider()
        provider.errorToThrow = .rateLimited
        await #expect(throws: InpaintingError.rateLimited) {
            _ = try await remover.remove(
                from: image, mask: maskWithBlob(at: CGPoint(x: 320, y: 240), radius: 60),
                provider: provider, apiKey: "k")
        }
    }

    @Test func tinyImageDoesNotCrash() async throws {
        let image = FixtureImageFactory.solidImage(size: CGSize(width: 4, height: 4), gray: 0.2)
        var mask = ReflectionMask(imageSize: CGSize(width: 4, height: 4))
        mask.add(.init(mode: .add, radius: 3, points: [CGPoint(x: 2, y: 2)]))
        let result = try await remover.remove(
            from: image, mask: mask, provider: MockProvider(), apiKey: "k")
        #expect(result.width == 4 && result.height == 4)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen generate` then RUN UNIT TESTS with `-only-testing:PictureFramerTests/ReflectionRemoverTests`
Expected: BUILD FAILURE — `cannot find 'ReflectionRemover' in scope`.

- [ ] **Step 3: Implement**

Create `Sources/Core/Inpainting/ReflectionRemover.swift`:

```swift
import CoreGraphics

/// Orchestrates one reflection-removal round trip. The provider only ever
/// sees a padded crop around the mask; the compositor guarantees pixels
/// outside the mask survive unchanged.
struct ReflectionRemover: Sendable {
    /// Context border around the mask bounding box, as a fraction of the
    /// box's larger side — gives the model surrounding artwork to match.
    var paddingFraction: CGFloat = 0.12
    /// Feather radius (full-res pixels) for the composite seam.
    var featherRadius: CGFloat = 6

    func remove(
        from image: CGImage,
        mask: ReflectionMask,
        provider: any InpaintingProvider,
        apiKey: String
    ) async throws -> CGImage {
        guard let fullMask = mask.rasterize(scale: 1),
              fullMask.width == image.width, fullMask.height == image.height else {
            throw InpaintingError.emptyMask
        }
        guard let box = PatchCompositor.maskBoundingBox(of: fullMask) else {
            throw InpaintingError.emptyMask
        }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let padding = max(box.width, box.height) * paddingFraction
        let cropRect = box.insetBy(dx: -padding, dy: -padding)
            .intersection(bounds)
            .integral
            .intersection(bounds)
        guard cropRect.width >= 1, cropRect.height >= 1,
              let imageCrop = croppedCanonical(image, to: cropRect),
              let maskCrop = croppedCanonical(fullMask, to: cropRect) else {
            throw InpaintingError.renderingFailed
        }

        let uploadSize = provider.uploadSize(for: cropRect.size)
        guard let uploadImage = resized(imageCrop, to: uploadSize),
              let uploadMask = resized(maskCrop, to: uploadSize) else {
            throw InpaintingError.renderingFailed
        }

        let patch = try await provider.inpaint(
            image: uploadImage, mask: uploadMask, apiKey: apiKey)

        // Resize back to the crop rect — any aspect distortion from the
        // upload resize cancels here.
        guard let patchAtCropSize = resized(patch, to: cropRect.size),
              let feathered = PatchCompositor.featheredMask(
                  from: fullMask, radius: featherRadius),
              let result = PatchCompositor.composite(
                  original: image,
                  patch: patchAtCropSize,
                  patchRect: cropRect,
                  mask: feathered) else {
            throw InpaintingError.renderingFailed
        }
        return result
    }
}
```

Note `resized` uses `CGImageAlphaInfo.premultipliedLast` — the grayscale mask crop goes through it too, which converts it to RGBA. `PatchCompositor.maskBoundingBox`/`featheredMask` redraw into DeviceGray contexts so this is fine, and the provider only needs "white vs black". If the DeviceGray→RGBA resize fails on some simulator, draw the mask into an RGB context first; the tests will catch it.

- [ ] **Step 4: Run tests to verify they pass**

Run: RUN UNIT TESTS with `-only-testing:PictureFramerTests/ReflectionRemoverTests`
Expected: 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Inpainting/ReflectionRemover.swift Tests/ReflectionRemoverTests.swift
git commit -m "feat: reflection remover orchestrating crop, inpaint, composite"
```

---

### Task 8: EditorViewModel reflection stage + export wiring

**Files:**
- Modify: `Sources/UI/EditorViewModel.swift`
- Test: `Tests/EditorViewModelReflectionTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–7.
- Produces (added to `EditorViewModel`):

```swift
// New stage case, inserted in enum Stage: case reflection
// New stored state:
private(set) var correctedFullRes: CGImage?    // full-res corrected image the mask refers to
var reflectionMask: ReflectionMask?
private(set) var cleanedImage: CGImage?        // accepted AI result (nil = none)
private(set) var pendingCleaned: CGImage?      // AI result awaiting accept/reject
private(set) var isRemovingReflections = false
let settings: ProviderSettingsStore

// New init parameter (appended, defaulted):
init(pipeline: FramingPipeline = FramingPipeline(),
     exporter: PhotoLibraryExporter = PhotoLibraryExporter(),
     settings: ProviderSettingsStore = ProviderSettingsStore(),
     detector: ReflectionMaskDetector = ReflectionMaskDetector(),
     remover: ReflectionRemover = ReflectionRemover(),
     inpainterFactory: @escaping @Sendable (AIProvider) -> any InpaintingProvider = { $0.makeInpainter() })

// New methods:
func beginReflectionRemoval() async   // renders correctedFullRes, runs detector, stage = .reflection
func redetectReflections()            // re-runs detector into reflectionMask
func addMaskStroke(_ stroke: ReflectionMask.Stroke)
func runReflectionRemoval() async     // → pendingCleaned, or errorMessage
func acceptCleaned()                  // pendingCleaned → cleanedImage, stage = .adjusting
func discardPendingCleaned()          // pendingCleaned = nil (stay in .reflection)
func exitReflectionRemoval()          // clears reflection state, stage = .adjusting
```

Export change: when `cleanedImage != nil`, `export()` saves `cleanedImage` directly instead of re-rendering `finalImage` (the cleaned image IS the full-res corrected render). Changing quad/margin/pan (`moveCorner`, `marginPixels.didSet`, `pan`, `resetPan`, `runDetection`) invalidates `cleanedImage` — add `invalidateCleaned()` calls there. `reset()` clears all new state.

- [ ] **Step 1: Write the failing tests**

Create `Tests/EditorViewModelReflectionTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import PictureFramer

@MainActor
@Suite struct EditorViewModelReflectionTests {

    private final class RecordingProvider: InpaintingProvider, @unchecked Sendable {
        var callCount = 0
        func uploadSize(for cropSize: CGSize) -> CGSize { cropSize }
        func inpaint(image: CGImage, mask: CGImage, apiKey: String) async throws -> CGImage {
            callCount += 1
            return FixtureImageFactory.solidImage(
                size: CGSize(width: image.width, height: image.height), gray: 1.0)
        }
    }

    /// Model with a loaded fixture "photo" and detected quad, configured
    /// provider, and a recording inpainter.
    private func makeModel(provider: RecordingProvider = RecordingProvider())
    -> (EditorViewModel, ProviderSettingsStore) {
        let defaults = UserDefaults(suiteName: "EditorVMReflection-\(UUID().uuidString)")!
        let settings = ProviderSettingsStore(defaults: defaults, secrets: InMemorySecretStore())
        settings.selectedProvider = .openAI
        settings.setAPIKey("sk-test", for: .openAI)
        let model = EditorViewModel(
            settings: settings,
            inpainterFactory: { _ in provider }
        )
        let size = CGSize(width: 800, height: 600)
        let quad = FixtureImageFactory.axisAlignedQuad(in: size, inset: 100)
        model.setSourceForTesting(
            FixtureImageFactory.image(size: size, quad: quad), quad: quad)
        return (model, settings)
    }

    @Test func beginReflectionRemovalRendersCorrectedAndEntersStage() async {
        let (model, _) = makeModel()
        await model.beginReflectionRemoval()
        #expect(model.stage == .reflection)
        #expect(model.correctedFullRes != nil)
        #expect(model.reflectionMask != nil)   // present (possibly empty of strokes)
    }

    @Test func runReflectionRemovalProducesPendingResult() async {
        let provider = RecordingProvider()
        let (model, _) = makeModel(provider: provider)
        await model.beginReflectionRemoval()
        model.addMaskStroke(.init(mode: .add, radius: 40,
                                  points: [CGPoint(x: 300, y: 200)]))
        await model.runReflectionRemoval()
        #expect(provider.callCount == 1)
        #expect(model.pendingCleaned != nil)
        #expect(model.cleanedImage == nil)
        #expect(model.errorMessage == nil)
    }

    @Test func acceptPendingMakesItTheCleanedImage() async {
        let (model, _) = makeModel()
        await model.beginReflectionRemoval()
        model.addMaskStroke(.init(mode: .add, radius: 40,
                                  points: [CGPoint(x: 300, y: 200)]))
        await model.runReflectionRemoval()
        model.acceptCleaned()
        #expect(model.cleanedImage != nil)
        #expect(model.pendingCleaned == nil)
        #expect(model.stage == .adjusting)
    }

    @Test func emptyMaskRemovalSetsError() async {
        let (model, _) = makeModel()
        await model.beginReflectionRemoval()
        model.reflectionMask?.clear()
        await model.runReflectionRemoval()
        #expect(model.pendingCleaned == nil)
        #expect(model.errorMessage != nil)
    }

    @Test func unconfiguredProviderSetsError() async {
        let (model, settings) = makeModel()
        settings.selectedProvider = nil
        await model.beginReflectionRemoval()
        model.addMaskStroke(.init(mode: .add, radius: 40,
                                  points: [CGPoint(x: 300, y: 200)]))
        await model.runReflectionRemoval()
        #expect(model.pendingCleaned == nil)
        #expect(model.errorMessage != nil)
    }

    @Test func adjustingQuadInvalidatesCleanedImage() async {
        let (model, _) = makeModel()
        await model.beginReflectionRemoval()
        model.addMaskStroke(.init(mode: .add, radius: 40,
                                  points: [CGPoint(x: 300, y: 200)]))
        await model.runReflectionRemoval()
        model.acceptCleaned()
        #expect(model.cleanedImage != nil)
        model.marginPixels = 80   // changes the crop — cleaned image is stale
        #expect(model.cleanedImage == nil)
    }

    @Test func resetClearsReflectionState() async {
        let (model, _) = makeModel()
        await model.beginReflectionRemoval()
        model.reset()
        #expect(model.correctedFullRes == nil)
        #expect(model.reflectionMask == nil)
        #expect(model.cleanedImage == nil)
        #expect(model.stage == .picking)
    }
}
```

- [ ] **Step 2: Add the test seam**

The tests need `setSourceForTesting`. In `Sources/UI/EditorViewModel.swift`, add at the bottom of the class:

```swift
    // MARK: Test support

    /// Injects a source image + quad without the photo picker. Test-only.
    func setSourceForTesting(_ image: CGImage, quad: Quad) {
        sourceImage = image
        self.quad = quad
        stage = .adjusting
    }
```

(Existing `EditorViewModelTests.swift` may already have a similar seam — check first; if one exists with a different name, use THAT name in the new tests instead of adding a duplicate.)

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodegen generate` then RUN UNIT TESTS with `-only-testing:PictureFramerTests/EditorViewModelReflectionTests`
Expected: BUILD FAILURE — missing members on `EditorViewModel`.

- [ ] **Step 4: Implement the ViewModel changes**

In `Sources/UI/EditorViewModel.swift`:

1. Add `case reflection` to `enum Stage` (after `.adjusting`).

2. Add stored properties (after `var errorMessage: String?`):

```swift
    // MARK: Reflection removal state

    /// Full-res corrected render the reflection mask refers to. Canonical
    /// space for the mask = this image's pixels, lower-left origin.
    private(set) var correctedFullRes: CGImage?
    var reflectionMask: ReflectionMask?
    /// Accepted AI result — exported verbatim instead of re-rendering.
    private(set) var cleanedImage: CGImage?
    /// AI result awaiting user accept/reject in the compare view.
    private(set) var pendingCleaned: CGImage?
    private(set) var isRemovingReflections = false

    let settings: ProviderSettingsStore
    private let reflectionDetector: ReflectionMaskDetector
    private let remover: ReflectionRemover
    private let inpainterFactory: @Sendable (AIProvider) -> any InpaintingProvider
```

3. Replace the init with:

```swift
    init(
        pipeline: FramingPipeline = FramingPipeline(),
        exporter: PhotoLibraryExporter = PhotoLibraryExporter(),
        settings: ProviderSettingsStore = ProviderSettingsStore(),
        detector: ReflectionMaskDetector = ReflectionMaskDetector(),
        remover: ReflectionRemover = ReflectionRemover(),
        inpainterFactory: @escaping @Sendable (AIProvider) -> any InpaintingProvider = {
            $0.makeInpainter()
        }
    ) {
        self.pipeline = pipeline
        self.exporter = exporter
        self.settings = settings
        self.reflectionDetector = detector
        self.remover = remover
        self.inpainterFactory = inpainterFactory
    }
```

4. Add the reflection methods (new `// MARK: Reflection removal` section before `// MARK: Export`):

```swift
    // MARK: Reflection removal

    /// Renders the full-res corrected image, proposes a glare mask, and
    /// enters the reflection stage.
    func beginReflectionRemoval() async {
        guard let sourceImage, let quad else { return }
        errorMessage = nil
        let margin = CGFloat(marginPixels)
        let pan = panOffset
        let pipeline = pipeline
        let detector = reflectionDetector
        let rendered = await Task.detached(priority: .userInitiated) {
            () -> (CGImage, CGImage?)? in
            guard let corrected = pipeline.finalImage(
                fullResImage: sourceImage, quad: quad,
                marginPixels: margin, panOffset: pan
            ) else { return nil }
            return (corrected, detector.detectMask(in: corrected))
        }.value
        guard let (corrected, proposal) = rendered else {
            errorMessage = "Rendering failed — try adjusting the corners."
            return
        }
        correctedFullRes = corrected
        reflectionMask = ReflectionMask(
            imageSize: CGSize(width: corrected.width, height: corrected.height),
            detectedRaster: proposal
        )
        pendingCleaned = nil
        stage = .reflection
    }

    func redetectReflections() {
        guard let correctedFullRes, var mask = reflectionMask else { return }
        mask.detectedRaster = reflectionDetector.detectMask(in: correctedFullRes)
        reflectionMask = mask
    }

    func addMaskStroke(_ stroke: ReflectionMask.Stroke) {
        reflectionMask?.add(stroke)
    }

    func runReflectionRemoval() async {
        guard let correctedFullRes, let mask = reflectionMask else { return }
        guard let provider = settings.selectedProvider,
              let apiKey = settings.apiKey(for: provider), !apiKey.isEmpty else {
            errorMessage = "Set up an AI provider in Settings first."
            return
        }
        guard !mask.isEmpty else {
            errorMessage = "Mark at least one reflection to remove."
            return
        }
        errorMessage = nil
        isRemovingReflections = true
        defer { isRemovingReflections = false }
        do {
            pendingCleaned = try await remover.remove(
                from: correctedFullRes,
                mask: mask,
                provider: inpainterFactory(provider),
                apiKey: apiKey
            )
        } catch InpaintingError.invalidKey {
            errorMessage = "The API key was rejected — check it in Settings."
        } catch InpaintingError.rateLimited {
            errorMessage = "The provider is rate-limiting — try again shortly."
        } catch InpaintingError.emptyMask {
            errorMessage = "Mark at least one reflection to remove."
        } catch let InpaintingError.server(message) {
            errorMessage = "Provider error: \(message)"
        } catch {
            errorMessage = "Reflection removal failed. Check your connection and try again."
        }
    }

    func acceptCleaned() {
        guard let pendingCleaned else { return }
        cleanedImage = pendingCleaned
        self.pendingCleaned = nil
        stage = .adjusting
        showCorrectedPreview = true
    }

    func discardPendingCleaned() {
        pendingCleaned = nil
    }

    func exitReflectionRemoval() {
        correctedFullRes = nil
        reflectionMask = nil
        pendingCleaned = nil
        errorMessage = nil
        stage = .adjusting
    }

    /// Any change to the crop makes an accepted AI result stale.
    private func invalidateCleaned() {
        cleanedImage = nil
        correctedFullRes = nil
        reflectionMask = nil
        pendingCleaned = nil
    }
```

5. Call `invalidateCleaned()` from every crop mutation:
   - in `marginPixels` didSet: `didSet { invalidateCleaned(); regeneratePreview() }`
   - first line of `pan(byDisplayDelta:previewFittedWidth:)` body after the guard: `invalidateCleaned()`
   - in `resetPan()` after the guard: `invalidateCleaned()`
   - in `moveCorner(_:toDisplayPoint:mapper:)` after the first guard: `invalidateCleaned()`
   - in `runDetection()` after `stage = .detecting`: `invalidateCleaned()`

6. In `export()`, use the cleaned image when present. Replace the render block:

```swift
        let rendered: CGImage?
        if let cleanedImage {
            rendered = cleanedImage
        } else {
            let margin = CGFloat(marginPixels)
            let pan = panOffset
            let pipeline = pipeline
            rendered = await Task.detached(priority: .userInitiated) {
                pipeline.finalImage(
                    fullResImage: sourceImage,
                    quad: quad,
                    marginPixels: margin,
                    panOffset: pan
                )
            }.value
        }
```

7. In `reset()`, add before `stage = .picking`:

```swift
        invalidateCleaned()
```

- [ ] **Step 5: Run tests to verify they pass**

Run: RUN UNIT TESTS with `-only-testing:PictureFramerTests/EditorViewModelReflectionTests`, then full RUN UNIT TESTS (existing `EditorViewModelTests` touch the same init/`export`).
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/UI/EditorViewModel.swift Tests/EditorViewModelReflectionTests.swift
git commit -m "feat: reflection-removal stage in editor view model with export wiring"
```

---

### Task 9: Settings UI

**Files:**
- Create: `Sources/UI/SettingsView.swift`
- Modify: `Sources/UI/ContentView.swift`

**Interfaces:**
- Consumes: `ProviderSettingsStore`, `AIProvider` (Task 1), `ProviderKeyValidator` (Task 6).
- Produces: `struct SettingsView: View` presented as a sheet from a gear toolbar button in `ContentView`.

- [ ] **Step 1: Implement SettingsView**

Create `Sources/UI/SettingsView.swift`:

```swift
import SwiftUI

/// AI provider configuration: pick a provider, store its API key in the
/// Keychain, optionally validate the key with a cheap authenticated ping.
struct SettingsView: View {
    let settings: ProviderSettingsStore

    @Environment(\.dismiss) private var dismiss
    @State private var selectedProvider: AIProvider?
    @State private var keys: [AIProvider: String] = [:]
    @State private var validationState: [AIProvider: ValidationState] = [:]

    private let validator = ProviderKeyValidator()

    enum ValidationState: Equatable {
        case validating
        case valid
        case invalid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: $selectedProvider) {
                        Text("None").tag(AIProvider?.none)
                        ForEach(AIProvider.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(AIProvider?.some(provider))
                        }
                    }
                } header: {
                    Text("AI Provider")
                } footer: {
                    Text("Reflection removal sends the masked image region to the selected provider. Usage is billed to your own API key.")
                }

                ForEach(AIProvider.allCases, id: \.self) { provider in
                    Section("\(provider.displayName) API Key") {
                        SecureField("API key", text: keyBinding(for: provider))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        HStack {
                            Button("Validate Key") {
                                Task { await validate(provider) }
                            }
                            .disabled((keys[provider] ?? "").isEmpty
                                      || validationState[provider] == .validating)
                            Spacer()
                            validationLabel(for: provider)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save()
                        dismiss()
                    }
                }
            }
            .onAppear(perform: load)
        }
    }

    @ViewBuilder
    private func validationLabel(for provider: AIProvider) -> some View {
        switch validationState[provider] {
        case .validating:
            ProgressView()
        case .valid:
            Label("Valid", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .invalid:
            Label("Invalid", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case nil:
            EmptyView()
        }
    }

    private func keyBinding(for provider: AIProvider) -> Binding<String> {
        Binding(
            get: { keys[provider] ?? "" },
            set: { keys[provider] = $0; validationState[provider] = nil }
        )
    }

    private func load() {
        selectedProvider = settings.selectedProvider
        for provider in AIProvider.allCases {
            keys[provider] = settings.apiKey(for: provider) ?? ""
        }
    }

    private func save() {
        settings.selectedProvider = selectedProvider
        for provider in AIProvider.allCases {
            let key = (keys[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            settings.setAPIKey(key.isEmpty ? nil : key, for: provider)
        }
    }

    private func validate(_ provider: AIProvider) async {
        let key = (keys[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        validationState[provider] = .validating
        let ok = await validator.validate(provider: provider, apiKey: key)
        validationState[provider] = ok ? .valid : .invalid
    }
}
```

- [ ] **Step 2: Wire into ContentView**

In `Sources/UI/ContentView.swift`:

Add state (after `@State private var model = EditorViewModel()`):

```swift
    @State private var showSettings = false
```

Add to the `NavigationStack`'s `Group` modifiers (after `.sensoryFeedback(...)`):

```swift
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: model.settings)
            }
```

Also extend the stage switch for the new stage (compiler will demand it once `.reflection` exists — Task 8 already added the case). Add to the switch:

```swift
                case .reflection:
                    ReflectionEditView(model: model)
```

`ReflectionEditView` arrives in Task 10 — if executing this task before Task 10, use a placeholder `Text("Reflection editor")` and replace it in Task 10. If Task 8 landed first (it did, per order), the switch is non-exhaustive without this arm.

- [ ] **Step 3: Build**

Run: `xcodegen generate` then
`xcodebuild -project PictureFramer.xcodeproj -scheme PictureFramer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: BUILD SUCCEEDED (with the placeholder arm if Task 10 not done yet).

- [ ] **Step 4: Commit**

```bash
git add Sources/UI/SettingsView.swift Sources/UI/ContentView.swift
git commit -m "feat: settings page for AI provider selection and API keys"
```

---

### Task 10: Reflection editing UI

**Files:**
- Create: `Sources/UI/ReflectionEditView.swift`
- Modify: `Sources/UI/EditorView.swift` (entry point button)
- Modify: `Sources/UI/ContentView.swift` (replace Task 9 placeholder if present)

**Interfaces:**
- Consumes: `EditorViewModel` reflection API (Task 8), `DisplayMapper` (existing), `ReflectionMask` (Task 2).
- Produces: `struct ReflectionEditView: View`.

- [ ] **Step 1: Implement ReflectionEditView**

Create `Sources/UI/ReflectionEditView.swift`:

```swift
import SwiftUI

/// Mask editing + AI removal UI. Shows the corrected image with the mask
/// as a red tint; drags paint (or erase) strokes through DisplayMapper —
/// the same canonical-coordinate discipline as the quad editor.
struct ReflectionEditView: View {
    @Bindable var model: EditorViewModel

    @State private var brushMode: ReflectionMask.Stroke.Mode = .add
    /// Brush radius in DISPLAY points; converted to canonical pixels per
    /// stroke so it feels constant on screen.
    @State private var brushRadiusPoints: CGFloat = 18
    @State private var currentStrokePoints: [CGPoint] = []   // canonical
    @State private var maskOverlay: CGImage?
    @State private var showPending = true

    var body: some View {
        VStack(spacing: 12) {
            imageArea
            controls
        }
        .padding()
        .navigationTitle("Remove Reflections")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear(perform: regenerateOverlay)
        .onChange(of: model.reflectionMask?.strokes.count ?? 0) { _, _ in
            regenerateOverlay()
        }
        .onChange(of: model.reflectionMask?.detectedRaster == nil) { _, _ in
            regenerateOverlay()
        }
    }

    // MARK: Image + mask overlay

    @ViewBuilder
    private var imageArea: some View {
        GeometryReader { proxy in
            if let pending = model.pendingCleaned, showPending {
                fittedImage(pending, in: proxy.size)
                    .overlay(alignment: .top) { compareBadge("After — hold to compare") }
            } else if let pending = model.pendingCleaned, !showPending,
                      let original = model.correctedFullRes {
                fittedImage(original, in: proxy.size)
                    .overlay(alignment: .top) { compareBadge("Before") }
                    .onAppear { _ = pending }   // keep type-checker happy
            } else if let corrected = model.correctedFullRes {
                let mapper = DisplayMapper(
                    imagePixelSize: CGSize(width: corrected.width, height: corrected.height),
                    viewSize: proxy.size
                )
                ZStack {
                    fittedImage(corrected, in: proxy.size)
                    if let maskOverlay {
                        Image(decorative: maskOverlay, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .gesture(brushGesture(mapper: mapper))
            }
        }
    }

    private func fittedImage(_ image: CGImage, in size: CGSize) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size.width, height: size.height)
    }

    private func compareBadge(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .padding(.top, 8)
    }

    private func brushGesture(mapper: DisplayMapper) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                currentStrokePoints.append(mapper.pixelPoint(fromDisplay: value.location))
            }
            .onEnded { _ in
                guard !currentStrokePoints.isEmpty else { return }
                // Convert display-point radius → canonical pixels.
                let pixelsPerPoint = mapper.imagePixelSize.width / max(mapper.fittedRect.width, 1)
                model.addMaskStroke(.init(
                    mode: brushMode,
                    radius: brushRadiusPoints * pixelsPerPoint,
                    points: currentStrokePoints
                ))
                currentStrokePoints = []
            }
    }

    /// Renders the mask as a red-tinted overlay image at preview scale.
    private func regenerateOverlay() {
        guard let mask = model.reflectionMask,
              let corrected = model.correctedFullRes else {
            maskOverlay = nil
            return
        }
        let scale = min(1, 1024 / CGFloat(max(corrected.width, corrected.height)))
        Task.detached(priority: .userInitiated) {
            let overlay = Self.tintedOverlay(mask: mask, scale: scale)
            await MainActor.run { maskOverlay = overlay }
        }
    }

    /// Red 45%-alpha where the mask is white, clear elsewhere.
    nonisolated private static func tintedOverlay(
        mask: ReflectionMask, scale: CGFloat
    ) -> CGImage? {
        guard let raster = mask.rasterize(scale: scale) else { return nil }
        let width = raster.width
        let height = raster.height
        var gray = [UInt8](repeating: 0, count: width * height)
        guard let grayContext = CGContext(
            data: &gray, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        grayContext.draw(raster, in: CGRect(x: 0, y: 0, width: width, height: height))
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) where gray[i] > 127 {
            rgba[i * 4] = 255       // premultiplied red
            rgba[i * 4 + 3] = 115   // ~45% alpha
        }
        return rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return context.makeImage()
        }
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 12) {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if model.pendingCleaned != nil {
                pendingControls
            } else {
                maskEditingControls
            }
        }
    }

    @ViewBuilder
    private var pendingControls: some View {
        Button(showPending ? "Hold to see Before" : "Release for After") {}
            .buttonStyle(.bordered)
            .onLongPressGesture(minimumDuration: .infinity) {
            } onPressingChanged: { pressing in
                showPending = !pressing
            }
        HStack {
            Button("Try Again", role: .cancel) {
                model.discardPendingCleaned()
            }
            Spacer()
            Button("Use This") {
                model.acceptCleaned()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var maskEditingControls: some View {
        Picker("Brush", selection: $brushMode) {
            Text("Mark").tag(ReflectionMask.Stroke.Mode.add)
            Text("Erase").tag(ReflectionMask.Stroke.Mode.erase)
        }
        .pickerStyle(.segmented)

        HStack {
            Image(systemName: "circle.fill").font(.system(size: 8))
            Slider(value: $brushRadiusPoints, in: 6...48)
            Image(systemName: "circle.fill").font(.system(size: 20))
        }
        .accessibilityLabel("Brush size")

        HStack {
            Button("Cancel", role: .cancel) {
                model.exitReflectionRemoval()
            }
            Button("Re-detect") {
                model.redetectReflections()
            }
            .buttonStyle(.bordered)
            Spacer()
            Button {
                Task { await model.runReflectionRemoval() }
            } label: {
                if model.isRemovingReflections {
                    ProgressView()
                } else {
                    Label("Remove", systemImage: "sparkles")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isRemovingReflections
                      || (model.reflectionMask?.isEmpty ?? true))
        }
    }
}
```

- [ ] **Step 2: Entry point in EditorView**

In `Sources/UI/EditorView.swift`, inside `controls` after `MarginControlView(marginPixels: $model.marginPixels)`, add:

```swift
            HStack {
                Button {
                    Task { await model.beginReflectionRemoval() }
                } label: {
                    Label(
                        model.cleanedImage != nil
                            ? "Reflections Removed" : "Remove Reflections",
                        systemImage: model.cleanedImage != nil ? "checkmark.seal" : "sparkles"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(model.quad == nil || !model.settings.isConfigured)
                if !model.settings.isConfigured {
                    Text("Set up an AI provider in Settings")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
```

- [ ] **Step 3: Replace ContentView placeholder**

In `Sources/UI/ContentView.swift`, ensure the stage switch reads:

```swift
                case .reflection:
                    ReflectionEditView(model: model)
```

- [ ] **Step 4: Build + full unit tests**

Run: `xcodegen generate` then
`xcodebuild -project PictureFramer.xcodeproj -scheme PictureFramer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
then full RUN UNIT TESTS.
Expected: BUILD SUCCEEDED, all unit tests PASS.

- [ ] **Step 5: Manual smoke test in simulator**

```sh
xcrun simctl boot "iPhone 17 Pro" || true
xcrun simctl addmedia booted "Design/Test Pictures Reflections/IMG_7666.heic"
# install + launch per CLAUDE.md
```

Verify: gear icon opens Settings; without a key the Remove Reflections button is disabled with hint; with a dummy key the reflection stage opens, the detector proposes a mask over the cyan skylight glare, brushing adds red tint, Remove fails gracefully with a provider error (dummy key → "API key was rejected"). Real end-to-end with a live key is the user's acceptance test.

- [ ] **Step 6: Commit**

```bash
git add Sources/UI/ReflectionEditView.swift Sources/UI/EditorView.swift Sources/UI/ContentView.swift
git commit -m "feat: reflection mask editing UI with AI removal and before/after compare"
```

---

### Task 11: Documentation

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md architecture section**

In the Architecture section, after the `Export` bullet, add:

```markdown
- **Reflection removal** (optional, after correction): `Core/Reflection/ReflectionMaskDetector.swift` proposes a glare mask (bright + unsaturated heuristic, no ML); `Core/Reflection/ReflectionMask.swift` holds proposal + brush strokes and rasterizes at any scale; `Core/Inpainting/ReflectionRemover.swift` crops the mask's padded bbox, sends it to an `InpaintingProvider` (OpenAI `gpt-image-1` via true mask edit, or Gemini 2.5 Flash Image via prompt+mask image), and `PatchCompositor` blends the returned patch back **only inside the mask** — pixels outside the mask are bit-identical (pure CoreGraphics clip-mask compositing; this is the tested fidelity invariant). Provider + API keys configured in `SettingsView`; keys live in the Keychain (`Core/Config/KeychainStore.swift`), never UserDefaults. All provider tests use `Tests/Support/StubURLProtocol.swift` — no live network.
```

In Gotchas, add:

```markdown
- `CGImage.cropping(to:)` takes a TOP-LEFT-origin rect — always crop through `croppedCanonical` (`Core/Inpainting/ImageCoding.swift`), never call `cropping` directly with canonical coords.
- OpenAI's images/edits mask marks repaint regions with TRANSPARENT pixels; app masks are white-=repaint grayscale. `OpenAIInpainter.transparentWhereWhitePNG` converts.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document reflection-removal architecture and gotchas"
```

---

## Self-Review Notes

- Spec coverage: detection (Task 3), mask+brush (Task 2), providers OpenAI/Gemini (Tasks 5–6), compositor fidelity guarantee (Task 4), orchestration (Task 7), pipeline position after correction + export wiring + invalidation (Task 8), settings page with Keychain + validation (Tasks 1, 9), reflection UI with before/after (Task 10), error handling (Tasks 5–8), sRGB/PNG transport (Task 4 helpers), docs (Task 11). Out-of-scope items from the spec are absent by design.
- Ordering: Task 8 (`.reflection` enum case) before Task 9/10 keeps ContentView's switch exhaustive; Task 9 carries a placeholder arm instruction in case of reordering.
- Live-API acceptance (real key, real photo) is intentionally manual — Task 10 Step 5.
```
