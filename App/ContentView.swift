import SwiftUI

struct ContentView: View {
    @State private var selectedTab: DialTab = .keypad

    enum DialTab: String, CaseIterable, Hashable {
        case favorites
        case recents
        case contacts
        case keypad
        case settings

        var title: String {
            switch self {
            case .favorites: return "个人收藏"
            case .recents:   return "最近通话"
            case .contacts:  return "通讯录"
            case .keypad:    return "拨号键盘"
            case .settings:  return "设置"
            }
        }

        var icon: String {
            switch self {
            case .favorites: return "star.fill"
            case .recents:   return "clock.fill"
            case .contacts:  return "person.circle.fill"
            case .keypad:    return "circle.grid.3x3.fill"
            case .settings:  return "gearshape.fill"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(value: .favorites) {
                FavoritesView()
            } label: {
                Label(DialTab.favorites.title, systemImage: DialTab.favorites.icon)
            }

            Tab(value: .recents) {
                RecentsView()
            } label: {
                Label(DialTab.recents.title, systemImage: DialTab.recents.icon)
            }

            Tab(value: .contacts) {
                ContactsListView()
            } label: {
                Label(DialTab.contacts.title, systemImage: DialTab.contacts.icon)
            }

            Tab(value: .keypad) {
                KeypadView()
            } label: {
                Label(DialTab.keypad.title, systemImage: DialTab.keypad.icon)
            }
        }
        .tint(.blue)
    }
}