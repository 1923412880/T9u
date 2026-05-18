import Foundation
import Contacts
import os

private let logger = Logger(subsystem: "com.t9u.app", category: "MockContactSeeder")

extension Notification.Name {
    static let contactsDidUpdate = Notification.Name(NotificationNames.contactsDidUpdate)
}

struct MockContactSeeder {

    static func clearAndReseed() {
        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized else {
            logger.debug("无通讯录权限，跳过")
            return
        }

        clearAllContacts(store: store)
        let mockContacts = Self.generateMockContacts()
        seedContacts(mockContacts, store: store)
    }

    static func seedIfNeeded() {
        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized else {
            logger.debug("无通讯录权限，跳过")
            return
        }

        let existingPhones = Set(fetchExistingPhoneNumbers(store: store))
        logger.debug("已存在 \(existingPhones.count) 个联系人号码")

        let mockContacts = Self.generateMockContacts()
        let targetCount = mockContacts.count
        guard existingPhones.count < targetCount else {
            logger.debug("已有 \(existingPhones.count) 个联系人，跳过播种")
            return
        }

        seedContacts(mockContacts, store: store)
    }

    private static func clearAllContacts(store: CNContactStore) {
        let keys = [CNContactIdentifierKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var ids: [String] = []
        try? store.enumerateContacts(with: request) { contact, _ in
            ids.append(contact.identifier)
        }

        guard !ids.isEmpty else {
            logger.debug("通讯录已空，无需清理")
            return
        }

        let batchSize = 100
        for chunk in ids.chunked(into: batchSize) {
            let saveRequest = CNSaveRequest()
            for id in chunk {
                guard let cnContact = try? store.unifiedContact(withIdentifier: id, keysToFetch: keys),
                      let mutable = cnContact.mutableCopy() as? CNMutableContact else { continue }
                saveRequest.delete(mutable)
            }
            try? store.execute(saveRequest)
        }
        logger.debug("已清除 \(ids.count) 个联系人")
    }

    private static func fetchExistingPhoneNumbers(store: CNContactStore) -> [String] {
        let keys = [CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var phones: [String] = []
        try? store.enumerateContacts(with: request) { contact, _ in
            for phone in contact.phoneNumbers {
                phones.append(phone.value.stringValue.filter { $0.isNumber })
            }
        }
        return phones
    }

    private static func seedContacts(_ mockContacts: [MockContact], store: CNContactStore) {
        let existingPhones = Set(fetchExistingPhoneNumbers(store: store))
        var addedCount = 0

        for mock in mockContacts {
            let phoneDigits = mock.phone.filter { $0.isNumber }
            if !existingPhones.isEmpty, existingPhones.contains(phoneDigits) { continue }

            let contact = CNMutableContact()
            contact.givenName = mock.givenName
            contact.familyName = mock.familyName
            contact.organizationName = mock.org

            var phoneNumbers: [CNLabeledValue<CNPhoneNumber>] = []
            phoneNumbers.append(
                CNLabeledValue(
                    label: mock.label,
                    value: CNPhoneNumber(stringValue: mock.phone)
                )
            )
            if let phone2 = mock.phone2 {
                phoneNumbers.append(
                    CNLabeledValue(
                        label: CNLabelPhoneNumberMobile,
                        value: CNPhoneNumber(stringValue: phone2)
                    )
                )
            }
            if let phone3 = mock.phone3 {
                phoneNumbers.append(
                    CNLabeledValue(
                        label: CNLabelWork,
                        value: CNPhoneNumber(stringValue: phone3)
                    )
                )
            }
            contact.phoneNumbers = phoneNumbers

            let request = CNSaveRequest()
            request.add(contact, toContainerWithIdentifier: nil)
            do {
                try store.execute(request)
                addedCount += 1
            } catch {
                logger.error("保存失败 \(mock.givenName): \(error.localizedDescription)")
            }
        }
        logger.debug("新增 \(addedCount) 个联系人")

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .contactsDidUpdate, object: nil)
        }
    }

    // MARK: - Mock Contact Data

