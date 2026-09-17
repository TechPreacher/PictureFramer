import Foundation

/// User-selected color scheme. `system` follows the device setting; the
/// UI layer maps the other two onto SwiftUI's `ColorScheme`.
enum AppAppearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    /// UserDefaults key, shared with the `@AppStorage` read at the app root.
    static let defaultsKey = "appAppearance"

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// UserDefaults-backed appearance preference. Unknown or missing values
/// resolve to `.system`.
final class AppearanceStore: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var appearance: AppAppearance {
        get {
            defaults.string(forKey: AppAppearance.defaultsKey)
                .flatMap(AppAppearance.init(rawValue:)) ?? .system
        }
        set { defaults.set(newValue.rawValue, forKey: AppAppearance.defaultsKey) }
    }
}
