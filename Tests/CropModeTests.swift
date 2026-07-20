import Testing
@testable import PictureFramer

struct CropModeTests {

    /// Raw values are the UserDefaults persistence format — renaming a
    /// case must not silently break restored preferences.
    @Test func rawValuesAreStable() {
        #expect(CropMode(rawValue: "framed") == .framed)
        #expect(CropMode(rawValue: "paintingOnly") == .paintingOnly)
        #expect(CropMode(rawValue: "bogus") == nil)
    }
}
