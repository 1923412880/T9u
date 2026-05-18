import SwiftUI
import Contacts
import ContactsUI
import os

private let logger = Logger(subsystem: "com.t9u.app", category: "ContactsListView")

struct ContactsListView: View {
    @State private var contacts: [CNContact] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var selectedContactId: ContactID?
    @State private var showingNewContact = false

    var filteredContacts: [CNContact] {
        guard !searchText.isEmpty else { return contacts }
        return contacts.filter {
            let name = "\($0.familyName)\($0.givenName)".localizedStandardContains(searchText)
            let phone = $0.phoneNumbers.contains {
                $0.value.stringValue.localizedStandardContains(searchText)
            }
            return name || phone
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("加载通讯录...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if contacts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.gray)
                        Text("无联系人")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("通讯录中没有联系人")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredContacts, id: \.identifier) { contact in
                            ContactRow(contact: contact)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedContactId = ContactID(id: contact.identifier)
                                }
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, prompt: "搜索联系人")
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("通讯录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingNewContact = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .task { await loadContacts() }
            .onReceive(NotificationCenter.default.publisher(for: .contactsDidUpdate)) { _ in
                Task { await loadContacts() }
            }
            .sheet(item: $selectedContactId, onDismiss: {
                Task { await loadContacts() }
            }) { contactId in
                ContactNativeDetailSheet(contactId: contactId.id)
            }
            .sheet(isPresented: $showingNewContact, onDismiss: {
                Task { await loadContacts() }
            }) {
                NewContactSheet()
            }
        }
    }

    private func loadContacts() async {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized else {
            logger.debug("无权限，跳过加载")
            await MainActor.run { isLoading = false }
            return
        }

        logger.debug("正在后台加载联系人...")
        let allContacts = await Task.detached(priority: .utility) {
            ContactStore.shared.fetchAllContactsWithDetails()
        }.value
        logger.debug("获取到 \(allContacts.count) 个联系人")
        contacts = allContacts
        isLoading = false
    }
}

// MARK: - New Contact Sheet（系统新建联系人）

private struct NewContactSheet: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = CNContactViewController(forNewContact: nil)
        vc.delegate = context.coordinator
        let nav = UINavigationController(rootViewController: vc)
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    class Coordinator: NSObject, CNContactViewControllerDelegate {
        let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            dismiss()
        }
    }
}

// MARK: - 原生联系人详情 Sheet

private struct ContactNativeDetailSheet: UIViewControllerRepresentable {
    let contactId: String
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UINavigationController {
        let store = CNContactStore()
        let keys = [
            CNContactViewController.descriptorForRequiredKeys(),
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ] as [CNKeyDescriptor]
        guard let contact = try? store.unifiedContact(withIdentifier: contactId, keysToFetch: keys) else {
            return UINavigationController()
        }
        let vc = CNContactViewController(for: contact)
        vc.delegate = context.coordinator
        vc.allowsEditing = true

        context.coordinator.contactVC = vc
        context.coordinator.contact = contact
        context.coordinator.updateCloseButton()
        context.coordinator.observeEditing(for: vc)

        // CNContactViewController 在 viewDidAppear 时会重置导航栏，
        // 用定时守护持续重插星标按钮，确保不被系统覆盖
        context.coordinator.startStarButtonGuard()

        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    class Coordinator: NSObject, CNContactViewControllerDelegate {
        let dismiss: DismissAction
        weak var contactVC: CNContactViewController?
        var contact: CNContact?
        private var editingObservation: NSKeyValueObservation?
        private weak var starButtonItem: UIBarButtonItem?
        private var starGuardTimer: Timer?

        init(dismiss: DismissAction) { self.dismiss = dismiss }

        deinit {
            editingObservation?.invalidate()
            starGuardTimer?.invalidate()
        }

        /// CNContactViewController 会持续重置导航栏按钮，此方法在展示后 2s 内反复重插星标
        func startStarButtonGuard() {
            starGuardTimer?.invalidate()
            updateStarButton()
            var count = 0
            let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] t in
                count += 1
                guard let self else { t.invalidate(); return }
                self.updateStarButton()
                if count >= 10 { t.invalidate() } // 2s 后停止
            }
            timer.tolerance = 0.05
            starGuardTimer = timer
        }

