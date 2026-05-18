import SwiftUI
import Contacts
import ContactsUI
import MessageUI

// MARK: - iOS 26 Native-Style Contact Detail View
struct ContactDetailView: View {
    let contactId: String
    @Environment(\.dismiss) private var dismiss
    @State private var contact: CNContact?
    @State private var isLoading = true
    @State private var showingEditor = false
    @State private var showingNumberPicker = false
    @State private var isFav = false
    @State private var showingMessageCompose = false
    @State private var messageRecipient = ""
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            contactContentView
            customNavBar
        }
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $showingEditor, onDismiss: { loadContact() }) {
            EditContactSheet(contactId: contactId)
        }
        .sheet(isPresented: $showingMessageCompose) {
            MessageComposeView(recipient: $messageRecipient, isPresented: $showingMessageCompose)
        }
        .confirmationDialog("选择快捷拨号号码", isPresented: $showingNumberPicker, titleVisibility: .visible) {
            if let contact = contact {
                ForEach(contact.phoneNumbers, id: \.identifier) { phone in
                    let label = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: phone.label ?? CNLabelPhoneNumberMain)
                    Button("\(label) \(phone.value.stringValue)") {
                        let _ = FavoritesManager.shared.toggleFavorite(contactId, phoneNumberId: phone.identifier)
                        isFav = true
                        notifyFavoritesChanged()
                    }
                }
                Button("取消", role: .cancel) {}
            }
        }
        .onAppear { loadContact() }
    }

    // MARK: - 自定义导航栏

    private var customNavBar: some View {
        let opacity = min(max(scrollOffset / 120, 0), 1)
        return HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)

            Spacer()

            if opacity > 0.3 {
                Text(contact.flatMap { CNContactFormatter.string(from: $0, style: .fullName) } ?? "")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .opacity(opacity)
                    .animation(.easeInOut(duration: 0.2), value: opacity)
            }

            Spacer()

            HStack(spacing: 16) {
                Button(action: toggleFavoriteAction) {
                    Image(systemName: isFav ? "star.fill" : "star")
                        .font(.system(size: 17))
                        .foregroundStyle(isFav ? .yellow : .white)
                        .padding(8)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)

                Button("编辑") { showingEditor = true }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, safeAreaTop)
        .padding(.bottom, 8)
        .background(
            Color(.systemBackground)
                .opacity(opacity)
                .animation(.easeInOut(duration: 0.15), value: opacity)
        )
        .shadow(color: .black.opacity(opacity * 0.08), radius: 2, y: 1)
    }

    // MARK: - 主内容

    @ViewBuilder
    private var contactContentView: some View {
        if isLoading {
            ProgressView("加载联系人...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
        } else if let contact = contact {
            ScrollView {
                LazyVStack(spacing: 0) {
                    headerSection(contact)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .global).minY)
                            }
                        )

                    actionButtonsSection(contact)
                        .padding(.top, 8)

                    if !contact.phoneNumbers.isEmpty {
                        contactInfoSection(title: "电话号码") {
                            phoneNumbersContent(contact)
                        }
                    }

                    if !contact.emailAddresses.isEmpty {
                        contactInfoSection(title: "电子邮箱") {
                            emailsContent(contact)
                        }
                    }

                    if !contact.postalAddresses.isEmpty {
                        contactInfoSection(title: "地址") {
                            addressesContent(contact)
                        }
                    }

                    let notes = contact.note
                    if !notes.isEmpty {
                        contactInfoSection(title: "备注") {
                            Text(notes)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        }
                    }

                    bottomActionsSection(contact)
                }
            }
            .background(Color(.systemGroupedBackground))
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                self.scrollOffset = -value
            }
        } else {
            ContentUnavailableView("联系人不存在", systemImage: "person.slash")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - 顶部头像区域

    private func headerSection(_ contact: CNContact) -> some View {
        VStack(spacing: 16) {
            Spacer().frame(height: safeAreaTop + 60)

            ZStack {
                if contact.imageDataAvailable,
                   let imgData = contact.imageData,
                   let img = UIImage(data: imgData) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(.systemGray4), Color(.systemGray3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(initials(for: contact))
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 110, height: 110)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)

            VStack(spacing: 4) {
                Text(CNContactFormatter.string(from: contact, style: .fullName) ?? "无姓名")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if !contact.organizationName.isEmpty {
                    Text(contact.organizationName)
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer().frame(height: 8)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 操作按钮

    private func actionButtonsSection(_ contact: CNContact) -> some View {
        HStack(spacing: 32) {
            if !contact.phoneNumbers.isEmpty {
                ActionCircleButton(icon: "message.fill", label: "信息", color: .green) {
                    if let firstPhone = contact.phoneNumbers.first?.value.stringValue {
                        openSMS(firstPhone)
                    }
                }
                ActionCircleButton(icon: "phone.fill", label: "呼叫", color: .green) {
                    if let firstPhone = contact.phoneNumbers.first?.value.stringValue {
                        callNumber(firstPhone)
                    }
                }
            }
            if !contact.emailAddresses.isEmpty {
                ActionCircleButton(icon: "envelope.fill", label: "邮件", color: .blue) {
                    if let emailStr = contact.emailAddresses.first?.value as String?,
                       let url = URL(string: "mailto:\(emailStr)") {
                        UIApplication.shared.open(url, options: [:])
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    // MARK: - 电话号码行

    private func phoneNumbersContent(_ contact: CNContact) -> some View {
        ForEach(Array(contact.phoneNumbers.enumerated()), id: \.element.identifier) { index, phone in
            let label = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: phone.label ?? CNLabelPhoneNumberMain)
            let number = phone.value.stringValue

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(number)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                        Text(label)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .contextMenu {
                    Button { callNumber(number) } label: {
                        Label("呼叫", systemImage: "phone.fill")
                    }
                    Button { openSMS(number) } label: {
                        Label("发送信息", systemImage: "message.fill")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button { callNumber(number) } label: {
                        Label("呼叫", systemImage: "phone.fill")
                    }
                    .tint(.green)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { openSMS(number) } label: {
                        Label("信息", systemImage: "message.fill")
                    }
                    .tint(.blue)
                }

                if index < contact.phoneNumbers.count - 1 {
                    Divider().padding(.leading, 16)
                }
            }
        }
    }

    // MARK: - 邮箱行

    private func emailsContent(_ contact: CNContact) -> some View {
        ForEach(Array(contact.emailAddresses.enumerated()), id: \.element.identifier) { index, email in
            let label = CNLabeledValue<NSString>.localizedString(forLabel: email.label ?? CNLabelWork)
            let emailStr = email.value as String

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(emailStr)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                        Text(label)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if index < contact.emailAddresses.count - 1 {
                    Divider().padding(.leading, 16)
                }
            }
        }
    }

    // MARK: - 地址行

    private func addressesContent(_ contact: CNContact) -> some View {
        ForEach(Array(contact.postalAddresses.enumerated()), id: \.element.identifier) { index, address in
            let label = CNLabeledValue<CNPostalAddress>.localizedString(forLabel: address.label ?? CNLabelWork)
            let formatted = CNPostalAddressFormatter().string(from: address.value)

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(formatted)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                        Text(label)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if index < contact.postalAddresses.count - 1 {
                    Divider().padding(.leading, 16)
                }
            }
        }
    }

    // MARK: - 通用信息 Section（iOS 26 圆角卡片风格）

    private func contactInfoSection<T: View>(title: String, @ViewBuilder content: () -> T) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.none)
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - 底部操作

    private func bottomActionsSection(_ contact: CNContact) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("操作")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.none)
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                Button { shareContact(contact) } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        Text("共享联系人")
                            .font(.system(size: 16))
                            .foregroundStyle(.blue)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 56)

                Button { toggleFavoriteAction() } label: {
                    HStack {
                        Image(systemName: isFav ? "star.fill" : "star")
                            .font(.system(size: 16))
                            .foregroundStyle(isFav ? .orange : .blue)
                            .frame(width: 24)
                        Text(isFav ? "移出个人收藏" : "添加到个人收藏")
                            .font(.system(size: 16))
                            .foregroundStyle(.blue)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)

            Spacer().frame(height: 40)
        }
    }

    // MARK: - 收藏操作

    private func toggleFavoriteAction() {
        guard let contact = contact else { return }

        if isFav {
            FavoritesManager.shared.toggleFavorite(contactId)
            isFav = false
            notifyFavoritesChanged()
            return
        }

        let phones = contact.phoneNumbers
        if phones.isEmpty {
            FavoritesManager.shared.toggleFavorite(contactId)
            isFav = true
            notifyFavoritesChanged()
        } else if phones.count == 1 {
            if let firstPhone = phones.first {
                FavoritesManager.shared.toggleFavorite(contactId, phoneNumberId: firstPhone.identifier)
                isFav = true
                notifyFavoritesChanged()
            }
        } else {
            showingNumberPicker = true
        }
    }

    private func notifyFavoritesChanged() {
        NotificationCenter.default.post(name: .favoritesDidUpdate, object: nil)
    }

    // MARK: - 拨号 / 短信

    private func callNumber(_ number: String) {
        let cleaned = number.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        guard !cleaned.isEmpty,
              let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let url = URL(string: "tel:\(encoded)") else { return }
        UIApplication.shared.open(url, options: [:])
    }

    private func openSMS(_ number: String) {
        let cleaned = number.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        guard !cleaned.isEmpty else { return }
        if MFMessageComposeViewController.canSendText() {
            messageRecipient = number
            showingMessageCompose = true
        } else {
            guard let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
                  let url = URL(string: "sms:\(encoded)") else { return }
            UIApplication.shared.open(url, options: [:])
        }
    }

    // MARK: - 共享联系人

    private func shareContact(_ contact: CNContact) {
        let vCardData = try? CNContactVCardSerialization.data(with: [contact])
        let items: [Any] = {
            if let data = vCardData { return [data] }
            return [CNContactFormatter.string(from: contact, style: .fullName) ?? "联系人"]
        }()
        let avc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(avc, animated: true)
        }
    }

    // MARK: - 加载联系人

    private func loadContact() {
        isLoading = true
        isFav = FavoritesManager.shared.isFavorite(contactId)
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
        ]
        DispatchQueue.global(qos: .userInitiated).async { [contactId] in
            let store = CNContactStore()
            do {
                let c = try store.unifiedContact(withIdentifier: contactId, keysToFetch: keys)
                DispatchQueue.main.async {
                    self.contact = c
                    self.isLoading = false
                }
            } catch {
                NSLog("[T9U-DEBUG] ContactDetailView: 加载联系人失败 id=\(contactId) error=\(error)")
                DispatchQueue.main.async {
                    self.contact = nil
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - 辅助

    private var safeAreaTop: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return 54
        }
        return window.safeAreaInsets.top
    }

    private func initials(for contact: CNContact) -> String {
        let last = contact.familyName.first.map(String.init) ?? ""
        let first = contact.givenName.first.map(String.init) ?? ""
        return (last + first).isEmpty ? "#" : last + first
    }
}

// MARK: - PreferenceKey for scroll offset

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - 操作按钮组件（iOS 26 风格圆形按钮）

private struct ActionCircleButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 60, height: 60)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: - 编辑联系人 Sheet

private struct EditContactSheet: UIViewControllerRepresentable {
    let contactId: String
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UINavigationController {
        let store = CNContactStore()
        let keys = [CNContactViewController.descriptorForRequiredKeys()]
        guard let contact = try? store.unifiedContact(withIdentifier: contactId, keysToFetch: keys) else {
            return UINavigationController()
        }
        let vc = CNContactViewController(for: contact)
        vc.delegate = context.coordinator
        vc.allowsEditing = true
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    class Coordinator: NSObject, CNContactViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            dismiss()
        }
    }
}

// MARK: - 短信发送 View

private struct MessageComposeView: UIViewControllerRepresentable {
    @Binding var recipient: String
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = [recipient]
        vc.messageComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        var isPresented: Binding<Bool>
        init(isPresented: Binding<Bool>) { self.isPresented = isPresented }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            isPresented.wrappedValue = false
        }
    }
}
