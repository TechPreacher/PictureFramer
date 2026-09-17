import Foundation
import Testing
@testable import PictureFramer

@Suite struct AppAppearanceTests {

    private func makeStore() -> (AppearanceStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "AppAppearanceTests-\(UUID().uuidString)")!
        return (AppearanceStore(defaults: defaults), defaults)
    }

    /// Raw values are the UserDefaults persistence format — renaming a
    /// case must not silently break restored preferences.
    @Test func rawValuesAreStable() {
        #expect(AppAppearance(rawValue: "system") == .system)
        #expect(AppAppearance(rawValue: "light") == .light)
        #expect(AppAppearance(rawValue: "dark") == .dark)
        #expect(AppAppearance(rawValue: "bogus") == nil)
    }

    @Test func defaultsToSystem() {
        let (store, _) = makeStore()
        #expect(store.appearance == .system)
    }

    @Test func roundTrips() {
        let (store, defaults) = makeStore()
        store.appearance = .dark
        #expect(store.appearance == .dark)
        #expect(defaults.string(forKey: AppAppearance.defaultsKey) == "dark")
        store.appearance = .light
        #expect(store.appearance == .light)
    }

    @Test func unknownStoredValueFallsBackToSystem() {
        let (store, defaults) = makeStore()
        defaults.set("sepia", forKey: AppAppearance.defaultsKey)
        #expect(store.appearance == .system)
    }

    @Test func displayNamesAreDistinct() {
        let names = Set(AppAppearance.allCases.map(\.displayName))
        #expect(names.count == AppAppearance.allCases.count)
    }
}
