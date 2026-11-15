import Foundation
import UIKit

/// 拨出记录条目（含真实时间戳）
struct CallHistoryEntry: Codable, Identifiable, Equatable {
    var id: String { number }
    var number: String
    var date: Date?
    /// nil = 未知（未观察到接通状态）；true = 已接通；false = 未接通
    var connected: Bool?
}

/// 统一的拨出记录存储。
/// 说明：iOS 不允许第三方应用读取系统通话记录，这里只维护“本机真实拨出”的记录。
enum RecentDialStore {
    static let historyDidChange = Notification.Name("RecentDialHistoryDidChange")

    // MARK: - 读写

    static func load() -> [CallHistoryEntry] {
        if let data = UserDefaults.standard.data(forKey: StorageKeys.recentDialHistoryV2) {
            if let entries = try? JSONDecoder().decode([CallHistoryEntry].self, from: data) {
                return cap(entries)
            }
        }
        return migrateIfNeeded()
    }

    static func save(_ entries: [CallHistoryEntry]) {
        let capped = cap(entries)
        if let data = try? JSONEncoder().encode(capped) {
            UserDefaults.standard.set(data, forKey: StorageKeys.recentDialHistoryV2)
        }
        NotificationCenter.default.post(name: historyDidChange, object: nil)
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: StorageKeys.recentDialHistoryV2)
        UserDefaults.standard.removeObject(forKey: StorageKeys.recentDialHistory)
        NotificationCenter.default.post(name: historyDidChange, object: nil)
    }

    // MARK: - 变更操作

    /// 新增一条真实拨出记录（去重、置顶、写入真实时间）
    @discardableResult
    static func add(number: String) -> [CallHistoryEntry] {
        var entries = load()
        entries.removeAll { $0.number == number }
        entries.insert(CallHistoryEntry(number: number, date: Date(), connected: nil), at: 0)
        save(entries)
        return entries
    }

    /// 撤销最近新增的某号码记录（仅当该记录是近期新增时）。
    /// 用于“点击拨号后立刻挂断、实际没有打出”的情况。
    @discardableResult
    static func undoRecentAdd(number: String, within seconds: TimeInterval) -> [CallHistoryEntry] {
        var entries = load()
        if let idx = entries.firstIndex(where: { $0.number == number }),
           let date = entries[idx].date,
           Date().timeIntervalSince(date) <= seconds {
            entries.remove(at: idx)
            save(entries)
        }
        return entries
    }

    /// 标记最近一条该号码记录的接通状态
    static func markStatus(number: String, connected: Bool, within seconds: TimeInterval) {
        var entries = load()
        if let idx = entries.firstIndex(where: { $0.number == number }),
           let date = entries[idx].date,
           Date().timeIntervalSince(date) <= seconds {
            entries[idx].connected = connected
            save(entries)
        }
    }

    /// 手动删除某号码全部记录
    static func remove(number: String) {
        var entries = load()
        entries.removeAll { $0.number == number }
        save(entries)
    }

    private static func cap(_ entries: [CallHistoryEntry]) -> [CallHistoryEntry] {
        let maxCount = AppSettings.shared.maxRecentRecords
        return entries.count > maxCount ? Array(entries.prefix(maxCount)) : entries
    }

    /// 旧版数据（纯号码数组）一次性迁移为带时间戳格式
    private static func migrateIfNeeded() -> [CallHistoryEntry] {
        let old = UserDefaults.standard.stringArray(forKey: StorageKeys.recentDialHistory) ?? []
        let entries = old.map { CallHistoryEntry(number: $0, date: nil, connected: nil) }
        if !entries.isEmpty {
            if let data = try? JSONEncoder().encode(entries) {
                UserDefaults.standard.set(data, forKey: StorageKeys.recentDialHistoryV2)
            }
        }
        UserDefaults.standard.removeObject(forKey: StorageKeys.recentDialHistory)
        return entries
    }

    // MARK: - 拨打频次

    static func bumpFrequency(digits: String) {
        guard !digits.isEmpty else { return }
        var freq = UserDefaults.standard.dictionary(forKey: StorageKeys.callFrequency) as? [String: Int] ?? [:]
        freq[digits, default: 0] += 1
        UserDefaults.standard.set(freq, forKey: StorageKeys.callFrequency)
    }

    static func decrementFrequency(digits: String) {
        guard !digits.isEmpty else { return }
        var freq = UserDefaults.standard.dictionary(forKey: StorageKeys.callFrequency) as? [String: Int] ?? [:]
        if let count = freq[digits], count > 0 {
            freq[digits] = count - 1
            if freq[digits] == 0 {
                freq.removeValue(forKey: digits)
            }
        }
        UserDefaults.standard.set(freq, forKey: StorageKeys.callFrequency)
    }

    // MARK: - 已验证的拨号

    /// 通过 tel:// 拨号，只有系统确认接手后才记录通话与频次。
    /// 拨号失败（未交由系统）不会留下任何记录。
    static func dialVerified(_ rawNumber: String) {
        let clean = rawNumber.filter { $0.isNumber || $0 == "," || $0 == ";" || $0 == "+" }
        guard !clean.isEmpty else { return }
        guard let url = URL(string: "tel://\(clean)") else { return }
        let digits = clean.filter { $0.isNumber }
        UIApplication.shared.open(url, options: [:]) { success in
            guard success else {
                print("[RecentDialStore] 拨号未交由系统，不记录: \(clean)")
                return
            }
            // 系统已接手拨号 → 记录真实拨出
            bumpFrequency(digits: digits)
            add(number: clean)
            CallTracker.shared.noteDialed(clean)
        }
    }
}
