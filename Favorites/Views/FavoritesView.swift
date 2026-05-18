import SwiftUI
import Contacts
import ContactsUI
import os

private let logger = Logger(subsystem: "com.t9u.app", category: "FavoritesView")

struct FavoritesView: View {
    @State private var favoriteContacts: [CNContact] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("加载收藏...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if favoriteContacts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.yellow)
                        Text("个人收藏")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("在联系人详情页点击 ★ 即可收藏")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(favoriteContacts, id: \.identifier) { contact in
                            FavoriteRow(contact: contact) {
                                makeCall(to: contact)
                            } onStarTap: {
                                FavoritesManager.shared.removeFavorite(contact.identifier)
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let contact = favoriteContacts[index]
                                FavoritesManager.shared.removeFavorite(contact.identifier)
                            }
                            loadFavorites()
                        }
                    }
                    .listStyle(.plain)
                    .toolbar {
                        EditButton()
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("个人收藏")
            .navigationBarTitleDisplayMode(.inline)
            .task { loadFavorites() }
            .onReceive(NotificationCenter.default.publisher(for: .favoritesDidUpdate)) { _ in
                loadFavorites()
            }
        }
    }

    // MARK: - 直接拨号

    /// 使用 FavoritesManager 中存储的快捷号码拨号
    private func makeCall(to contact: CNContact) {
        guard let phoneNumber = FavoritesManager.shared.getPhoneNumber(for: contact) else { return }
        let cleaned = phoneNumber.stringValue
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .joined()
        guard let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let url = URL(string: "tel:\(encoded)") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func loadFavorites() {
        isLoading = true
        Task {
            let contacts = await Task.detached(priority: .utility) {
                FavoritesManager.shared.getAllFavoriteContacts()
            }.value
            await MainActor.run {
                favoriteContacts = contacts
                isLoading = false
            }
        }
    }
}

// MARK: - Favorite Row（支持点击拨号 + 五角星取消收藏 + 动画）

private struct FavoriteRow: View {
    let contact: CNContact
    let onTap: () -> Void
    let onStarTap: () -> Void

    @State private var isStarPressed = false

    private var displayName: String {
        [contact.familyName, contact.givenName, contact.middleName]
            .filter { !$0.isEmpty }
            .joined()
    }

    private var initials: String {
        let last = contact.familyName.first.map { String($0) } ?? ""
        let first = contact.givenName.first.map { String($0) } ?? ""
        return last + first
    }

    /// 显示收藏时选中的快捷拨号号码
    private var favoritePhoneLabel: String {
        guard let selectedId = FavoritesManager.shared.getSelectedPhoneNumber(for: contact.identifier),
              let labeled = contact.phoneNumbers.first(where: { $0.identifier == selectedId }) else {
            return contact.phoneNumbers.first.map { $0.value.stringValue } ?? ""
        }
        let label = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: labeled.label ?? "")
        return "\(label) \(labeled.value.stringValue)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let imageData = contact.thumbnailImageData,
                   let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle()
                        .fill(Color(.systemGray4))
                        .overlay(
                            Text(initials.isEmpty ? "#" : initials)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(favoritePhoneLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: {
                // 五角星点击动画：放大 + 旋转 + 缩放回到最小然后恢复
                withAnimation(.interpolatingSpring(stiffness: 170, damping: 8)) {
                    isStarPressed = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    onStarTap()
                    withAnimation(.easeOut(duration: 0.2)) {
                        isStarPressed = false
                    }
                }
            }) {
                Image(systemName: "star.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.yellow)
                    .scaleEffect(isStarPressed ? 0.2 : 1.0)
                    .rotationEffect(.degrees(isStarPressed ? 180 : 0))
                    .opacity(isStarPressed ? 0.3 : 1.0)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
