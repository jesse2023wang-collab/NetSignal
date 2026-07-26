import Cocoa

// MARK: - FlippedView

class FlippedView: NSView {
    override var isFlipped: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        // Dynamic colors resolve at draw time via .cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Force layer to re-resolve dynamic NSColor.cgColor
        setNeedsDisplay(bounds)
        needsDisplay = true
    }
}

// MARK: - PopoverViewControllerDelegate

protocol PopoverViewControllerDelegate: AnyObject {
    func popoverDidRequestRefresh()
    func popoverDidChangeEnvironment(to mode: EnvironmentMode)
    func popoverDidRequestSettings()
}

// MARK: - PopoverViewController

class PopoverViewController {
    weak var delegate: PopoverViewControllerDelegate?

    let popover: NSPopover
    private let rootVC: NSViewController
    private let dashboardView: DashboardView
    private let settingsView: SettingsPopoverView

    private var countdownTimer: Timer?
    private var autoRefreshTimer: Timer?
    private var lastTestTime: Date = .distantPast

    init() {
        popover = NSPopover()
        rootVC = NSViewController()
        dashboardView = DashboardView(frame: NSRect(x: 0, y: 0, width: NSDesignLayout.popoverWidth, height: 500))
        settingsView = SettingsPopoverView(frame: NSRect(x: 0, y: 0, width: NSDesignLayout.popoverWidth, height: 500))

        popover.contentViewController = rootVC
        popover.contentSize = NSSize(width: NSDesignLayout.popoverWidth, height: 500)
        popover.behavior = .transient
        popover.animates = true

        setupView()
        dashboardView.delegate = self
        settingsView.settingsDelegate = self
        startAutoRefresh()
        startCountdown()
    }

    private func setupView() {
        let container = FlippedView(frame: NSRect(x: 0, y: 0, width: NSDesignLayout.popoverWidth, height: 500))
        container.wantsLayer = true

        container.addSubview(dashboardView)
        container.addSubview(settingsView)
        settingsView.isHidden = true

        rootVC.view = container

        // Observe system theme changes to update dynamic colors
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // Rebuild everything with current appearance
            self.dashboardView.rebuildForAppearanceChange()
            if !self.settingsView.isHidden {
                self.settingsView.reload()
            }
        }
    }

    private var container: FlippedView? { rootVC.view as? FlippedView }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.close()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
        }
    }

    func resetCountdown() {
        lastTestTime = Date()
        startCountdown()
    }

    private func startCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard Preferences.shared.autoRefresh else {
                self.dashboardView.updateCountdown(text: "自动刷新已关闭")
                return
            }
            let remaining = max(0, Preferences.shared.refreshInterval - Date().timeIntervalSince(self.lastTestTime))
            self.dashboardView.updateCountdown(text: "\(Int(ceil(remaining)))秒后刷新")
        }
    }

    private func startAutoRefresh() {
        autoRefreshTimer?.invalidate()
        guard Preferences.shared.autoRefresh else { return }
        lastTestTime = Date()
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: Preferences.shared.refreshInterval, repeats: true) { [weak self] _ in
            self?.delegate?.popoverDidRequestRefresh()
        }
    }

    func restartTimers() { resetCountdown(); startAutoRefresh() }
    func updateResults(results: [WebsiteResult], quality: NetworkQuality) { dashboardView.updateResults(results: results, quality: quality); resetCountdown() }
    func updateTesting() { dashboardView.updateTesting() }
    func reloadSettings() { settingsView.reload() }
    func updateEnvironmentDisplay() { dashboardView.updateEnvToggle(mode: Preferences.shared.environmentMode) }
}

// MARK: - Dashboard Delegates

extension PopoverViewController: DashboardViewDelegate {
    func dashboardDidRequestRefresh() { lastTestTime = Date(); delegate?.popoverDidRequestRefresh() }
    func dashboardDidChangeEnvironment(to mode: EnvironmentMode) { delegate?.popoverDidChangeEnvironment(to: mode); lastTestTime = Date() }
    func dashboardDidRequestSettings() { settingsView.reload(); dashboardView.isHidden = true; settingsView.isHidden = false }
}

extension PopoverViewController: SettingsPopoverViewDelegate {
    func settingsDidRequestBack() { settingsView.isHidden = true; dashboardView.isHidden = false }
    func settingsDidAddWebsite() { lastTestTime = Date() }
    func settingsDidChangeWebsites() { lastTestTime = Date() }
    func settingsDidChangeAutoRefresh() { startAutoRefresh(); startCountdown() }
}

// MARK: - DashboardViewDelegate

protocol DashboardViewDelegate: AnyObject {
    func dashboardDidRequestRefresh()
    func dashboardDidChangeEnvironment(to mode: EnvironmentMode)
    func dashboardDidRequestSettings()
}

// MARK: - DashboardView

class DashboardView: NSView {
    weak var delegate: DashboardViewDelegate?

