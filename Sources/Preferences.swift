import SwiftUI

enum DisplayMode: String, CaseIterable, Identifiable {
    case wallpaper, window

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wallpaper: "Desktop Wallpaper"
        case .window: "Window"
        }
    }
}

enum SceneTheme: String, CaseIterable, Identifiable {
    case daylight, midnight, bare

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daylight: "Daylight"
        case .midnight: "Midnight"
        case .bare: "Turntable Only"
        }
    }
}

enum SceneSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var dimensions: CGSize {
        switch self {
        case .small: CGSize(width: 560, height: 350)
        case .medium: CGSize(width: 800, height: 500)
        case .large: CGSize(width: 1200, height: 750)
        }
    }
}

final class Preferences: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var display: DisplayMode { didSet { defaults.set(display.rawValue, forKey: "display") } }
    @Published var theme: SceneTheme { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    @Published var size: SceneSize { didSet { defaults.set(size.rawValue, forKey: "size") } }
    @Published var floating: Bool { didSet { defaults.set(floating, forKey: "floating") } }
    /// Whether the introduction has been shown, which happens once, on first launch.
    var welcomed: Bool {
        get { defaults.bool(forKey: "welcomed") }
        set { defaults.set(newValue, forKey: "welcomed") }
    }

    init() {
        display = defaults.string(forKey: "display").flatMap(DisplayMode.init) ?? .wallpaper
        theme = defaults.string(forKey: "theme").flatMap(SceneTheme.init) ?? .daylight
        size = defaults.string(forKey: "size").flatMap(SceneSize.init) ?? .medium
        floating = defaults.bool(forKey: "floating")
    }
}
