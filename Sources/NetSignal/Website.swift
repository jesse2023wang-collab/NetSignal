import Foundation

extension Notification.Name {
    static let autoRefreshChanged = Notification.Name("autoRefreshChanged")
}

struct Website: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var url: String
    var isDomestic: Bool
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, url: String, isDomestic: Bool, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.url = url
        self.isDomestic = isDomestic
        self.isEnabled = isEnabled
    }

    static let defaults: [Website] = [
        Website(name: "微博", url: "https://weibo.com", isDomestic: true),
        Website(name: "小红书", url: "https://www.xiaohongshu.com", isDomestic: true),
        Website(name: "京东", url: "https://www.jd.com", isDomestic: true),
        Website(name: "淘宝", url: "https://www.taobao.com", isDomestic: true),
        Website(name: "B站", url: "https://www.bilibili.com", isDomestic: true),
        Website(name: "网易", url: "https://www.163.com", isDomestic: true),
        Website(name: "X", url: "https://x.com", isDomestic: false),
        Website(name: "YouTube", url: "https://www.youtube.com", isDomestic: false),
        Website(name: "Google", url: "https://www.google.com", isDomestic: false),
        Website(name: "Netflix", url: "https://www.netflix.com", isDomestic: false),
        Website(name: "GitHub", url: "https://github.com", isDomestic: false),
    ]
}

struct WebsiteResult: Identifiable {
    let id = UUID()
    let website: Website
    let responseTime: TimeInterval
    let status: WebsiteStatus
}

enum WebsiteStatus {
    case excellent    // < 200ms
    case good         // 200-500ms
    case fair         // 500-1500ms
    case poor         // > 1500ms
    case timeout      // 超时或失败

    var description: String {
        switch self {
        case .excellent: return "极快"
        case .good: return "良好"
        case .fair: return "一般"
        case .poor: return "较慢"
        case .timeout: return "超时"
        }
    }

    var colorHex: String {
        switch self {
        case .excellent: return "#34C759"
        case .good: return "#30D158"
        case .fair: return "#FF9500"
        case .poor: return "#FF3B30"
        case .timeout: return "#8E8E93"
        }
    }
}

enum NetworkQuality: Int, CaseIterable {
    case noSignal = 0   // 无网络
    case poor = 1       // 1格
    case fair = 2       // 2格
    case good = 3       // 3格
    case excellent = 4  // 4格

    var description: String {
        switch self {
        case .noSignal: return "无网络"
        case .poor: return "网络较差"
        case .fair: return "网络一般"
        case .good: return "网络良好"
        case .excellent: return "网络极佳"
        }
    }
}

enum EnvironmentMode: String, Codable, CaseIterable {
    case auto = "auto"
    case global = "global"
    case domesticOnly = "domesticOnly"

    var description: String {
        switch self {
        case .auto: return "自动"
        case .global: return "全球"
        case .domesticOnly: return "仅国内"
        }
    }
}
