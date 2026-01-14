import Foundation

/// 版本更新信息
struct ReleaseInfo {
    let version: String
    let htmlURL: String
    let downloadURL: String?
    let releaseNotes: String
}

/// 更新检测器
class UpdateChecker {
    static let shared = UpdateChecker()

    // GitHub Release API
    private let releaseAPIURL = "https://api.github.com/repos/yellowpeachxgp/HAUTNetworkGuard/releases/latest"

    // 检测间隔：1天 (秒)
    private let checkInterval: TimeInterval = 86400

    // UserDefaults 键
    private let lastCheckKey = "haut_last_update_check"
    private let skippedVersionKey = "haut_skipped_version"

    private let session: URLSession
    private var checkTimer: Timer?

    // 更新回调
    var onUpdateAvailable: ((ReleaseInfo) -> Void)?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    /// 启动定期检测
    func startPeriodicCheck() {
        // 立即检测一次（如果距离上次检测超过1天）
        if shouldCheckNow() {
            checkForUpdate()
        }

        // 设置定时器，每小时检查一次是否需要检测更新
        checkTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            if self?.shouldCheckNow() == true {
                self?.checkForUpdate()
            }
        }
    }

    /// 停止定期检测
    func stopPeriodicCheck() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    /// 判断是否需要立即检测
    private func shouldCheckNow() -> Bool {
        let lastCheck = UserDefaults.standard.double(forKey: lastCheckKey)
        let now = Date().timeIntervalSince1970
        return (now - lastCheck) >= checkInterval
    }

    /// 手动检测更新
    func checkForUpdate(force: Bool = false) {
        guard let url = URL(string: releaseAPIURL) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("HAUTNetworkGuard/\(AppConfig.version)", forHTTPHeaderField: "User-Agent")

        Logger.log("检测更新...")

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            // 记录检测时间
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: self?.lastCheckKey ?? "")

            if let error = error {
                Logger.log("检测更新失败: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                Logger.log("检测更新失败: 无响应数据")
                return
            }

            self?.parseReleaseResponse(data, force: force)
        }
        task.resume()
    }

    /// 解析 Release 响应
    private func parseReleaseResponse(_ data: Data, force: Bool) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                Logger.log("解析 Release 信息失败")
                return
            }

            // 提取版本号 (去掉 v 前缀)
            let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            Logger.log("当前版本: \(AppConfig.version), 最新版本: \(latestVersion)")

            // 比较版本号
            if isNewerVersion(latestVersion, than: AppConfig.version) {
                // 检查是否跳过了此版本
                let skippedVersion = UserDefaults.standard.string(forKey: skippedVersionKey)
                if !force && skippedVersion == latestVersion {
                    Logger.log("用户已跳过此版本: \(latestVersion)")
                    return
                }

                // 获取下载链接
                var downloadURL: String? = nil
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String,
                           name.hasSuffix(".dmg"),
                           let url = asset["browser_download_url"] as? String {
                            downloadURL = url
                            break
                        }
                    }
                }

                let releaseInfo = ReleaseInfo(
                    version: latestVersion,
                    htmlURL: json["html_url"] as? String ?? "",
                    downloadURL: downloadURL,
                    releaseNotes: json["body"] as? String ?? ""
                )

                Logger.log("发现新版本: \(latestVersion)")

                DispatchQueue.main.async {
                    self.onUpdateAvailable?(releaseInfo)
                }
            } else {
                Logger.log("已是最新版本")
            }
        } catch {
            Logger.log("解析 Release JSON 失败: \(error.localizedDescription)")
        }
    }

    /// 比较版本号
    private func isNewerVersion(_ new: String, than current: String) -> Bool {
        let newParts = new.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(newParts.count, currentParts.count)

        for i in 0..<maxCount {
            let newPart = i < newParts.count ? newParts[i] : 0
            let currentPart = i < currentParts.count ? currentParts[i] : 0

            if newPart > currentPart {
                return true
            } else if newPart < currentPart {
                return false
            }
        }

        return false
    }

    /// 跳过此版本
    func skipVersion(_ version: String) {
        UserDefaults.standard.set(version, forKey: skippedVersionKey)
        Logger.log("已跳过版本: \(version)")
    }

    /// 清除跳过的版本
    func clearSkippedVersion() {
        UserDefaults.standard.removeObject(forKey: skippedVersionKey)
    }
}
