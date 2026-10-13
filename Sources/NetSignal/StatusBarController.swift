import Cocoa

class StatusBarController: NSObject, NetworkMonitorDelegate, NSMenuDelegate {
    private static let environmentOptions: [EnvironmentMode] = [.auto, .global, .domesticOnly]

    private var statusItem: NSStatusItem
    private var timer: Timer?
    private var countdownTimer: Timer?
    private var currentResults: [WebsiteResult] = []
    private var currentQuality: NetworkQuality = .noSignal
    private var isRefreshing = false
    private var lastTestTime: Date = .distantPast
    /// 当前菜单里实际展示的环境（自动模式下由探测结果决定）
    private var displayedEnvironment: EnvironmentMode = .global
    /// 海外站点相关的菜单项，自动模式下按需显隐
    private var overseasItems: [NSMenuItem] = []
    private weak var envMenuItem: NSMenuItem?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = SignalIcon.generateImage(quality: .noSignal)
            button.imagePosition = .imageOnly
            button.toolTip = "NetSignal"
            button.target = self
            button.action = #selector(handleClick)
        }

        NetworkMonitor.shared.delegate = self
        buildMenu()
        startAutoRefresh()

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

    @objc private func websitesDidChange() {
        rebuildMenu()
        lastTestTime = Date()
        NetworkMonitor.shared.testAllWebsites()
    }

    @objc private func autoRefreshDidChange() {
        rebuildMenu()
    }

    @objc private func handleClick(_ sender: Any) {
        guard let menu = self.statusItem.menu else { return }
        if let button = self.statusItem.button, let window = button.window {
            let frame = button.convert(button.bounds, to: nil)
            let screenPoint = window.convertToScreen(frame)
            let menuOrigin = NSPoint(x: screenPoint.minX, y: screenPoint.minY - 5)
            menu.popUp(positioning: nil, at: menuOrigin, in: nil)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = true
        menu.delegate = self
        let prefs = Preferences.shared

        displayedEnvironment = resolvedEnvironment()
        overseasItems = []

        // 状态标题
        let titleItem = NSMenuItem(title: "NetSignal - 真实的网络状态", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        // 网络质量
        let qualityItem = NSMenuItem(title: "网络质量: 检测中...", action: nil, keyEquivalent: "")
        qualityItem.isEnabled = false
        qualityItem.tag = 100
        menu.addItem(qualityItem)
        menu.addItem(NSMenuItem.separator())

        // 国内网站
        let domesticTitle = NSMenuItem(title: "  国内网站", action: nil, keyEquivalent: "")
        domesticTitle.isEnabled = false
        menu.addItem(domesticTitle)

        for website in prefs.websites.filter({ $0.isDomestic && $0.isEnabled }) {
            let item = NSMenuItem(title: "    \(website.name): 等待检测...", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.tag = website.id.hashValue
            menu.addItem(item)
        }

        // 海外网站（全球模式显示；自动模式下先建好，再按探测结果显隐）
        if prefs.environmentMode == .auto || displayedEnvironment == .global {
            let separator = NSMenuItem.separator()
            menu.addItem(separator)
            overseasItems.append(separator)

            let overseasTitle = NSMenuItem(title: "  海外网站", action: nil, keyEquivalent: "")
            overseasTitle.isEnabled = false
            menu.addItem(overseasTitle)
            overseasItems.append(overseasTitle)

            for website in prefs.websites.filter({ !$0.isDomestic && $0.isEnabled }) {
                let item = NSMenuItem(title: "    \(website.name): 等待检测...", action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.tag = website.id.hashValue
                menu.addItem(item)
                overseasItems.append(item)
            }

            updateOverseasVisibility()
        }

        menu.addItem(NSMenuItem.separator())

        // 下一次刷新倒计时（仅在自动刷新开启时显示）
        let countdownItem = NSMenuItem(title: "下一次刷新", action: nil, keyEquivalent: "")
        countdownItem.isEnabled = false
        countdownItem.tag = 200
        countdownItem.isHidden = !Preferences.shared.autoRefresh
        menu.addItem(countdownItem)

        // 立即刷新
        let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        // 环境切换子菜单
        let envMenu = NSMenu()
        for (index, mode) in Self.environmentOptions.enumerated() {
            let item = NSMenuItem(title: mode.description, action: #selector(setEnvironmentMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = prefs.environmentMode == mode ? .on : .off
            envMenu.addItem(item)
        }

        // 环境切换 — 状态文字灰色且靠近 ▸
        let envAttr = NSMutableAttributedString(string: "环境切换")
        envAttr.append(NSAttributedString(string: "  \(environmentStatusText())", attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
        let envItem = NSMenuItem()
        envItem.attributedTitle = envAttr
        envItem.submenu = envMenu
        menu.addItem(envItem)
        envMenuItem = envItem

        menu.addItem(NSMenuItem.separator())

        // 设置
        let settingsItem = NSMenuItem(title: "设置...", action: #selector(settingsClicked), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // 关于
        let aboutItem = NSMenuItem(title: "关于", action: #selector(aboutClicked), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        // 检查更新
        let updateItem = NSMenuItem(title: "检查更新", action: #selector(updateClicked), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        // 退出
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        menu.delegate = self
    }

    private func resolvedEnvironment() -> EnvironmentMode {
        let mode = Preferences.shared.environmentMode
        return mode == .auto ? (NetworkMonitor.shared.effectiveMode ?? .global) : mode
    }

    private func environmentStatusText() -> String {
        let mode = Preferences.shared.environmentMode
        guard mode == .auto, let detected = NetworkMonitor.shared.effectiveMode else {
            return mode.description
        }
        return "自动·\(detected.description)"
    }

    private func updateOverseasVisibility() {
        let hidden = displayedEnvironment != .global
        for item in overseasItems {
            item.isHidden = hidden
        }
    }

    private func updateMenuItems() {
        guard let menu = statusItem.menu else { return }

        let newEnvironment = resolvedEnvironment()
        if newEnvironment != displayedEnvironment {
            displayedEnvironment = newEnvironment
            updateOverseasVisibility()
        }

        if let envItem = envMenuItem {
            let attr = NSMutableAttributedString(string: "环境切换")
            attr.append(NSAttributedString(string: "  \(environmentStatusText())", attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
            envItem.attributedTitle = attr
        }

        if let qualityItem = menu.item(withTag: 100) {
            let qualityText = isRefreshing ? "检测中..." : currentQuality.description
            qualityItem.title = "网络质量: \(qualityText)"
        }

        for result in currentResults {
            let tag = result.website.id.hashValue
            if let menuItem = menu.item(withTag: tag) {
                if result.status == .timeout {
                    menuItem.title = "    \(result.website.name): 超时"
                    menuItem.attributedTitle = NSAttributedString(
                        string: "    \(result.website.name): 超时",
                        attributes: [.foregroundColor: NSColor.systemGray]
                    )
                } else {
                    let timeStr = String(format: "%.0fms", result.responseTime)
                    menuItem.title = "    \(result.website.name): \(timeStr)"
                    let color = NSColor.fromHex(result.status.colorHex)
                    menuItem.attributedTitle = NSAttributedString(
                        string: "    \(result.website.name): \(timeStr)",
                        attributes: [.foregroundColor: color]
                    )
                }
                menuItem.isEnabled = false
            }
        }
    }

    private func startAutoRefresh() {
        timer?.invalidate()
        guard Preferences.shared.autoRefresh else { return }
        let interval = Preferences.shared.refreshInterval
        lastTestTime = Date()
        let refreshTimer = Timer(timeInterval: interval, repeats: true) { _ in
            NetworkMonitor.shared.testAllWebsites()
        }
        // 菜单打开时 RunLoop 跑在 eventTracking 模式，.default 模式的定时器不会触发
        RunLoop.main.add(refreshTimer, forMode: .common)
        timer = refreshTimer
        NetworkMonitor.shared.testAllWebsites()
    }

    // MARK: - NetworkMonitorDelegate

    func networkMonitorDidStartTesting() {
        isRefreshing = true
        lastTestTime = Date()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // 检测期间保持图标不变，不重置为 noSignal
            self.updateMenuItems()
        }
    }

    func networkMonitorDidUpdate(results: [WebsiteResult], quality: NetworkQuality) {
        isRefreshing = false
        currentResults = results
        currentQuality = quality

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.statusItem.button?.image = SignalIcon.generateImage(quality: quality)
            self.updateMenuItems()
        }
    }

    // MARK: - Actions

    @objc private func refreshClicked() {
        lastTestTime = Date()
        NetworkMonitor.shared.testAllWebsites()
    }

    @objc private func setEnvironmentMode(_ sender: NSMenuItem) {
        let options = Self.environmentOptions
        guard sender.tag >= 0, sender.tag < options.count else { return }
        let mode = options[sender.tag]
        guard Preferences.shared.environmentMode != mode else { return }

        Preferences.shared.environmentMode = mode
        rebuildMenu()
        lastTestTime = Date()
        NetworkMonitor.shared.testAllWebsites()
    }

    private func rebuildMenu() {
        statusItem.menu = nil
        buildMenu()
    }

    @objc private func settingsClicked() {
        SettingsWindowController.shared.showWindow()
    }

    @objc private func aboutClicked() {
        let alert = NSAlert()
        alert.messageText = "NetSignal"
        alert.informativeText = "版本 1.0.3\n\n网络状态监测工具\n通过监测国内外主要网站访问速度，直观反映当前网络状态。"
        alert.alertStyle = .informational
        alert.icon = appIcon()
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    private func appIcon() -> NSImage {
          return SignalIcon.drawAppIcon()
      }

    @objc private func updateClicked() {
        UpdateChecker.shared.checkForUpdate()
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension StatusBarController {
    func menuWillOpen(_ menu: NSMenu) {
        startMenuCountdown()
    }

    func menuDidClose(_ menu: NSMenu) {
        stopMenuCountdown()
    }

    private func startMenuCountdown() {
        stopMenuCountdown()
        updateCountdownItem()
        let ticker = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateCountdownItem()
        }
        // 菜单打开期间 RunLoop 处于 eventTracking 模式，必须注册到 .common 才会每秒跳动
        RunLoop.main.add(ticker, forMode: .common)
        countdownTimer = ticker
    }

    private func stopMenuCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func updateCountdownItem() {
        guard let menu = statusItem.menu,
              let item = menu.item(withTag: 200) else { return }
        let prefs = Preferences.shared
        guard prefs.autoRefresh else {
            item.isHidden = true
            return
        }
        item.isHidden = false

        let interval = prefs.refreshInterval
        let elapsed = Date().timeIntervalSince(lastTestTime)
        let remaining = max(0, interval - elapsed)
        let seconds = max(1, Int(ceil(remaining)))
        let text = "下一次刷新  \(seconds)秒"
        item.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.foregroundColor: NSColor.secondaryLabelColor]
        )
    }
}

extension NSColor {
    static func fromHex(_ hex: String) -> NSColor {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0
        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }
}
