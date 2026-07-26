import Foundation
import Cocoa

class UpdateChecker {
    static let shared = UpdateChecker()

    private let currentVersion = "1.0.2"
    private let checkURL = "https://api.github.com/repos/jesse2023wang-ai/NetSignal/releases/latest"

    func checkForUpdate() {
        guard let url = URL(string: checkURL) else { return }

        let request = URLRequest(url: url, timeoutInterval: 10)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else {
                DispatchQueue.main.async {
                    self?.showAlert(title: "检查更新失败", message: "无法连接到更新服务器，请检查网络后重试。")
                }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tagName = json["tag_name"] as? String {
                    let latestVersion = tagName.replacingOccurrences(of: "v", with: "")
                    DispatchQueue.main.async {
                        self.compareVersions(current: self.currentVersion, latest: latestVersion)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.showAlert(title: "检查更新", message: "当前版本 \(self.currentVersion) 已是最新版本。")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.showAlert(title: "检查更新", message: "当前版本 \(self.currentVersion) 已是最新版本。")
                }
            }
        }.resume()
    }

    private func compareVersions(current: String, latest: String) {
        if latest > current {
            showUpdateAvailable(latest: latest)
        } else {
            showAlert(title: "检查更新", message: "当前版本 \(current) 已是最新版本。")
        }
    }

    private func showUpdateAvailable(latest: String) {
        let alert = NSAlert()
        alert.messageText = "发现新版本"
        alert.informativeText = "最新版本: \(latest)\n当前版本: \(currentVersion)\n\n是否前往下载？"
        alert.alertStyle = .informational
        alert.icon = SignalIcon.drawAppIcon()
        alert.addButton(withTitle: "前往下载")
        alert.addButton(withTitle: "稍后提醒")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "https://github.com/jesse2023wang-ai/NetSignal/releases/latest") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.icon = SignalIcon.drawAppIcon()
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
}