    private let W = NSDesignLayout.popoverWidth
    private let P = NSDesignLayout.horizontalPadding

    private var siteRows: [String: SiteRowView] = [:]
    private var envToggle: EnvToggle!
    private var qualityLabel: NSTextField!
    private var qualityIcon: SignalBarsView!
    private var avgLabel: NSTextField!
    private var countdownLabel: NSTextField!
    private var refreshBtn: NSButton!
    private var scrollContent: FlippedView!
    private var scrollView: NSScrollView!
    private var fixedTop: NSView!

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        buildUI()
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = NSColor.nsBackgroundDefault.cgColor
        fixedTop?.layer?.backgroundColor = NSColor.nsBackgroundDefault.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Refresh all dynamic colors
        rebuildSiteSections()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Build UI

    private func buildUI() {
        // Fixed top container (added LAST for correct z-order)
        fixedTop = FlippedView(frame: NSRect(x: 0, y: 0, width: W, height: 0))
        fixedTop.wantsLayer = true
        fixedTop.layer?.backgroundColor = NSColor.nsBackgroundDefault.cgColor

        var ty: CGFloat = 0

        // --- Header ---
        let headerH: CGFloat = 44
        let header = FlippedView(frame: NSRect(x: 0, y: ty, width: W, height: headerH))

        let icon = SignalBarsView(lit: 3, total: 4, size: NSSize(width: 16, height: 16),
                                   activeColor: .nsGrey800, inactiveColor: .nsTextDisabled)
        icon.frame = NSRect(x: P, y: (headerH - 16) / 2, width: 16, height: 16)
        header.addSubview(icon)

        let title = makeLabel("NetSignal", font: NSDesignFont.title, color: .nsTextDefault)
        title.frame = NSRect(x: P + 22, y: (headerH - 16) / 2, width: 80, height: 16)
        header.addSubview(title)

        let settingsBtn = NSButton(frame: NSRect(x: W - P - 28 - 80, y: (headerH - 28) / 2, width: 28, height: 28))
        settingsBtn.bezelStyle = .inline
        settingsBtn.isBordered = false
        settingsBtn.wantsLayer = true
        settingsBtn.image = makeGearIcon()
        settingsBtn.imagePosition = .imageOnly
        settingsBtn.target = self
        settingsBtn.action = #selector(settingsClicked)
        header.addSubview(settingsBtn)

        envToggle = EnvToggle(frame: NSRect(x: W - P - 76, y: (headerH - 24) / 2, width: 76, height: 24))
        envToggle.selectedMode = Preferences.shared.environmentMode
        envToggle.target = self
        envToggle.action = #selector(envChanged)
        header.addSubview(envToggle)

        fixedTop.addSubview(header)
        ty += headerH

        fixedTop.addSubview(makeDivider(at: ty))
        ty += 0.5

        // --- Quality Summary ---
        let qualityH: CGFloat = 36
        let qualityView = FlippedView(frame: NSRect(x: 0, y: ty, width: W, height: qualityH))

        qualityIcon = SignalBarsView(lit: 0, total: 4, size: NSSize(width: 18, height: 18),
                                      activeColor: .nsGrey300, inactiveColor: .nsGrey300)
        qualityIcon.frame = NSRect(x: P, y: (qualityH - 18) / 2, width: 18, height: 18)
        qualityView.addSubview(qualityIcon)

        qualityLabel = makeLabel("检测中...", font: NSFont.systemFont(ofSize: 12, weight: .semibold), color: .nsTextDefault)
        qualityLabel.frame = NSRect(x: P + 26, y: (qualityH - 14) / 2, width: 120, height: 14)
        qualityView.addSubview(qualityLabel)

        avgLabel = makeLabel("", font: NSDesignFont.caption, color: .nsTextSecondary)
        avgLabel.frame = NSRect(x: W - P - 80, y: (qualityH - 14) / 2, width: 80, height: 14)
        avgLabel.alignment = .right
        qualityView.addSubview(avgLabel)

        fixedTop.addSubview(qualityView)
        ty += qualityH

        fixedTop.addSubview(makeDivider(at: ty))
        ty += 0.5

        // --- Countdown ---
        let cdH: CGFloat = 30
        let cdView = FlippedView(frame: NSRect(x: 0, y: ty, width: W, height: cdH))

        countdownLabel = makeLabel("刷新中...", font: NSDesignFont.caption, color: .nsTextTertiary)
        countdownLabel.frame = NSRect(x: P, y: (cdH - 14) / 2, width: 160, height: 14)
        cdView.addSubview(countdownLabel)

        refreshBtn = NSButton(frame: NSRect(x: W - P - 60, y: (cdH - 20) / 2, width: 60, height: 20))
        refreshBtn.title = "立即刷新"
        refreshBtn.bezelStyle = .inline
        refreshBtn.wantsLayer = true
        refreshBtn.layer?.backgroundColor = NSColor.nsBackgroundTertiary.cgColor
        refreshBtn.layer?.cornerRadius = 4
        refreshBtn.font = NSDesignFont.button
        refreshBtn.isBordered = false
        refreshBtn.target = self
        refreshBtn.action = #selector(refreshClicked)
        cdView.addSubview(refreshBtn)

        fixedTop.addSubview(cdView)
        ty += cdH

        // Set fixed top total height
        fixedTop.frame = NSRect(x: 0, y: 0, width: W, height: ty)

        // --- Scroll View (added FIRST = bottom z-order, behind fixedTop) ---
        let scrollFrame = NSRect(x: 0, y: ty, width: W, height: bounds.height - ty)
        scrollView = NSScrollView(frame: scrollFrame)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        scrollContent = FlippedView(frame: NSRect(x: 0, y: 0, width: W, height: 400))
        scrollContent.wantsLayer = true

        rebuildSiteSections()
        scrollView.documentView = scrollContent

        addSubview(scrollView)   // bottom z-order
        addSubview(fixedTop)     // top z-order, painted above scrollView
    }

