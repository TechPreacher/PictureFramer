import SwiftUI

@main
struct PictureFramerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear { AppearanceApplier.apply(AppearanceStore().appearance) }
        }
    }
}
