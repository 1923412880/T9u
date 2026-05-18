import SwiftUI
import Contacts
import UIKit
import os

private let logger = Logger(subsystem: "com.t9u.app", category: "T9uApp")

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        AppSettings.shared.syncFromUserDefaults()
        return true
    }
}

@main
struct T9uApp: App {
    @State private var isReady = false
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            if isReady {
                ContentView()
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                        AppSettings.shared.syncFromUserDefaults()
                    }
            } else {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("正在初始化通讯录...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .task {
                    await initializeContacts()
                }
            }
        }
    }

    private func initializeContacts() async {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            guard (try? await CNContactStore().requestAccess(for: .contacts)) == true else {
                isReady = true
                return
            }
        }
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            isReady = true
            return
        }

        #if DEBUG
        await Task.detached(priority: .utility) {
            MockContactSeeder.clearAndReseed()
        }.value
        #endif

        isReady = true
    }
}
