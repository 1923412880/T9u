import SwiftUI
import Contacts
import UIKit
import os

private let logger = Logger(subsystem: "com.t9u.app", category: "KeypadViewModel")

class KeypadViewModel: ObservableObject {

    @Published var dialedNumber: String = "" {
        didSet {
            updateSuggestions()
            updateAttribution()
            updateSpamLabel()
        }
    }
    @Published var suggestions: [CNContact] = []
    @Published var matchedNumbers: [String: [CNLabeledValue<CNPhoneNumber>]] = [:]
    @Published var contactsAuthorizationStatus: CNAuthorizationStatus = .notDetermined
    @Published var selectedSIM: Int = 1
    @Published var attribution: PhoneAttribution? = nil
    @Published var spamLabel: String? = nil
    @Published var isContactsLoading: Bool = true

    let searchEngine = T9SearchEngine()
    private var deleteTimer: Timer?
    private var isDeleting = false
    private var clearRecordsObserver: NSObjectProtocol?
    private var historyChangeObserver: NSObjectProtocol?

    private let cacheQueue = DispatchQueue(label: "com.t9u.callFrequencyCache")
    private var _callFrequencyCache: [String: Int] = [:]
    private var callFrequencyCache: [String: Int] {
        get { cacheQueue.sync { _callFrequencyCache } }
        set { cacheQueue.sync { _callFrequencyCache = newValue } }
    }

    private func loadCallFrequency() -> [String: Int] {
        return cacheQueue.sync {
            if _callFrequencyCache.isEmpty {
                _callFrequencyCache = UserDefaults.standard.dictionary(forKey: StorageKeys.callFrequency) as? [String: Int] ?? [:]
            }
            return _callFrequencyCache
        }
    }

    @Published var recentHistory: [CallHistoryEntry] = []

    init() {
        selectedSIM = min(max(UserDefaults.standard.integer(forKey: StorageKeys.selectedSIM), 1), 2)
        loadRecentHistory()
        // 主动加载联系人
        loadContactsIfAuthorized()
        feedbackGenerator.prepare()

        clearRecordsObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(NotificationNames.recentRecordsCleared),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadRecentHistory()
        }

        historyChangeObserver = NotificationCenter.default.addObserver(
            forName: RecentDialStore.historyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadRecentHistory()
        }
    }

    private func loadContactsIfAuthorized() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized:
            isContactsLoading = true
            searchEngine.reloadContacts {
                self.isContactsLoading = false
            }
        case .notDetermined:
            Task {
                await requestContactsAccess()
            }
        case .denied, .restricted:
            isContactsLoading = false
        @unknown default:
            isContactsLoading = false
        }
    }

    deinit {
        if let observer = clearRecordsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = historyChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        searchTask?.cancel()
    }

    private func loadRecentHistory() {
        recentHistory = RecentDialStore.load()
    }

    func requestContactsAccess() async {
        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .notDetermined else { return }
        _ = try? await store.requestAccess(for: .contacts)
        contactsAuthorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
        if contactsAuthorizationStatus == .authorized {
            isContactsLoading = true
            searchEngine.reloadContacts {
                self.isContactsLoading = false
            }
        } else {
            isContactsLoading = false
        }
    }

    func digitTapped(_ digit: String) {
        if digit == "," || digit == ";" {
            if !dialedNumber.isEmpty {
                dialedNumber += digit
            }
            return
        }
        dialedNumber += digit
        playDTMFSound(digit: digit)
        playHapticFeedback()
    }

    private func playDTMFSound(digit: String) {
        guard AppSettings.shared.keypadSoundEnabled else { return }
        DTMFPlayer.shared.playDTMF(digit: digit)
    }

    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)

    private func playHapticFeedback() {
        guard AppSettings.shared.keypadHapticEnabled else { return }
        feedbackGenerator.impactOccurred()
    }

    private var searchTask: Task<Void, Never>?

    func deleteTapped() {
        if !dialedNumber.isEmpty {
            dialedNumber.removeLast()
        }
    }

    func startContinuousDelete() {
        isDeleting = true
        deleteTimer?.invalidate()
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.dialedNumber.isEmpty {
                self.stopContinuousDelete()
                return
            }
            self.dialedNumber.removeLast()
        }
        RunLoop.main.add(deleteTimer!, forMode: .common)
    }

    func stopContinuousDelete() {
        isDeleting = false
        deleteTimer?.invalidate()
        deleteTimer = nil
    }

    /// 记录拨打频次（仅在系统确认接手拨号后调用）
    func recordCall(_ number: String) {
        RecentDialStore.bumpFrequency(digits: number)
    }

    /// 拨号：只有系统真实接手后才记录通话记录与频次；
    /// 拨出后数秒内秒取消（未实际拨出）的记录会被 CallTracker 自动撤销。
    func callNumber(_ number: String) {
        RecentDialStore.dialVerified(number)
    }

    func callCurrentNumber() {
        if dialedNumber.isEmpty {
            if let last = recentHistory.first {
                dialedNumber = last.number
            }
            return
        }
        callNumber(dialedNumber)
    }

    func callFirstSuggestion() {
        guard !suggestions.isEmpty else { return }
        let contact = suggestions[0]
        if let numbers = matchedNumbers[contact.identifier],
           let firstNumber = numbers.first?.value.stringValue {
            callNumber(firstNumber)
        }
    }

    func selectSuggestion(_ number: String) {
        callNumber(number)
    }

    func switchSIM() {
        selectedSIM = selectedSIM == 1 ? 2 : 1
        UserDefaults.standard.set(selectedSIM, forKey: StorageKeys.selectedSIM)
    }

    private func updateSpamLabel() {
        guard AppSettings.shared.spamLabelEnabled else {
            spamLabel = nil
            return
        }
        let digits = dialedNumber.filter { $0.isNumber }
        spamLabel = SpamLabelService.shared.lookup(digits)
    }

    /// 兼容入口：新增一条拨出记录（带真实时间戳）
    func addToHistory(_ number: String) {
        RecentDialStore.add(number: number)
    }

    private func updateAttribution() {
        guard AppSettings.shared.attributionEnabled else {
            attribution = nil
            return
        }
        attribution = PhoneAttributionService.shared.lookup(dialedNumber)
    }

    private func updateSuggestions() {
        searchTask?.cancel()

        if dialedNumber.isEmpty {
            suggestions = []
            matchedNumbers = [:]
            return
        }

        let currentNumber = dialedNumber
        let freq = AppSettings.shared.callFrequencySortEnabled ? loadCallFrequency() : [:]

        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            // 搜索返回标识符
            let results = await self.searchEngine.searchAsync(currentNumber, callFrequency: freq)

            guard !Task.isCancelled else { return }

            // 在主线程根据标识符获取 CNContact
            await MainActor.run { [weak self] in
                guard let self = self, self.dialedNumber == currentNumber, !Task.isCancelled else { return }

                var contacts: [CNContact] = []
                var numbersDict: [String: [CNLabeledValue<CNPhoneNumber>]] = [:]

                for result in results {
                    if let contact = ContactStore.shared.fetchContact(by: result.identifier) {
                        contacts.append(contact)

                        // 匹配电话号码
                        let matchedPhones = contact.phoneNumbers.filter { phone in
                            result.matchedPhoneNumbers.contains(phone.value.stringValue)
                        }
                        numbersDict[contact.identifier] = matchedPhones.isEmpty ? contact.phoneNumbers : matchedPhones
                    }
                }

                self.suggestions = contacts
                self.matchedNumbers = numbersDict
            }
        }
    }
}

