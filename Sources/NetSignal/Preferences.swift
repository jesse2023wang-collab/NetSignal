import Foundation

class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let websites = "websites"
        static let autoRefresh = "autoRefresh"
        static let refreshInterval = "refreshInterval"
        static let launchAtLogin = "launchAtLogin"
        static let environmentMode = "environmentMode"
        static let firstLaunch = "firstLaunch"
    }

    @Published var websites: [Website] {
        didSet {
            if let data = try? JSONEncoder().encode(websites) {
                defaults.set(data, forKey: Keys.websites)
            }
        }
    }

    @Published var autoRefresh: Bool {
        didSet { defaults.set(autoRefresh, forKey: Keys.autoRefresh) }
    }

    @Published var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    @Published var environmentMode: EnvironmentMode {
        didSet { defaults.set(environmentMode.rawValue, forKey: Keys.environmentMode) }
    }

    private init() {
        if let data = defaults.data(forKey: Keys.websites),
           let saved = try? JSONDecoder().decode([Website].self, from: data),
           !saved.isEmpty {
            self.websites = saved
        } else {
            self.websites = Website.defaults
        }

        self.autoRefresh = defaults.object(forKey: Keys.autoRefresh) as? Bool ?? true
        self.refreshInterval = defaults.object(forKey: Keys.refreshInterval) as? TimeInterval ?? 60.0
        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false

        if let modeRaw = defaults.string(forKey: Keys.environmentMode),
           let mode = EnvironmentMode(rawValue: modeRaw) {
            self.environmentMode = mode
        } else {
            self.environmentMode = .auto
        }

        if defaults.object(forKey: Keys.firstLaunch) == nil {
            defaults.set(true, forKey: Keys.firstLaunch)
        }
    }

    func resetToDefaults() {
        websites = Website.defaults
        environmentMode = .auto
    }
}
