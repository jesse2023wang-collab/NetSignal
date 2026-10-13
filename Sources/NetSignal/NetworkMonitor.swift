import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let websitesDidChange = Notification.Name("websitesDidChange")
}

protocol NetworkMonitorDelegate: AnyObject {
    func networkMonitorDidUpdate(results: [WebsiteResult], quality: NetworkQuality)
    func networkMonitorDidStartTesting()
}

class NetworkMonitor {
    static let shared = NetworkMonitor()
    weak var delegate: NetworkMonitorDelegate?

    /// 自动模式下探测出的实际环境，nil 表示尚未探测
    private(set) var effectiveMode: EnvironmentMode?

    private var session: URLSession
    private var isTesting = false

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 15.0
        config.allowsCellularAccess = true
        self.session = URLSession(configuration: config)
    }

    func testAllWebsites() {
        guard !isTesting else { return }
        isTesting = true
        delegate?.networkMonitorDidStartTesting()

        let mode = Preferences.shared.environmentMode
        guard mode == .auto else {
            runTests(mode)
            return
        }

        // 自动模式：先判断海外网站能否访问（等价于判断 VPN 是否生效），再决定检测范围
        detectOverseasAccessibility { [weak self] accessible in
            guard let self = self else { return }
            let resolved: EnvironmentMode = accessible ? .global : .domesticOnly
            self.effectiveMode = resolved
            self.runTests(resolved)
        }
    }

    private func runTests(_ mode: EnvironmentMode) {
        let prefs = Preferences.shared
        let websites: [Website]
        switch mode {
        case .domesticOnly:
            websites = prefs.websites.filter { $0.isEnabled && $0.isDomestic }
        case .global, .auto:
            websites = prefs.websites.filter { $0.isEnabled }
        }
        let group = DispatchGroup()
        var results: [WebsiteResult] = []
        let lock = NSLock()

        for website in websites {
            group.enter()
            testWebsite(website) { result in
                lock.lock()
                results.append(result)
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.isTesting = false
            let quality = self?.calculateOverallQuality(results: results) ?? .noSignal
            self?.delegate?.networkMonitorDidUpdate(results: results, quality: quality)
        }
    }

    /// 探测海外网站是否可访问（GitHub 除外），任一真正可达即视为海外网络可用
    private func detectOverseasAccessibility(completion: @escaping (Bool) -> Void) {
        // 固定探针：204 空响应、无内容，被墙时必然超时，是最可靠的判定依据
        var probes = [URL(string: "https://www.google.com/generate_204")!]
        probes += Preferences.shared.websites
            .filter { $0.isEnabled && !$0.isDomestic && !isGitHub($0) }
            .compactMap { URL(string: normalizedURL($0.url)) }

        let state = ProbeState()
        let group = DispatchGroup()

        for url in probes {
            group.enter()

            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 3.0
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

            let task = session.dataTask(with: request) { _, response, _ in
                // 只认 2xx/3xx：403/405 这类多半是地域限制或 CDN 拦 HEAD（如 Netflix 无 VPN 也返回 403），
                // 而真正被墙时表现为超时/连接失败，压根拿不到响应
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                state.record(statusCode >= 200 && statusCode < 400)
                group.leave()
            }

            state.add(task)
            task.resume()
        }

        group.notify(queue: .main) { completion(state.isAccessible) }
    }

    /// 海外可达性探测状态：记录结果，命中后取消其余请求以尽快返回
    private final class ProbeState: @unchecked Sendable {
        private let lock = NSLock()
        private var tasks: [URLSessionTask] = []
        private var accessible = false
        private var cancelled = false

        var isAccessible: Bool {
            lock.lock()
            defer { lock.unlock() }
            return accessible
        }

        func add(_ task: URLSessionTask) {
            lock.lock()
            tasks.append(task)
            let drop = accessible
            lock.unlock()
            if drop { task.cancel() }
        }

        func record(_ ok: Bool) {
            lock.lock()
            if ok { accessible = true }
            let pending = (accessible && !cancelled) ? tasks : []
            if !pending.isEmpty { cancelled = true }
            lock.unlock()
            pending.forEach { $0.cancel() }
        }
    }

    private func isGitHub(_ website: Website) -> Bool {
        guard let host = URL(string: normalizedURL(website.url))?.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com")
    }

    private func normalizedURL(_ url: String) -> String {
        return url.hasPrefix("http") ? url : "https://\(url)"
    }

    private func testWebsite(_ website: Website, completion: @escaping (WebsiteResult) -> Void) {
        let urlStr = website.url.hasPrefix("http") ? website.url : "https://\(website.url)"
        guard let url = URL(string: urlStr) else {
            completion(WebsiteResult(website: website, responseTime: -1, status: .timeout))
            return
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Use HEAD first for speed, fall back to GET on error
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5.0
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")

        let task = session.dataTask(with: request) { data, response, error in
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0 // ms

            if error != nil || response == nil {
                // Fallback to GET if HEAD fails (some servers don't support HEAD)
                self.retryWithGet(website, startTime: startTime, completion: completion)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(WebsiteResult(website: website, responseTime: -1, status: .timeout))
                }
                return
            }

            // If HEAD succeeded with 2xx/3xx, no need to retry
            if httpResponse.statusCode >= 200 && httpResponse.statusCode < 400 {
                let status: WebsiteStatus
                if elapsed < 200 {
                    status = .excellent
                } else if elapsed < 500 {
                    status = .good
                } else if elapsed < 1500 {
                    status = .fair
                } else {
                    status = .poor
                }
                DispatchQueue.main.async {
                    completion(WebsiteResult(website: website, responseTime: elapsed, status: status))
                }
                return
            }

            // Non-2xx from HEAD — retry with GET
            self.retryWithGet(website, startTime: startTime, completion: completion)
        }
        task.resume()
    }

    private func retryWithGet(_ website: Website, startTime: CFAbsoluteTime, completion: @escaping (WebsiteResult) -> Void) {
        let urlStr = website.url.hasPrefix("http") ? website.url : "https://\(website.url)"
        guard let url = URL(string: urlStr) else {
            DispatchQueue.main.async {
                completion(WebsiteResult(website: website, responseTime: -1, status: .timeout))
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8.0
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        let task = session.dataTask(with: request) { data, response, error in
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0 // ms

            if error != nil {
                DispatchQueue.main.async {
                    completion(WebsiteResult(website: website, responseTime: -1, status: .timeout))
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(WebsiteResult(website: website, responseTime: -1, status: .timeout))
                }
                return
            }

            let status: WebsiteStatus
            if httpResponse.statusCode >= 200 && httpResponse.statusCode < 400 {
                if elapsed < 200 {
                    status = .excellent
                } else if elapsed < 500 {
                    status = .good
                } else if elapsed < 1500 {
                    status = .fair
                } else {
                    status = .poor
                }
            } else {
                status = .timeout
            }

            DispatchQueue.main.async {
                completion(WebsiteResult(website: website, responseTime: elapsed, status: status))
            }
        }
        task.resume()
    }

    private func calculateOverallQuality(results: [WebsiteResult]) -> NetworkQuality {
        guard !results.isEmpty else { return .noSignal }

        let validResults = results.filter { $0.status != .timeout }
        if validResults.isEmpty {
            return .noSignal
        }

        let avgTime = validResults.map { $0.responseTime }.reduce(0, +) / Double(validResults.count)

        if avgTime < 200 {
            return .excellent
        } else if avgTime < 500 {
            return .good
        } else if avgTime < 1500 {
            return .fair
        } else {
            return .poor
        }
    }
}
