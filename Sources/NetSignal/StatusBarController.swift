import Cocoa

class StatusBarController: NSObject, NetworkMonitorDelegate, PopoverViewControllerDelegate {
    private var statusItem: NSStatusItem
    private var popoverVC: PopoverViewController!

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let prefs = Preferences.shared
            button.image = SignalIcon.generateImage(quality: .noSignal, colorful: prefs.useColorfulIcon)
            button.imagePosition = .imageOnly
            button.toolTip = "NetSignal"
            button.target = self
            button.action = #selector(handleClick)
        }

        popoverVC = PopoverViewController()
        popoverVC.delegate = self

        NetworkMonitor.shared.delegate = self

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iconStyleDidChange),
            name: .iconStyleChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(websitesDidChange),
            name: .websitesDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(autoRefreshDidChange),
            name: .autoRefreshChanged,
            object: nil
        )
    }

    // MARK: - Status Bar Click

    @objc private func handleClick(_ sender: Any) {
        guard let button = statusItem.button else { return }
        popoverVC.toggle(relativeTo: button)
    }

    // MARK: - PopoverViewControllerDelegate

    func popoverDidRequestRefresh() {
        popoverVC.resetCountdown()
        NetworkMonitor.shared.testAllWebsites()
    }

    func popoverDidChangeEnvironment(to mode: EnvironmentMode) {
        Preferences.shared.environmentMode = mode
        popoverVC.updateEnvironmentDisplay()
        popoverVC.resetCountdown()
        NetworkMonitor.shared.testAllWebsites()
    }

    func popoverDidRequestSettings() {
        // Settings are now shown within the popover, handled by PopoverViewController
    }

    // MARK: - NetworkMonitorDelegate

    func networkMonitorDidStartTesting() {
        popoverVC.updateTesting()
    }

    func networkMonitorDidUpdate(results: [WebsiteResult], quality: NetworkQuality) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let prefs = Preferences.shared
            self.statusItem.button?.image = SignalIcon.generateImage(quality: quality, colorful: prefs.useColorfulIcon)
            self.popoverVC.updateResults(results: results, quality: quality)
        }
    }

    // MARK: - Notifications

    @objc private func iconStyleDidChange() {
        let prefs = Preferences.shared
        statusItem.button?.image = SignalIcon.generateImage(quality: .noSignal, colorful: prefs.useColorfulIcon)
    }

    @objc private func websitesDidChange() {
        popoverVC.reloadSettings()
        popoverVC.resetCountdown()
        NetworkMonitor.shared.testAllWebsites()
    }

    @objc private func autoRefreshDidChange() {
        popoverVC.restartTimers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
