import Foundation
import Contacts
import os

private let logger = Logger(subsystem: "com.t9u.app", category: "ContactStore")

// 线程安全的联系人数据结构
struct SafeContactData {
    let identifier: String
    let givenName: String
    let familyName: String
    let middleName: String
    let organizationName: String
    let nickname: String
    let jobTitle: String
    let departmentName: String
    let note: String
    let emailUsernames: [String]
    let phoneNumbers: [String]
}

class ContactStore {
    static let shared = ContactStore()
    
    private let store = CNContactStore()
    
    // 搜索所需的最小字段（加快加载速度，只加确定安全的 key）
    static let searchKeys: [CNKeyDescriptor] = [
        CNContactGivenNameKey,
        CNContactFamilyNameKey,
        CNContactMiddleNameKey,
        CNContactPhoneNumbersKey,
        CNContactOrganizationNameKey,
        CNContactNicknameKey,
        CNContactEmailAddressesKey,
    ] as [CNKeyDescriptor]
    
    // 详情页所需的所有字段
    static let sharedKeys: [CNKeyDescriptor] = [
        CNContactGivenNameKey,
        CNContactFamilyNameKey,
        CNContactMiddleNameKey,
        CNContactPhoneNumbersKey,
        CNContactOrganizationNameKey,
        CNContactNicknameKey,
        CNContactThumbnailImageDataKey,
        CNContactImageDataKey,
        CNContactJobTitleKey,
        CNContactDepartmentNameKey,
        CNContactEmailAddressesKey,
    ] as [CNKeyDescriptor]
    
    private init() {}
    
    func requestAccess() async -> Bool {
        do {
            return try await store.requestAccess(for: .contacts)
        } catch {
            logger.error("请求通讯录权限失败: \(error.localizedDescription)")
            return false
        }
    }
    
    // 搜索用：只获取必要字段，速度快，返回线程安全的数据
    func fetchContactsForSearchData() -> [SafeContactData] {
        let request = CNContactFetchRequest(keysToFetch: Self.searchKeys)
        request.sortOrder = .familyName
        
        var result: [SafeContactData] = []
        
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                guard !contact.phoneNumbers.isEmpty else { return }
                
                let emailUsernames = contact.emailAddresses.compactMap { email -> String? in
                    let addr = email.value as String
                    if let atRange = addr.range(of: "@") {
                        return String(addr[..<atRange.lowerBound])
                    }
                    return nil
                }
                
                let phones = contact.phoneNumbers.map { $0.value.stringValue }
                
                let data = SafeContactData(
                    identifier: contact.identifier,
                    givenName: contact.givenName,
                    familyName: contact.familyName,
                    middleName: contact.middleName,
                    organizationName: contact.organizationName,
                    nickname: contact.nickname,
                    jobTitle: "",      // searchKeys 不含此 key，不访问
                    departmentName: "", // searchKeys 不含此 key，不访问
                    note: "",          // searchKeys 不含此 key，不访问
                    emailUsernames: emailUsernames,
                    phoneNumbers: phones
                )
                result.append(data)
            }
        } catch {
            logger.error("获取联系人失败: \(error.localizedDescription)")
        }
        
        return result
    }
    
    // 搜索用：只获取必要字段，速度快
    func fetchContactsForSearch() -> [CNContact] {
        let request = CNContactFetchRequest(keysToFetch: Self.searchKeys)
        request.sortOrder = .familyName
        
        var contacts: [CNContact] = []
        
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                guard !contact.phoneNumbers.isEmpty else { return }
                contacts.append(contact)
            }
        } catch {
            logger.error("获取联系人失败: \(error.localizedDescription)")
        }
        
        return contacts
    }
    
    // 详情页使用：获取所有字段
    func fetchAllContacts() -> [CNContact] {
        let request = CNContactFetchRequest(keysToFetch: Self.sharedKeys)
        request.sortOrder = .familyName
        
        var contacts: [CNContact] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                contacts.append(contact)
            }
        } catch {
            logger.error("获取带详情联系人失败: \(error.localizedDescription)")
        }
        return contacts
    }
    
    // 根据标识符获取单个联系人（在主线程调用）
    func fetchContact(by identifier: String) -> CNContact? {
        do {
            return try store.unifiedContact(withIdentifier: identifier, keysToFetch: Self.sharedKeys)
        } catch {
            logger.error("获取联系人详情失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    // 兼容旧接口
    func fetchAllContactsWithDetails() -> [CNContact] {
        return fetchAllContacts()
    }
}
