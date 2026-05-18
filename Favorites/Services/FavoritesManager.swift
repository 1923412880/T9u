import Foundation
import Contacts
import os

private let logger = Logger(subsystem: "com.t9u.app", category: "FavoritesManager")

class FavoritesManager {
    static let shared = FavoritesManager()
    private let defaults = UserDefaults.standard
    private let storageKey = "T9uFavoriteContactIds"
    private let phoneKey = "T9uFavoritePhoneNumbers"
    private let lock = NSLock()

    private init() {}

    func getAllFavoriteIds() -> [String] {
        defaults.stringArray(forKey: storageKey) ?? []
    }

    func getAllFavoriteContacts() -> [CNContact] {
        let ids = getAllFavoriteIds()
        guard !ids.isEmpty else { return [] }

        let idSet = Set(ids)
        let store = CNContactStore()
        let keys = [
            CNContactIdentifierKey,
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactMiddleNameKey,
            CNContactPhoneNumbersKey,
            CNContactThumbnailImageDataKey,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys as [CNKeyDescriptor])

        var result: [CNContact] = []
        do {
            try store.enumerateContacts(with: request) { contact, stop in
                if idSet.contains(contact.identifier) {
                    result.append(contact)
                }
                if result.count == idSet.count {
                    stop.pointee = true
                }
            }
        } catch {
            logger.error("枚举联系人失败: \(error.localizedDescription)")
        }
        return result
    }

    /// 检查某个联系人是否已收藏
    func isFavorite(_ id: String) -> Bool {
        getAllFavoriteIds().contains(id)
    }

    /// 获取某收藏联系人的快捷拨号号码 identifier（用于 FavoritesTab 一键拨号）
    func getSelectedPhoneNumber(for contactId: String) -> String? {
        let dict = defaults.dictionary(forKey: phoneKey) as? [String: String] ?? [:]
        return dict[contactId]
    }

    // MARK: - Toggle & Set

    /// 切换收藏状态（不带快捷号码，返回新状态）
    @discardableResult
    func toggleFavorite(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var ids = getAllFavoriteIds()
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
            defaults.set(ids, forKey: storageKey)
            // 同时移除快捷号码记录
            removeSelectedPhoneNumberInternal(for: id)
            postChangeNotification()
            return false
        } else {
            ids.append(id)
            defaults.set(ids, forKey: storageKey)
            postChangeNotification()
            return true
        }
    }

    /// 收藏联系人并设置快捷拨号号码，返回 true；若已收藏则取消收藏
    /// - Parameters:
    ///   - contactId: 联系人 ID
    ///   - phoneNumberId: CNLabeledValue<CNPhoneNumber>.identifier
    @discardableResult
    func toggleFavorite(_ contactId: String, phoneNumberId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var ids = getAllFavoriteIds()
        if let index = ids.firstIndex(of: contactId) {
            // 已收藏 → 取消收藏
            ids.remove(at: index)
            defaults.set(ids, forKey: storageKey)
            removeSelectedPhoneNumberInternal(for: contactId)
            postChangeNotification()
            return false
        } else {
            // 未收藏 → 添加收藏并记录快捷号码
            ids.append(contactId)
            defaults.set(ids, forKey: storageKey)
            setSelectedPhoneNumberInternal(for: contactId, phoneNumberId: phoneNumberId)
            postChangeNotification()
            return true
        }
    }

    /// 设置某联系人的快捷拨号号码 identifier（内部方法，调用方需加锁）
    private func setSelectedPhoneNumberInternal(for contactId: String, phoneNumberId: String) {
        var dict = defaults.dictionary(forKey: phoneKey) as? [String: String] ?? [:]
        dict[contactId] = phoneNumberId
        defaults.set(dict, forKey: phoneKey)
    }

    /// 移除某联系人的快捷拨号号码记录（内部方法，调用方需加锁）
    private func removeSelectedPhoneNumberInternal(for contactId: String) {
        var dict = defaults.dictionary(forKey: phoneKey) as? [String: String] ?? [:]
        dict.removeValue(forKey: contactId)
        defaults.set(dict, forKey: phoneKey)
    }

    /// 设置某联系人的快捷拨号号码 identifier（公开接口，自动加锁）
    func setSelectedPhoneNumber(for contactId: String, phoneNumberId: String) {
        lock.lock()
        defer { lock.unlock() }
        setSelectedPhoneNumberInternal(for: contactId, phoneNumberId: phoneNumberId)
    }

    /// 移除某联系人的快捷拨号号码记录（公开接口，自动加锁）
    func removeSelectedPhoneNumber(for contactId: String) {
        lock.lock()
        defer { lock.unlock() }
        removeSelectedPhoneNumberInternal(for: contactId)
    }

    /// 根据联系人 ID + 选中的号码 identifier，获取完整的 CNPhoneNumber（用于拨号）
    func getPhoneNumber(for contact: CNContact) -> CNPhoneNumber? {
        guard let selectedId = getSelectedPhoneNumber(for: contact.identifier) else {
            // 未记录快捷号码，返回第一个号码
            return contact.phoneNumbers.first?.value
        }
        return contact.phoneNumbers.first { $0.identifier == selectedId }?.value
    }

    // MARK: - Remove

    func removeFavorite(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        var ids = getAllFavoriteIds()
        ids.removeAll { $0 == id }
        defaults.set(ids, forKey: storageKey)
        removeSelectedPhoneNumberInternal(for: id)
        postChangeNotification()
    }

    // MARK: - Notification

    private func postChangeNotification() {
        NotificationCenter.default.post(name: .favoritesDidUpdate, object: nil)
    }
}

extension Notification.Name {
    static let favoritesDidUpdate = Notification.Name("T9uFavoritesDidUpdate")
}