        // MARK: - 收藏按钮

        @objc private func toggleFavorite() {
            guard let contact = contact else { return }

            let isFav = FavoritesManager.shared.isFavorite(contact.identifier)

            if isFav {
                FavoritesManager.shared.toggleFavorite(contact.identifier)
                updateStarButton()
                return
            }

            let phones = contact.phoneNumbers
            if phones.isEmpty { return }

            if phones.count == 1 {
                FavoritesManager.shared.toggleFavorite(contact.identifier, phoneNumberId: phones[0].identifier)
                updateStarButton()
            } else {
                showNumberPicker(phones: phones)
            }
        }

        private func showNumberPicker(phones: [CNLabeledValue<CNPhoneNumber>]) {
            let alert = UIAlertController(title: "选择收藏号码", message: nil, preferredStyle: .actionSheet)

            for phone in phones {
                let label = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: phone.label ?? "")
                let title = "\(label) \(phone.value.stringValue)"
                alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                    guard let self = self, let contact = self.contact else { return }
                    FavoritesManager.shared.toggleFavorite(contact.identifier, phoneNumberId: phone.identifier)
                    self.updateStarButton()
                })
            }

            alert.addAction(UIAlertAction(title: "取消", style: .cancel))

            if let vc = contactVC {
                alert.popoverPresentationController?.barButtonItem = starButtonItem
                vc.present(alert, animated: true)
            }
        }

        func updateStarButton() {
            guard let vc = contactVC, let contact = contact else { return }

            let isFav = FavoritesManager.shared.isFavorite(contact.identifier)
            let imageName = isFav ? "star.fill" : "star"
            let item = UIBarButtonItem(
                image: UIImage(systemName: imageName),
                style: .plain,
                target: self,
                action: #selector(toggleFavorite)
            )
            item.tintColor = isFav ? .systemYellow : .systemBlue
            starButtonItem = item

            // 插在「编辑」按钮左侧（编辑在最右，星标在编辑左侧）
            let existing = vc.navigationItem.rightBarButtonItems ?? []
            let filtered = existing.filter { $0.action != #selector(toggleFavorite) }
            vc.navigationItem.rightBarButtonItems = filtered + [item]
        }

        // MARK: - 关闭按钮

        /// 点"关闭"时：如果在编辑模式 → 退出编辑（回到详情页）
        /// 不在编辑模式 → 关 sheet（回到列表）
        @objc func dismissSheet() {
            if let vc = contactVC, vc.isEditing {
                vc.setEditing(false, animated: true)
                return
            }
            dismiss()
        }

        /// 恢复"关闭"按钮（只在非编辑状态下添加）
        func updateCloseButton() {
            guard let vc = contactVC else { return }
            if !vc.isEditing {
                vc.navigationItem.leftBarButtonItem = UIBarButtonItem(
                    title: "关闭",
                    style: .plain,
                    target: self,
                    action: #selector(dismissSheet)
                )
            }
        }

        /// 延时恢复关闭按钮，避开 CNContactViewController 的 nav item 动画窗口
        private func scheduleRestore() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.updateCloseButton()
                self?.updateStarButton()
            }
        }

        // MARK: - 编辑状态监控

        func observeEditing(for vc: CNContactViewController) {
            editingObservation = vc.observe(\.isEditing, options: [.new]) { [weak self] (_, change) in
                guard let self = self, let isEditing = change.newValue, !isEditing else { return }
                self.scheduleRestore()
            }
        }

        // MARK: - CNContactViewControllerDelegate

        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            if contact == nil {
                // 删除联系人 → 关闭 sheet
                dismiss()
            } else {
                // 取消/保存 → 留在详情页
                scheduleRestore()
            }
        }
    }
}

// MARK: - 联系人行

private struct ContactRow: View {
    let contact: CNContact

    private var isFavorited: Bool {
        FavoritesManager.shared.isFavorite(contact.identifier)
    }

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

                if let firstPhone = contact.phoneNumbers.first {
                    Text(firstPhone.value.stringValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isFavorited {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .padding(.trailing, 4)
            }

            if contact.phoneNumbers.count > 1 {
                Text("\(contact.phoneNumbers.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(.systemGray5)))
            }
        }
        .padding(.vertical, 2)
    }
}
