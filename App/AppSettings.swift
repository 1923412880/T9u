import Foundation
import UIKit
import os

private let logger = Logger(subsystem: "com.t9u.app", category: "AppSettings")

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var keypadSoundEnabled: Bool {
        didSet { UserDefaults.standard.set(keypadSoundEnabled, forKey: Keys.keypadSoundEnabled) }
    }

    @Published var keypadHapticEnabled: Bool {
        didSet { UserDefaults.standard.set(keypadHapticEnabled, forKey: Keys.keypadHapticEnabled) }
    }

    @Published var longPressQuickDialEnabled: Bool {
        didSet { UserDefaults.standard.set(longPressQuickDialEnabled, forKey: Keys.longPressQuickDialEnabled) }
    }

    @Published var attributionEnabled: Bool {
        didSet { UserDefaults.standard.set(attributionEnabled, forKey: Keys.attributionEnabled) }
    }

    @Published var spamLabelEnabled: Bool {
        didSet { UserDefaults.standard.set(spamLabelEnabled, forKey: Keys.spamLabelEnabled) }
    }

    @Published var callFrequencySortEnabled: Bool {
        didSet { UserDefaults.standard.set(callFrequencySortEnabled, forKey: Keys.callFrequencySortEnabled) }
    }

    @Published var maxRecentRecords: Int {
        didSet { UserDefaults.standard.set(maxRecentRecords, forKey: Keys.maxRecentRecords) }
    }

    private struct Keys {
        static let keypadSoundEnabled = "keypad_sound_enabled"
        static let keypadHapticEnabled = "keypad_haptic_enabled"
        static let longPressQuickDialEnabled = "long_press_quick_dial_enabled"
        static let attributionEnabled = "attribution_enabled"
        static let spamLabelEnabled = "spam_label_enabled"
        static let callFrequencySortEnabled = "call_frequency_sort_enabled"
        static let maxRecentRecords = "max_recent_records"
        static let clearRecordsTrigger = "clear_records_trigger"
        static let appVersion = "app_version"
        static let dbVersion = "db_version"
        static let dbLastUpdated = "db_last_updated"
    }

    private var clearRecordsObserver: NSObjectProtocol?

    private init() {
        UserDefaults.standard.register(defaults: [
            Keys.keypadSoundEnabled: true,
            Keys.keypadHapticEnabled: false,
            Keys.longPressQuickDialEnabled: true,
            Keys.attributionEnabled: true,
            Keys.spamLabelEnabled: true,
            Keys.callFrequencySortEnabled: true,
            Keys.maxRecentRecords: 100
        ])

        self.keypadSoundEnabled = UserDefaults.standard.bool(forKey: Keys.keypadSoundEnabled)
        self.keypadHapticEnabled = UserDefaults.standard.bool(forKey: Keys.keypadHapticEnabled)
        self.longPressQuickDialEnabled = UserDefaults.standard.bool(forKey: Keys.longPressQuickDialEnabled)
        self.attributionEnabled = UserDefaults.standard.bool(forKey: Keys.attributionEnabled)
        self.spamLabelEnabled = UserDefaults.standard.bool(forKey: Keys.spamLabelEnabled)
        self.callFrequencySortEnabled = UserDefaults.standard.bool(forKey: Keys.callFrequencySortEnabled)
        self.maxRecentRecords = UserDefaults.standard.integer(forKey: Keys.maxRecentRecords)

        registerAppVersion()
        observeClearRecordsTrigger()
    }

    func syncFromUserDefaults() {
        let newSound = UserDefaults.standard.bool(forKey: Keys.keypadSoundEnabled)
        if newSound != keypadSoundEnabled { keypadSoundEnabled = newSound }

        let newHaptic = UserDefaults.standard.bool(forKey: Keys.keypadHapticEnabled)
        if newHaptic != keypadHapticEnabled { keypadHapticEnabled = newHaptic }

        let newLongPress = UserDefaults.standard.bool(forKey: Keys.longPressQuickDialEnabled)
        if newLongPress != longPressQuickDialEnabled { longPressQuickDialEnabled = newLongPress }

        let newAttribution = UserDefaults.standard.bool(forKey: Keys.attributionEnabled)
        if newAttribution != attributionEnabled { attributionEnabled = newAttribution }

        let newSpam = UserDefaults.standard.bool(forKey: Keys.spamLabelEnabled)
        if newSpam != spamLabelEnabled { spamLabelEnabled = newSpam }

        let newFreqSort = UserDefaults.standard.bool(forKey: Keys.callFrequencySortEnabled)
        if newFreqSort != callFrequencySortEnabled { callFrequencySortEnabled = newFreqSort }

        let newMaxRecords = UserDefaults.standard.integer(forKey: Keys.maxRecentRecords)
        if newMaxRecords != maxRecentRecords { maxRecentRecords = newMaxRecords }
    }

    func updateDatabaseInfo(version: String, date: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        UserDefaults.standard.set(version, forKey: Keys.dbVersion)
        UserDefaults.standard.set(formatter.string(from: date), forKey: Keys.dbLastUpdated)
    }

    private func registerAppVersion() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        UserDefaults.standard.set(version, forKey: Keys.appVersion)
    }

    deinit {
        if let observer = clearRecordsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func observeClearRecordsTrigger() {
        clearRecordsObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if UserDefaults.standard.bool(forKey: Keys.clearRecordsTrigger) {
                UserDefaults.standard.set(false, forKey: Keys.clearRecordsTrigger)
                self.clearRecentRecords()
            }
        }
    }

    private func clearRecentRecords() {
        UserDefaults.standard.set([], forKey: StorageKeys.recentDialHistory)
        UserDefaults.standard.set([String: Int](), forKey: StorageKeys.callFrequency)
        NotificationCenter.default.post(name: NSNotification.Name(NotificationNames.recentRecordsCleared), object: nil)
    }
}
