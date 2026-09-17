import SwiftUI
import UIKit

extension AppAppearance {
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Applies the user's appearance choice to every window of the app.
///
/// Uses UIKit's `overrideUserInterfaceStyle` instead of SwiftUI's
/// `preferredColorScheme`: the latter is a view preference, and once a
/// presented sheet (Settings) has published its own value, later changes
/// from the root are not reliably re-applied. A window-level override
/// covers the root, sheets, alerts and UIKit-presented pickers alike.
@MainActor
enum AppearanceApplier {
    static func apply(_ appearance: AppAppearance) {
        let style = appearance.interfaceStyle
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
