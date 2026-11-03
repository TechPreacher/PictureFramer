import Foundation
import Testing
@testable import PictureFramer

@Suite struct CameraCaptureErrorTests {
    @Test func notConfiguredSaysTheCameraIsNotReady() throws {
        let description = try #require(CameraCaptureError.notConfigured.errorDescription)
        #expect(description.localizedCaseInsensitiveContains("not configured"))
    }

    @Test func captureInProgressSaysAnotherCaptureIsRunning() throws {
        let description = try #require(CameraCaptureError.captureInProgress.errorDescription)
        #expect(description.localizedCaseInsensitiveContains("in progress"))
    }

    @Test func captureErrorCarriesDomainCodeAndMessage() throws {
        let underlying = NSError(
            domain: AVFoundationErrorDomainForTests.domain, code: -11800,
            userInfo: [NSLocalizedDescriptionKey: "The operation could not be completed"])
        let description = try #require(CameraCaptureError.capture(underlying: underlying).errorDescription)
        #expect(description.contains(AVFoundationErrorDomainForTests.domain))
        #expect(description.contains("-11800"))
        #expect(description.contains("The operation could not be completed"))
    }

    @Test func noImageDataSaysThePhotoHadNoData() throws {
        let description = try #require(CameraCaptureError.noImageData.errorDescription)
        #expect(description.localizedCaseInsensitiveContains("no image data"))
    }

    @Test func casesHaveDistinctDescriptions() {
        let underlying = NSError(domain: "D", code: 1)
        let descriptions: [String?] = [
            CameraCaptureError.notConfigured.errorDescription,
            CameraCaptureError.captureInProgress.errorDescription,
            CameraCaptureError.capture(underlying: underlying).errorDescription,
            CameraCaptureError.noImageData.errorDescription,
        ]
        #expect(Set(descriptions.compactMap { $0 }).count == 4)
    }
}

/// Literal domain string so the test stays Foundation-only (no AVFoundation import).
private enum AVFoundationErrorDomainForTests {
    static let domain = "AVFoundationErrorDomain"
}