    // MARK: - Build Site Sections

    private func rebuildSiteSections() {
        scrollContent.subviews.forEach { $0.removeFromSuperview() }
        siteRows.removeAll()

        var sy: CGFloat = 0
        let prefs = Preferences.shared

        let domestic = prefs.websites.filter { $0.isDomestic && $0.isEnabled }
        if !domestic.isEmpty {
            sy = addSection(title: "国内网站", sites: domestic, y: sy)
        }

        if prefs.environmentMode == .global {
            let overseas = prefs.websites.filter { !$0.isDomestic && $0.isEnabled }
            if !overseas.isEmpty {
                sy += 4
                sy = addSection(title: "海外网站", sites: overseas, y: sy)
            }
        }

        sy += 8
        sy = addFooter(y: sy)
        sy += 8

        scrollContent.frame = NSRect(x: 0, y: 0, width: W, height: max(sy, scrollView.frame.height))
    }

    private func addSection(title: String, sites: [Website], y: CGFloat) -> CGFloat {
        var sy = y

        let header = makeLabel(title, font: NSDesignFont.sectionHeading, color: .nsTextTertiary)
        header.frame = NSRect(x: P, y: sy + 4, width: 200, height: 14)
        scrollContent.addSubview(header)
        sy += 22

        for site in sites {
            let row = SiteRowView(frame: NSRect(x: 4, y: sy, width: W - 8, height: 29))
            row.siteName = site.name
            scrollContent.addSubview(row)
            siteRows[site.name] = row
            sy += 29
        }
        return sy + 4
    }

    private func addFooter(y: CGFloat) -> CGFloat {
        let footerH: CGFloat = 28

        let footer = FlippedView(frame: NSRect(x: 0, y: y, width: W, height: footerH))

        let div = NSView(frame: NSRect(x: 0, y: 0, width: W, height: 0.5))
        div.wantsLayer = true
        div.layer?.backgroundColor = NSColor.nsBorderNeutral.cgColor
        footer.addSubview(div)

        let items: [(NSColor, String)] = [
            (.nsStatusSuccess, "<500ms"),
            (.nsStatusWarning, "500-1500ms"),
            (.nsStatusError, ">1500ms")
        ]
        let startX = (W - 240) / 2

        for (i, item) in items.enumerated() {
            let fx = startX + CGFloat(i) * 80
            let dot = NSView(frame: NSRect(x: fx, y: (footerH - 6) / 2, width: 6, height: 6))
            dot.wantsLayer = true
            dot.layer?.backgroundColor = item.0.cgColor
            dot.layer?.cornerRadius = 3
            footer.addSubview(dot)

            let label = makeLabel(item.1, font: NSDesignFont.legend, color: .nsTextTertiary)
            label.frame = NSRect(x: fx + 10, y: (footerH - 12) / 2, width: 60, height: 12)
            footer.addSubview(label)
        }

        scrollContent.addSubview(footer)
        var retY = y + footerH

        // Divider
        let div2 = NSView(frame: NSRect(x: 0, y: retY, width: W, height: 0.5))
        div2.wantsLayer = true
        div2.layer?.backgroundColor = NSColor.nsBorderNeutral.cgColor
        scrollContent.addSubview(div2)
        retY += 0.5

        // Quit button
        let quitBtn = NSButton(frame: NSRect(x: P, y: retY, width: W - 2 * P, height: 32))
        quitBtn.title = "退出 NetSignal"
        quitBtn.bezelStyle = .inline
        quitBtn.isBordered = false
        quitBtn.wantsLayer = true
        quitBtn.font = NSDesignFont.body
        quitBtn.contentTintColor = .nsStatusError
        quitBtn.target = self
        quitBtn.action = #selector(quitClicked)
        scrollContent.addSubview(quitBtn)
        retY += 32

        return retY
    }

