import Foundation

/// 软件更新检查
///
/// 说明：这是 App 里**唯一**会联网的地方。它只是向 GitHub 的公开 API
/// 读一次最新 release 的版本号，不发送任何本地数据、不上报任何统计。
/// 可以在 设置 → 更新 里关掉。
enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate(current: String)
    case available(latest: String, url: String, notes: String?)
    case failed(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

/// GitHub releases API 里我们用得到的字段
struct GitHubRelease: Codable {
    let tagName: String
    let htmlURL: String
    let name: String?
    let body: String?
    let prerelease: Bool?
    let draft: Bool?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case name, body, prerelease, draft
    }

    /// "v1.0.1" -> "1.0.1"
    var version: String {
        var v = tagName
        if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
        return v
    }
}

enum AppVersion {
    /// 语义化比较：a 是否比 b 新（支持 1.0.0 / 1.0.1 / 1.0.0-beta.2 这类）
    static func isNewer(_ a: String, than b: String) -> Bool {
        let (aCore, aPre) = split(a)
        let (bCore, bPre) = split(b)
        for i in 0..<max(aCore.count, bCore.count) {
            let x = i < aCore.count ? aCore[i] : 0
            let y = i < bCore.count ? bCore[i] : 0
            if x != y { return x > y }
        }
        // 主版本号相同：正式版 > 预发布版
        switch (aPre, bPre) {
        case (nil, nil):        return false
        case (nil, _):          return true      // a 是正式版，b 是 beta
        case (_, nil):          return false
        case let (x?, y?):      return x > y
        }
    }

    private static func split(_ v: String) -> ([Int], String?) {
        let halves = v.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        let core = halves.first.map(String.init) ?? v
        let pre = halves.count > 1 ? String(halves[1]) : nil
        let nums = core.split(separator: ".").map { part -> Int in
            Int(part.prefix { $0.isNumber }) ?? 0
        }
        return (nums, pre)
    }
}

enum UpdateChecker {
    static let apiURL = URL(string: "https://api.github.com/repos/wang90/disk-cleaner/releases/latest")!

    /// 检查最新正式版。只有 autoCheck 打开时才会被调用。
    static func latestRelease() async throws -> GitHubRelease {
        var req = URLRequest(url: apiURL)
        req.timeoutInterval = 12
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("DiskCleaner/\(AppInfo.shortVersion) (macOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "DiskCleaner", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "无效的服务器响应"])
        }
        guard http.statusCode == 200 else {
            throw NSError(domain: "DiskCleaner", code: Int(http.statusCode),
                          userInfo: [NSLocalizedDescriptionKey: "GitHub 返回 \(http.statusCode)"])
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
}
