import CoreGraphics
import Foundation
import ImageIO
import Photos
import Testing
@testable import PictureFramer

/// Mock photo library that records calls instead of touching PHPhotoLibrary.
final class MockPhotoLibrary: PhotoLibraryWriting, @unchecked Sendable {
    var authorizationStatus: PHAuthorizationStatus
    var saveError: Error?
    private(set) var saveCallCount = 0
    private(set) var savedData: Data?

    init(authorizationStatus: PHAuthorizationStatus) {
        self.authorizationStatus = authorizationStatus
    }

    func requestAddOnlyAuthorization() async -> PHAuthorizationStatus {
        authorizationStatus
    }

    func saveImageData(_ data: Data) async throws {
        saveCallCount += 1
        savedData = data
        if let saveError { throw saveError }
    }
}

struct PhotoLibraryExporterTests {

    private let image = FixtureImageFactory.solidImage(size: CGSize(width: 320, height: 240))

    @Test(arguments: [PHAuthorizationStatus.denied, .restricted, .notDetermined])
    func unauthorizedThrowsAndNeverSaves(status: PHAuthorizationStatus) async {
        let library = MockPhotoLibrary(authorizationStatus: status)
        let exporter = PhotoLibraryExporter(library: library)
        await #expect(throws: PhotoLibraryExporter.ExportError.notAuthorized) {
            try await exporter.export(image)
        }
        #expect(library.saveCallCount == 0)
    }

    @Test(arguments: [PHAuthorizationStatus.authorized, .limited])
    func authorizedSavesExactlyOnce(status: PHAuthorizationStatus) async throws {
        let library = MockPhotoLibrary(authorizationStatus: status)
        let exporter = PhotoLibraryExporter(library: library)
        try await exporter.export(image)
        #expect(library.saveCallCount == 1)
        #expect((library.savedData?.count ?? 0) > 0)
    }

    @Test func saveFailureSurfacesAsSaveFailed() async {
        let library = MockPhotoLibrary(authorizationStatus: .authorized)
        library.saveError = NSError(domain: "test", code: 1)
        let exporter = PhotoLibraryExporter(library: library)
        await #expect(throws: PhotoLibraryExporter.ExportError.saveFailed) {
            try await exporter.export(image)
        }
    }

    @Test func encodedJPEGRoundTripsWithSameDimensions() throws {
        let exporter = PhotoLibraryExporter(library: MockPhotoLibrary(authorizationStatus: .authorized))
        let source = FixtureImageFactory.image(
            size: CGSize(width: 640, height: 480),
            quad: FixtureImageFactory.axisAlignedQuad(
                in: CGSize(width: 640, height: 480), inset: 80
            )
        )
        let data = try exporter.encodeJPEG(source)
        let decoded = CGImageSourceCreateWithData(data as CFData, nil)
            .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        #expect(decoded?.width == 640)
        #expect(decoded?.height == 480)
    }
}