    @objc private func quitClicked() { NSApp.terminate(nil) }

    // MARK: - Updates

    func updateResults(results: [WebsiteResult], quality: NetworkQuality) {
        qualityLabel.stringValue = quality.description

        let valid = results.filter { $0.status != .timeout }
        if !valid.isEmpty {
            let avg = valid.map { $0.responseTime }.reduce(0, +) / Double(valid.count)
            avgLabel.stringValue = String(format: "平均 %.0fms", avg)
        } else {
            avgLabel.stringValue = "无数据"
        }

        // Update quality icon
        qualityIcon.removeFromSuperview()
        let color: NSColor = quality.rawValue >= 3 ? .nsStatusSuccess :
                             quality.rawValue >= 2 ? .nsStatusWarning :
                             quality.rawValue >= 1 ? .nsStatusError : .nsGrey300
        let newIcon = SignalBarsView(lit: quality.rawValue, total: 4, size: NSSize(width: 18, height: 18),
                                      activeColor: color, inactiveColor: .nsGrey300)
        newIcon.frame = qualityIcon.frame
        qualityIcon.superview?.addSubview(newIcon)
        qualityIcon = newIcon

        for result in results {
            siteRows[result.website.name]?.update(result: result)
        }

        refreshBtn.title = "立即刷新"
        refreshBtn.alphaValue = 1.0
        refreshBtn.isEnabled = true
    }

    func updateTesting() {
        qualityLabel.stringValue = "检测中..."
        refreshBtn.title = "刷新中..."
        refreshBtn.alphaValue = 0.5
        refreshBtn.isEnabled = false
    }

    func updateCountdown(text: String) { countdownLabel.stringValue = text }
    func updateEnvToggle(mode: EnvironmentMode) { envToggle.selectedMode = mode }

    func rebuildForAppearanceChange() {
        // Re-apply all dynamic colors by updating layers
        layer?.backgroundColor = NSColor.nsBackgroundDefault.cgColor
        fixedTop?.layer?.backgroundColor = NSColor.nsBackgroundDefault.cgColor
        envToggle.updateForAppearance()
        rebuildSiteSections()
    }

    // MARK: - Actions

    @objc private func settingsClicked() { delegate?.dashboardDidRequestSettings() }

    @objc private func envChanged() {
        let mode = envToggle.selectedMode
        Preferences.shared.environmentMode = mode
        rebuildSiteSections()
        delegate?.dashboardDidChangeEnvironment(to: mode)
    }

    @objc private func refreshClicked() { delegate?.dashboardDidRequestRefresh() }

    // MARK: - Helpers

    private func makeLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = font; l.textColor = color
        l.isEditable = false; l.isBordered = false; l.drawsBackground = false
        return l
    }

    private func makeDivider(at y: CGFloat) -> NSView {
        let d = NSView(frame: NSRect(x: 0, y: y, width: W, height: 0.5))
        d.wantsLayer = true
        d.layer?.backgroundColor = NSColor.nsBorderNeutral.cgColor
        return d
    }

    private func makeGearIcon() -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.nsIconTertiary.setStroke()
        let circle = NSBezierPath()
        circle.appendOval(in: NSRect(x: 4, y: 4, width: 6, height: 6))
        circle.stroke()
        for i in 0..<8 {
            let a = CGFloat(i) * .pi / 4
            let line = NSBezierPath()
            line.lineWidth = 1.8
            line.move(to: NSPoint(x: 7 + cos(a) * 3.5, y: 7 + sin(a) * 3.5))
            line.line(to: NSPoint(x: 7 + cos(a) * 5.5, y: 7 + sin(a) * 5.5))
            line.stroke()
        }
        image.unlockFocus()
        return image
    }
}

// MARK: - SignalBarsView

class SignalBarsView: NSView {
    private let lit: Int
    private let total: Int
    private let barSize: NSSize
    private let activeColor: NSColor
    private let inactiveColor: NSColor

    init(lit: Int, total: Int, size: NSSize, activeColor: NSColor, inactiveColor: NSColor) {
        self.lit = lit; self.total = total; self.barSize = size
        self.activeColor = activeColor; self.inactiveColor = inactiveColor
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let barW = bounds.width * 0.17
        let spacing = bounds.width * 0.06
        let totalW = CGFloat(total) * barW + CGFloat(total - 1) * spacing
        let startX = (bounds.width - totalW) / 2
        let maxH = bounds.height * 0.8

        for i in 0..<total {
            let h = maxH * CGFloat(i + 1) / CGFloat(total)
            let x = startX + CGFloat(i) * (barW + spacing)
            let rect = NSRect(x: x, y: 0, width: barW, height: h)
            let path = NSBezierPath(roundedRect: rect, xRadius: barW / 3, yRadius: barW / 3)
            (i < lit ? activeColor : inactiveColor).setFill()
            path.fill()
        }
    }
}

// MARK: - SiteRowView

