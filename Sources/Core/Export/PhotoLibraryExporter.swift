import CoreGraphics
import ImageIO
import Photos
import UniformTypeIdentifiers

/// Seam between the exporter and PHPhotoLibrary so authorization and save
/// logic are unit-testable without touching the real photo library.
protocol PhotoLibraryWriting: Sendable {
    func requestAddOnlyAuthorization() async -> PHAuthorizationStatus
    func saveImageData(_ data: Data) async throws
}

/// Thin wrapper over the real photo library. Verified manually — all logic
/// above it is tested against a mock.
struct PHPhotoLibraryWriter: PhotoLibraryWriting {
    func requestAddOnlyAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    }

    func saveImageData(_ data: Data) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
    }
}

struct PhotoLibraryExporter: Sendable {
    enum ExportError: Error, Equatable {
        case notAuthorized
        case encodingFailed
        case saveFailed
    }

    private let library: PhotoLibraryWriting

    init(library: PhotoLibraryWriting = PHPhotoLibraryWriter()) {
        self.library = library
    }

    /// Encodes the image and saves it to the photo library after obtaining
    /// add-only authorization.
    func export(_ image: CGImage) async throws {
        let status = await library.requestAddOnlyAuthorization()
        guard status == .authorized || status == .limited else {
            throw ExportError.notAuthorized
        }
        let data = try encodeJPEG(image)
        do {
            try await library.saveImageData(data)
        } catch {
            throw ExportError.saveFailed
        }
    }

    /// JPEG at high quality — universally readable, no HDR/alpha needs for
    /// photographed paintings.
    func encodeJPEG(_ image: CGImage, quality: CGFloat = 0.95) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw ExportError.encodingFailed
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination), data.length > 0 else {
            throw ExportError.encodingFailed
        }
        return data as Data
    }
}
