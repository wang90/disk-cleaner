import Foundation
import SwiftUI

/// 外观主题
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - 与 diskautoclean.sh --json 对应的数据结构

struct ScanItem: Codable, Identifiable, Hashable {
    var id: String { path }
    let label: String
    let path: String
    let tier: Int
    let kb: Int
    let status: String?

    /// reading 状态：ok / timeout / fail
    var readOK: Bool { (status ?? "ok") == "ok" }

    var bytesText: String {
        guard !readOK else { return Fmt.size(kb) }
        return status == "timeout" ? "读取超时" : "无权限"
    }

    var tierName: String {
        switch tier {
        case 1: return "安全"
        case 2: return "开发"
        default: return "用户数据"
        }
    }
}

struct StatusPayload: Codable {
    let freeKB: Int
    let targetKB: Int
    let diskTotalKB: Int
    let diskUsedKB: Int
    let diskAvailKB: Int
    let memTotalKB: Int
    let memAvailKB: Int
    let memActiveKB: Int
    let memWiredKB: Int
    let memCompressedKB: Int
    let swapTotalKB: Int
    let swapUsedKB: Int
    let volumes: [VolumeInfo]?

    enum CodingKeys: String, CodingKey {
        case freeKB = "free_kb"
        case targetKB = "target_kb"
        case diskTotalKB = "disk_total_kb"
        case diskUsedKB = "disk_used_kb"
        case diskAvailKB = "disk_avail_kb"
        case memTotalKB = "mem_total_kb"
        case memAvailKB = "mem_avail_kb"
        case memActiveKB = "mem_active_kb"
        case memWiredKB = "mem_wired_kb"
        case memCompressedKB = "mem_compressed_kb"
        case swapTotalKB = "swap_total_kb"
        case swapUsedKB = "swap_used_kb"
        case volumes
    }
}

/// 一个硬盘 / 卷（--status 里的 volumes）
struct VolumeInfo: Codable, Identifiable, Hashable {
    var id: String { mount }
    let name: String
    let mount: String
    let totalKB: Int
    let usedKB: Int
    let availKB: Int
    let boot: Bool?

    enum CodingKeys: String, CodingKey {
        case name, mount, boot
        case totalKB = "total_kb"
        case usedKB = "used_kb"
        case availKB = "avail_kb"
    }

    var usedRatio: Double {
        totalKB > 0 ? min(1, Double(usedKB) / Double(totalKB)) : 0
    }
}

/// 储存空间的一个分类（--storage）
struct StorageCategory: Codable, Identifiable, Hashable {
    var id: String { key }
    let key: String
    let label: String
    let kb: Int
    let status: String?

    var readOK: Bool { (status ?? "ok") == "ok" }
}

struct StoragePayload: Codable {
    let totalKB: Int
    let usedKB: Int
    let availKB: Int
    let categories: [StorageCategory]

    enum CodingKeys: String, CodingKey {
        case totalKB = "total_kb"
        case usedKB = "used_kb"
        case availKB = "avail_kb"
        case categories
    }
}

/// 单个应用占用（--apps --json）
struct AppItem: Codable, Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let bundleID: String?
    let appKB: Int
    let dataKB: Int
    let totalKB: Int

    enum CodingKeys: String, CodingKey {
        case name, path
        case bundleID = "bundle_id"
        case appKB = "app_kb"
        case dataKB = "data_kb"
        case totalKB = "total_kb"
    }
}

struct AppsPayload: Codable {
    let freeKB: Int
    let diskTotalKB: Int
    let apps: [AppItem]

    enum CodingKeys: String, CodingKey {
        case freeKB = "free_kb"
        case diskTotalKB = "disk_total_kb"
        case apps
    }
}

struct ScanPayload: Codable {
    let freeKB: Int
    let targetKB: Int
    let totalKB: Int
    let items: [ScanItem]

    enum CodingKeys: String, CodingKey {
        case freeKB = "free_kb"
        case targetKB = "target_kb"
        case totalKB = "total_kb"
        case items
    }
}

// MARK: - 格式化

enum Fmt {
    /// 磁盘/文件体积：十进制（跟 Finder、macOS「储存空间」一致，1 GB = 1000³ 字节）
    static func size(_ kb: Int) -> String {
        let bytes = Double(max(0, kb)) * 1024
        if bytes >= 1e12 { return String(format: "%.2f TB", bytes / 1e12) }
        if bytes >= 1e9 { return String(format: "%.1f GB", bytes / 1e9) }
        if bytes >= 1e6 { return String(format: "%.0f MB", bytes / 1e6) }
        return String(format: "%.0f KB", bytes / 1000)
    }

    /// 内存：二进制（跟 macOS「关于本机」一致，16 GiB 显示为 16 GB）
    static func memSize(_ kb: Int) -> String {
        let gb = Double(max(0, kb)) / 1_048_576
        if gb >= 1024 { return String(format: "%.1f TB", gb / 1024) }
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(max(0, kb)) / 1024)
    }

    /// 把 /Users/wang90/xxx 缩写成 ~/xxx
    static func tilde(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