    private struct MockContact {
        let givenName: String
        let familyName: String
        let org: String
        let label: String
        let phone: String
        let phone2: String?
        let phone3: String?

        init(givenName: String, familyName: String = "", org: String = "", label: String = CNLabelPhoneNumberMobile, phone: String, phone2: String? = nil, phone3: String? = nil) {
            self.givenName = givenName
            self.familyName = familyName
            self.org = org
            self.label = label
            self.phone = phone
            self.phone2 = phone2
            self.phone3 = phone3
        }
    }

    private static func generateMockContacts() -> [MockContact] {
        [
            // ── 多号码联系人（2~3个号码）──
            MockContact(givenName: "张三",   org: "字节跳动",   phone: "13800138001", phone2: "18811110001", phone3: "01012345678"),
            MockContact(givenName: "王五",   org: "腾讯科技",   phone: "13700137001", phone2: "18622220002"),
            MockContact(givenName: "陈经理", org: "华为技术",   label: CNLabelWork,   phone: "13500135001", phone2: "18533330003", phone3: "07551234567"),
            MockContact(givenName: "周杰",   org: "美团",       phone: "13200132001", phone2: "18944440004"),
            MockContact(givenName: "客服中心", org: "中国移动", phone: "4008008800",  phone2: "10086"),
            MockContact(givenName: "建设银行", org: "中国建设银行", phone: "95533", phone2: "4008200588"),
            MockContact(givenName: "王芳",   org: "快手",       phone: "15900159001", phone2: "18766660006"),
            MockContact(givenName: "赵敏",   org: "小红书",     phone: "17100171001", phone2: "18288880008"),
            MockContact(givenName: "刘洋",   org: "拼多多",     phone: "17200172001", phone2: "18999990009"),
            MockContact(givenName: "李四",   org: "阿里巴巴",   phone: "13900139001", phone2: "057112345678"),

            // ── 单号码联系人 ──
            MockContact(givenName: "赵六",   org: "",           phone: "13600136001"),
            MockContact(givenName: "刘老师", org: "北京大学",   phone: "13400134001"),
            MockContact(givenName: "孙明",   org: "小米科技",   phone: "13300133001"),
            MockContact(givenName: "吴芳",   org: "京东集团",   phone: "13100131001"),
            MockContact(givenName: "郑涛",   org: "网易",       label: CNLabelWork, phone: "13000130001"),
            MockContact(givenName: "外卖",   org: "美团外卖",   phone: "10105757"),
            MockContact(givenName: "滴滴",   org: "滴滴出行",   phone: "4000000999"),
            MockContact(givenName: "顺丰",   org: "顺丰速运",   phone: "95338"),
            MockContact(givenName: "张伟",   org: "百度",       phone: "15800158001"),
            MockContact(givenName: "李娜",   org: "哔哩哔哩",   phone: "17000170001"),

            // ── 新增：混合号码联系人（含固定电话）──
            MockContact(givenName: "黄总",   org: "比亚迪",     phone: "18800188001", phone2: "07551234001"),
            MockContact(givenName: "杨会计", org: "中兴通讯",   label: CNLabelWork, phone: "18900189001", phone2: "02112345678"),
            MockContact(givenName: "马医生", org: "协和医院",   phone: "13601360001", phone2: "01087654321"),
            MockContact(givenName: "罗师傅", org: "滴滴出行",   phone: "15000150001"),
            MockContact(givenName: "唐女士", org: "万达集团",   phone: "15100151001"),
            MockContact(givenName: "宋律师", org: "金杜律所",   label: CNLabelWork, phone: "15200152001", phone2: "02812345678"),
            MockContact(givenName: "韩老师", org: "清华大学",   phone: "15300153001"),
            MockContact(givenName: "曹工",   org: "大疆创新",   phone: "15500155001"),
            MockContact(givenName: "邓老板", org: "",           phone: "15600156001", phone2: "4008880001"),
            MockContact(givenName: "魏师傅", org: "",           phone: "15700157001"),
        ]
    }
}

// MARK: - Array Chunk Extension
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