class SiteRowView: NSView {
    var siteName: String = "" { didSet { nameLabel.stringValue = siteName } }

    private let nameLabel: NSTextField
    private let msLabel: NSTextField
    private let barFill: NSView
    private var barWidthConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        nameLabel = NSTextField(labelWithString: "")
        msLabel = NSTextField(labelWithString: "等待检测...")
        barFill = NSView()
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 4

        nameLabel.font = NSDesignFont.body
        nameLabel.textColor = .nsTextDefault
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        msLabel.font = NSDesignFont.caption
        msLabel.textColor = .nsTextSecondary
        msLabel.alignment = .right
        msLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(msLabel)

        let barBg = NSView()
        barBg.wantsLayer = true
        barBg.layer?.backgroundColor = NSColor.nsGrey300.cgColor
        barBg.layer?.cornerRadius = 1
        barBg.translatesAutoresizingMaskIntoConstraints = false
        addSubview(barBg)

        barFill.wantsLayer = true
        barFill.layer?.cornerRadius = 1
        barFill.layer?.backgroundColor = NSColor.nsGrey300.cgColor
        barFill.translatesAutoresizingMaskIntoConstraints = false
        barBg.addSubview(barFill)

        barWidthConstraint = barFill.widthAnchor.constraint(equalToConstant: 4)
        barWidthConstraint?.isActive = true

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 150),
            msLabel.trailingAnchor.constraint(equalTo: barBg.leadingAnchor, constant: -8),
            msLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            msLabel.widthAnchor.constraint(equalToConstant: 48),
            barBg.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            barBg.centerYAnchor.constraint(equalTo: centerYAnchor),
            barBg.widthAnchor.constraint(equalToConstant: 56),
            barBg.heightAnchor.constraint(equalToConstant: 2),
            barFill.leadingAnchor.constraint(equalTo: barBg.leadingAnchor),
            barFill.topAnchor.constraint(equalTo: barBg.topAnchor),
            barFill.bottomAnchor.constraint(equalTo: barBg.bottomAnchor),
        ])

        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(result: WebsiteResult) {
        if result.status == .timeout {
            msLabel.stringValue = "超时"
            msLabel.textColor = .nsTextDisabled
            barFill.layer?.backgroundColor = NSColor.nsGrey300.cgColor
            barWidthConstraint?.constant = 4
        } else {
            let ms = Int(result.responseTime)
            msLabel.stringValue = "\(ms)ms"
            msLabel.textColor = .nsTextSecondary
            barFill.layer?.backgroundColor = NSLatencyThreshold.statusColor(for: ms).cgColor
            let normalized = max(0, min(1, 1.0 - CGFloat(ms) / 3000.0))
            barWidthConstraint?.constant = max(4, 56 * normalized)
        }
    }

    override func updateLayer() {
        super.updateLayer()
        // Bar background and fill re-resolve on appearance change
    }

    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = NSColor.nsOverlayLight.cgColor }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = NSColor.clear.cgColor }
}

// MARK: - EnvToggle

class EnvToggle: NSView {
    var selectedMode: EnvironmentMode = .global { didSet { updateSelection() } }
    weak var target: AnyObject?
    var action: Selector?

    private let domesticBtn: NSButton
    private let globalBtn: NSButton