// MARK: - Storage Keys

enum StorageKeys {
    static let recentDialHistory = "recentDialHistory"
    static let recentDialHistoryV2 = "recentDialHistoryV2"
    static let callFrequency = "callFrequency"
    static let customSpamLabels = "customSpamLabels"
    static let selectedSIM = "selectedSIM"
}

// MARK: - Notification Names

enum NotificationNames {
    static let recentRecordsCleared = "RecentRecordsCleared"
    static let contactsDidUpdate = "com.t9u.contactsDidUpdate"
    static let favoritesDidUpdate = "T9uFavoritesDidUpdate"
}

// MARK: - 骚扰电话标记服务

class SpamLabelService {
    static let shared = SpamLabelService()

    private let knownLabels: [(prefix: String, label: String)] = [
        ("1069", "广告"),
        ("1065", "广告"),
        ("1068", "快递"),
        ("00", "诈骗"),
        ("+0", "诈骗"),
    ]

    private let domesticAreaCodePrefixes = Set(["010", "020", "021", "022", "023", "024", "025", "027", "028", "029"])

    func lookup(_ digits: String) -> String? {
        guard digits.count >= 3 else { return nil }

        for (prefix, label) in knownLabels {
            if digits.hasPrefix(prefix) {
                if prefix == "00" {
                    let afterPrefix = String(digits.dropFirst(2))
                    if afterPrefix.count >= 2 {
                        let potentialAreaCode = "0" + String(afterPrefix.prefix(2))
                        if domesticAreaCodePrefixes.contains(where: { $0.hasPrefix(potentialAreaCode) || potentialAreaCode.hasPrefix($0) }) {
                            continue
                        }
                    }
                }
                return label
            }
        }
        return nil
    }

    func addCustomLabel(_ number: String, label: String) {
        var customLabels = UserDefaults.standard.dictionary(forKey: StorageKeys.customSpamLabels) as? [String: String] ?? [:]
        customLabels[number] = label
        UserDefaults.standard.set(customLabels, forKey: StorageKeys.customSpamLabels)
    }

    func lookupCustom(_ digits: String) -> String? {
        let customLabels = UserDefaults.standard.dictionary(forKey: StorageKeys.customSpamLabels) as? [String: String] ?? [:]
        return customLabels[digits]
    }
}