    override init(frame frameRect: NSRect) {
        let container = NSView(frame: NSRect(origin: .zero, size: frameRect.size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.nsBackgroundTertiary.cgColor
        container.layer?.cornerRadius = 4

        let btnW = (frameRect.width - 6) / 2
        let btnH = frameRect.height - 4
        domesticBtn = NSButton(frame: NSRect(x: 2, y: 2, width: btnW, height: btnH))
        globalBtn = NSButton(frame: NSRect(x: btnW + 4, y: 2, width: btnW, height: btnH))

        super.init(frame: frameRect)

        for btn in [domesticBtn, globalBtn] {
            btn.isBordered = false
            btn.wantsLayer = true
            btn.font = NSDesignFont.button
            btn.layer?.cornerRadius = 3
        }
        domesticBtn.title = "仅国内"
        globalBtn.title = "全球"
        domesticBtn.target = self
        domesticBtn.action = #selector(btnClicked)
        globalBtn.target = self
        globalBtn.action = #selector(btnClicked)

        container.addSubview(domesticBtn)
        container.addSubview(globalBtn)
        addSubview(container)
        updateSelection()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateSelection() {
        if selectedMode == .domesticOnly {
            setButtonActive(domesticBtn)
            setButtonInactive(globalBtn)
        } else {
            setButtonActive(globalBtn)
            setButtonInactive(domesticBtn)
        }
    }

    func updateForAppearance() {
        updateSelection()
    }

    private func setButtonActive(_ btn: NSButton) {
        btn.layer?.backgroundColor = NSColor.nsBackgroundDefault.cgColor
        btn.layer?.shadowColor = NSColor.black.cgColor
        btn.layer?.shadowOpacity = 0.06
        btn.layer?.shadowOffset = NSSize(width: 0, height: -0.5)
        btn.layer?.shadowRadius = 1.5
        btn.contentTintColor = .nsTextDefault
    }

    private func setButtonInactive(_ btn: NSButton) {
        btn.layer?.backgroundColor = NSColor.clear.cgColor
        btn.layer?.shadowOpacity = 0
        btn.contentTintColor = .nsTextTertiary
    }

    @objc private func btnClicked(_ sender: NSButton) {
        selectedMode = (sender == domesticBtn) ? .domesticOnly : .global
        if let action = action { _ = target?.perform(action, with: self) }
    }
}

// MARK: - SettingsPopoverViewDelegate

protocol SettingsPopoverViewDelegate: AnyObject {
    func settingsDidRequestBack()
    func settingsDidAddWebsite()
    func settingsDidChangeWebsites()
    func settingsDidChangeAutoRefresh()
}

// MARK: - SettingsPopoverView

class SettingsPopoverView: NSScrollView {
    weak var settingsDelegate: SettingsPopoverViewDelegate?

    private var content: FlippedView!
    private var autoRefreshToggle: ToggleSwitch!
    private var launchToggle: ToggleSwitch!
    private var intervalSlider: NSSlider!
    private var intervalValueLabel: NSTextField!
    private let W = NSDesignLayout.popoverWidth
    private let P: CGFloat = 16

    override init(frame: NSRect) {
        super.init(frame: frame)
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        borderType = .noBorder
        drawsBackground = false
    }

    required init?(coder: NSCoder) { fatalError() }

    func reload() {
        content?.removeFromSuperview()
        content = FlippedView(frame: NSRect(x: 0, y: 0, width: W, height: 600))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.nsBackgroundDefault.cgColor
        documentView = content
        buildLayout()
    }

    private func buildLayout() {
        var y: CGFloat = 0
        let cardX: CGFloat = P
        let cardW: CGFloat = W - 2 * P

        // --- Header ---
        let headerH: CGFloat = 44
        let header = FlippedView(frame: NSRect(x: 0, y: y, width: W, height: headerH))

        let backBtn = NSButton(frame: NSRect(x: 8, y: (headerH - 28) / 2, width: 28, height: 28))
        backBtn.bezelStyle = .inline
        backBtn.isBordered = false
        backBtn.title = "‹"
        backBtn.font = NSFont.systemFont(ofSize: 20, weight: .medium)
        backBtn.target = self
        backBtn.action = #selector(backClicked)
        header.addSubview(backBtn)

        let titleLabel = NSTextField(labelWithString: "设置")
        titleLabel.font = NSDesignFont.title
        titleLabel.textColor = .nsTextDefault
        titleLabel.frame = NSRect(x: 40, y: (headerH - 14) / 2, width: 60, height: 14)
        header.addSubview(titleLabel)

        content.addSubview(header)
        y += headerH

        // --- General Card ---
        let generalH: CGFloat = 128
        let generalCard = FlippedView(frame: NSRect(x: cardX, y: y + 4, width: cardW, height: generalH))
        generalCard.wantsLayer = true
        generalCard.layer?.backgroundColor = NSColor.nsBackgroundSecondary.cgColor
        generalCard.layer?.cornerRadius = 6

        let genTitle = makeSectionLabel("通用设置")
        genTitle.frame = NSRect(x: 12, y: 10, width: 100, height: 14)
        generalCard.addSubview(genTitle)

        launchToggle = ToggleSwitch(frame: NSRect(x: cardW - 50, y: 30, width: 38, height: 22))
        launchToggle.isOn = LaunchAtLoginHelper.isEnabled()
        launchToggle.target = self
        launchToggle.action = #selector(launchToggleChanged)
        generalCard.addSubview(makeRowLabel("开机自动启动", y: 30))
        generalCard.addSubview(launchToggle)

        autoRefreshToggle = ToggleSwitch(frame: NSRect(x: cardW - 50, y: 58, width: 38, height: 22))
        autoRefreshToggle.isOn = Preferences.shared.autoRefresh
        autoRefreshToggle.target = self
        autoRefreshToggle.action = #selector(autoRefreshToggleChanged)
        generalCard.addSubview(makeRowLabel("自动刷新", y: 58))
        generalCard.addSubview(autoRefreshToggle)

        intervalValueLabel = NSTextField(labelWithString: "\(Int(Preferences.shared.refreshInterval))秒")
        intervalValueLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        intervalValueLabel.textColor = .nsTextSecondary
        intervalValueLabel.alignment = .right
        intervalValueLabel.frame = NSRect(x: cardW - 60, y: 86, width: 48, height: 14)
        generalCard.addSubview(intervalValueLabel)
        generalCard.addSubview(makeRowLabel("刷新间隔", y: 86))

        intervalSlider = NSSlider(value: Preferences.shared.refreshInterval, minValue: 10, maxValue: 300,
                                   target: self, action: #selector(sliderChanged))
        intervalSlider.frame = NSRect(x: 12, y: 102, width: cardW - 24, height: 18)
        intervalSlider.isEnabled = Preferences.shared.autoRefresh
        generalCard.addSubview(intervalSlider)

        content.addSubview(generalCard)
        y += 4 + generalH

        // --- Websites Card ---
        let websites = Preferences.shared.websites
        let rowH: CGFloat = 28
        let headerArea: CGFloat = 36
        let websitesH = headerArea + CGFloat(websites.count) * rowH + 4

        let webCard = FlippedView(frame: NSRect(x: cardX, y: y + 8, width: cardW, height: websitesH))
        webCard.wantsLayer = true
        webCard.layer?.backgroundColor = NSColor.nsBackgroundSecondary.cgColor
        webCard.layer?.cornerRadius = 6

        let webTitle = makeSectionLabel("检测网址")
        webTitle.frame = NSRect(x: 12, y: 10, width: 100, height: 14)
        webCard.addSubview(webTitle)

        let addBtn = NSButton(frame: NSRect(x: cardW - 70, y: 6, width: 58, height: 22))
        addBtn.title = "添加网站"
        addBtn.font = NSDesignFont.body
        addBtn.bezelStyle = .inline
        addBtn.isBordered = false
        addBtn.target = self
        addBtn.action = #selector(addWebsiteClicked)
        webCard.addSubview(addBtn)

        let div = NSView(frame: NSRect(x: 0, y: headerArea - 0.5, width: cardW, height: 0.5))
        div.wantsLayer = true
        div.layer?.backgroundColor = NSColor.nsBorderNeutral.cgColor
        webCard.addSubview(div)

        var ry: CGFloat = headerArea
        for (i, site) in websites.enumerated() {
            let rowBg = FlippedView(frame: NSRect(x: 0, y: ry, width: cardW, height: rowH))
            rowBg.wantsLayer = true
            rowBg.layer?.backgroundColor = (i % 2 == 0 ? NSColor.nsBackgroundDefault : NSColor.nsBackgroundSecondary).cgColor

            let nameL = NSTextField(labelWithString: site.name)
            nameL.font = NSDesignFont.body
            nameL.textColor = .nsTextDefault
            nameL.frame = NSRect(x: 12, y: (rowH - 14) / 2, width: 120, height: 14)
            rowBg.addSubview(nameL)

            let badgeW: CGFloat = 28
            let badge = NSView(frame: NSRect(x: cardW - 70, y: (rowH - 18) / 2, width: badgeW, height: 18))
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 3
            let badgeLabel = NSTextField(labelWithString: site.isDomestic ? "国内" : "海外")
            badgeLabel.font = NSDesignFont.legend
            badgeLabel.alignment = .center
            badgeLabel.frame = badge.bounds
            if site.isDomestic {
                badge.layer?.backgroundColor = NSColor.nsOverlayLight.cgColor
                badgeLabel.textColor = .nsTextSecondary
            } else {
                badge.layer?.backgroundColor = NSColor.nsGrey900.cgColor
                badgeLabel.textColor = .nsBackgroundDefault
            }
            badge.addSubview(badgeLabel)
            rowBg.addSubview(badge)

            let delBtn = NSButton(frame: NSRect(x: cardW - 30, y: (rowH - 18) / 2, width: 18, height: 18))
            delBtn.bezelStyle = .inline
            delBtn.isBordered = false
            delBtn.attributedTitle = NSAttributedString(string: "✕", attributes: [
                .foregroundColor: NSColor.nsTextTertiary,
                .font: NSFont.systemFont(ofSize: 10, weight: .medium)
            ])
            delBtn.tag = i
            delBtn.target = self
            delBtn.action = #selector(deleteWebsiteClicked)
            rowBg.addSubview(delBtn)

            webCard.addSubview(rowBg)
            ry += rowH
        }

        content.addSubview(webCard)
        y += 8 + websitesH

        content.frame = NSRect(x: 0, y: 0, width: W, height: y + 16)
    }

    // MARK: - Actions

    @objc private func backClicked() { settingsDelegate?.settingsDidRequestBack() }

    @objc private func launchToggleChanged() {
        let on = launchToggle.toggle()
        Preferences.shared.launchAtLogin = on
        LaunchAtLoginHelper.setEnabled(on)
    }

    @objc private func autoRefreshToggleChanged() {
        let on = autoRefreshToggle.toggle()
        Preferences.shared.autoRefresh = on
        intervalSlider?.isEnabled = on
        settingsDelegate?.settingsDidChangeAutoRefresh()
    }

    @objc private func sliderChanged() {
        let interval = round(intervalSlider.doubleValue / 10) * 10
        Preferences.shared.refreshInterval = interval
        intervalValueLabel.stringValue = "\(Int(interval))秒"
        settingsDelegate?.settingsDidChangeAutoRefresh()
    }

    @objc private func addWebsiteClicked() {
        let alert = NSAlert()
        alert.messageText = "添加检测网址"
        alert.informativeText = "请输入网站名称和地址："
        alert.icon = SignalIcon.drawAppIcon(size: NSSize(width: 32, height: 32))

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        let nameLabel = NSTextField(labelWithString: "名称:")
        nameLabel.frame = NSRect(x: 0, y: 90, width: 40, height: 20)
        accessory.addSubview(nameLabel)
        let nameField = NSTextField()
        nameField.frame = NSRect(x: 50, y: 88, width: 250, height: 24)
        nameField.placeholderString = "例如：百度"
        accessory.addSubview(nameField)
        let urlLabel = NSTextField(labelWithString: "地址:")
        urlLabel.frame = NSRect(x: 0, y: 54, width: 40, height: 20)
        accessory.addSubview(urlLabel)
        let urlField = NSTextField()
        urlField.frame = NSRect(x: 50, y: 52, width: 250, height: 24)
        urlField.placeholderString = "https://www.baidu.com"
        accessory.addSubview(urlField)
        let typeLabel = NSTextField(labelWithString: "类型:")
        typeLabel.frame = NSRect(x: 0, y: 18, width: 40, height: 20)
        accessory.addSubview(typeLabel)
        let typeSeg = NSSegmentedControl(labels: ["国内", "海外"], trackingMode: .selectOne, target: nil, action: nil)
        typeSeg.frame = NSRect(x: 50, y: 16, width: 140, height: 24)
        typeSeg.selectedSegment = 0
        accessory.addSubview(typeSeg)

        alert.accessoryView = accessory
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !url.isEmpty else { return }
            let finalURL = url.hasPrefix("http") ? url : "https://\(url)"
            Preferences.shared.websites.append(Website(name: name, url: finalURL, isDomestic: typeSeg.selectedSegment == 0))
            reload()
            NotificationCenter.default.post(name: .websitesDidChange, object: nil)
            settingsDelegate?.settingsDidAddWebsite()
        }
    }

    @objc private func deleteWebsiteClicked(_ sender: NSButton) {
        let row = sender.tag
        guard row < Preferences.shared.websites.count else { return }
        let site = Preferences.shared.websites[row]
        let alert = NSAlert()
        alert.messageText = "删除网站"
        alert.informativeText = "确定要删除 \(site.name)？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")

        if let win = self.window {
            alert.beginSheetModal(for: win) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    Preferences.shared.websites.remove(at: row)
                    self?.reload()
                    NotificationCenter.default.post(name: .websitesDidChange, object: nil)
                    self?.settingsDelegate?.settingsDidChangeWebsites()
                }
            }
        } else {
            if alert.runModal() == .alertFirstButtonReturn {
                Preferences.shared.websites.remove(at: row)
                reload()
                NotificationCenter.default.post(name: .websitesDidChange, object: nil)
                settingsDelegate?.settingsDidChangeWebsites()
            }
        }
    }

    // MARK: - Helpers

    private func makeSectionLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSDesignFont.sectionHeading; l.textColor = .nsTextTertiary
        return l
    }

    private func makeRowLabel(_ text: String, y: CGFloat) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSDesignFont.body; l.textColor = .nsTextDefault
        l.frame = NSRect(x: 12, y: y, width: 100, height: 22)
        return l
    }
}

// MARK: - ToggleSwitch

class ToggleSwitch: NSView {
    var isOn: Bool = false { didSet { updateVisual() } }
    weak var target: AnyObject?
    var action: Selector?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = frame.height / 2
        updateVisual()
    }

    required init?(coder: NSCoder) { fatalError() }

    func toggle() -> Bool { isOn = !isOn; return isOn }

    override func updateLayer() {
        super.updateLayer()
        updateVisual()
    }

    private func updateVisual() {
        layer?.backgroundColor = (isOn ? NSColor.nsBrandPrimary : NSColor.nsGrey300).cgColor
        subviews.forEach { $0.removeFromSuperview() }
        let knobSize = bounds.height - 4
        let knobX = isOn ? bounds.width - knobSize - 2 : 2
        let knob = NSView(frame: NSRect(x: knobX, y: 2, width: knobSize, height: knobSize))
        knob.wantsLayer = true
        knob.layer?.backgroundColor = NSColor.white.cgColor
        knob.layer?.cornerRadius = knobSize / 2
        knob.layer?.shadowColor = NSColor.black.cgColor
        knob.layer?.shadowOpacity = 0.12
        knob.layer?.shadowOffset = NSSize(width: 0, height: 1)
        knob.layer?.shadowRadius = 2
        addSubview(knob)
    }

    override func mouseDown(with event: NSEvent) {
        if let action = action { _ = target?.perform(action, with: self) }
    }
}
