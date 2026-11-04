import SwiftUI
import Contacts
import ContactsUI
import AudioToolbox

// MARK: - View Extension for Conditional Long Press
extension View {
    func applyLongPressQuickDial(enabled: Bool, action: @escaping () -> Void) -> some View {
        self.modifier(LongPressQuickDialModifier(enabled: enabled, action: action))
    }
}

private struct LongPressQuickDialModifier: ViewModifier {
    let enabled: Bool
    let action: () -> Void
    
    func body(content: Content) -> some View {
        if enabled {
            content.onLongPressGesture(minimumDuration: 1.0) {
                action()
            }
        } else {
            content
        }
    }
}

struct KeypadView: View {
    
    @StateObject private var viewModel = KeypadViewModel()
    @State private var expandedContacts: Set<String> = []
    @State private var showAddContact = false
    @State private var isDeletePressed = false
    @State private var justDidLongPress = false
    @State private var showingSettings = false
    @State private var showSIMHint = false
    @AppStorage("sim1_name") private var sim1Name: String = "SIM1"
    @AppStorage("sim2_name") private var sim2Name: String = "SIM2"
    @Environment(\.colorScheme) private var colorScheme
    
    private let digitRows: [[DigitKey]] = [
        [.init(digit: "1", sub: ""), .init(digit: "2", sub: "ABC"), .init(digit: "3", sub: "DEF")],
        [.init(digit: "4", sub: "GHI"), .init(digit: "5", sub: "JKL"), .init(digit: "6", sub: "MNO")],
        [.init(digit: "7", sub: "PQRS"), .init(digit: "8", sub: "TUV"), .init(digit: "9", sub: "WXYZ")],
        [.init(digit: "*", sub: nil, longPressAction: ","),
         .init(digit: "0", sub: "+"),
         .init(digit: "#", sub: nil, longPressAction: ";")],
    ]
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            // ── 顶层区域：号码、归属地、联系人建议 ──
            VStack(spacing: 0) {
                
                NumberDisplayView(number: viewModel.dialedNumber)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                
                // 归属地 + 骚扰标记（固定高度，避免列表跳动）
                HStack(spacing: 8) {
                    Spacer()
                    if AppSettings.shared.attributionEnabled, let attr = viewModel.attribution {
                        Text(attributionText(attr))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if AppSettings.shared.spamLabelEnabled, let spam = viewModel.spamLabel {
                        HStack(spacing: 4) {
                            Image(systemName: spamIcon(spam))
                                .font(.caption2)
                            Text(spam)
                                .font(.caption)
                        }
                        .foregroundStyle(spamColor(spam))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(spamColor(spam).opacity(0.12))
                        .clipShape(Capsule())
                    }
                    Spacer()
                }
                .frame(height: 20)
                .padding(.top, 2)
                
                // 联系人建议 或 加载提示
                if viewModel.isContactsLoading && !viewModel.dialedNumber.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("正在加载联系人...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(height: 60)
                    .background(Color(.systemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                } else if !viewModel.dialedNumber.isEmpty && !viewModel.suggestions.isEmpty {
                    suggestionList
                        .background(Color(.systemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .onChange(of: viewModel.dialedNumber) { _ in
                            expandedContacts.removeAll()
                        }
                }
                
                Spacer(minLength: 0)
            }
            .padding(.top, 34)
            .frame(maxHeight: .infinity)
            
            // ── 拨号盘 + 底部按钮，从底部向上固定 ──
            VStack(spacing: 12) {
                keypadGrid
                
                ZStack {
                    HStack {
                        Spacer()
                        callButton
                            .frame(width: 75, height: 75)
                        Spacer()
                    }
                    HStack(spacing: 26) {
                        Color.clear.frame(width: 75, height: 75)
                        Color.clear.frame(width: 75, height: 75)
                        deleteButton
                            .frame(width: 75, height: 75)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)  // 距底部 24pt
        }
        .task {
            if CNContactStore.authorizationStatus(for: .contacts) == .authorized {
                viewModel.searchEngine.reloadContacts {
                    // 加载完成，ViewModel中的isContactsLoading会在回调中设置为false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .contactsDidUpdate)) { _ in
            viewModel.searchEngine.reloadContacts()
        }
        // ── 顶层覆盖层：SIM 按钮（固定位置，不受内容变化影响）──
        .overlay(alignment: .topLeading) {
            simButton
                .padding(.leading, 16)
                .padding(.top, 8)
        }
        .overlay(alignment: .topTrailing) {
            if !viewModel.dialedNumber.isEmpty {
                addContactButton
                    .padding(.trailing, 16)
                    .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showAddContact) {
            AddContactView(phoneNumber: viewModel.dialedNumber.filter { $0.isNumber || $0 == "+" })
        }
        .sheet(isPresented: $showingSettings) {
            NavigationView {
                Form {
                    Section(header: Text("SIM卡名称")) {
                        TextField("SIM 1 名称", text: $sim1Name)
                        TextField("SIM 2 名称", text: $sim2Name)
                    }
                }
                .navigationTitle("SIM设置")
                .navigationBarItems(trailing: Button("完成") {
                    showingSettings = false
                })
            }
        }
    }
    
    // MARK: - SIM Button
    private var simButton: some View {
        Button {
            viewModel.switchSIM()
            showSIMHint = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "simcard")
                    .font(.caption)
                Text(simName(for: viewModel.selectedSIM))
                    .font(.caption)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().stroke(Color.accentColor.opacity(0.5), lineWidth: 1))
        }
        .contextMenu {
            Button("设置SIM名称") {
                showingSettings = true
            }
        }
        .alert("SIM 线路说明", isPresented: $showSIMHint) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("受 iOS 系统限制，第三方应用无法直接指定拨号使用哪张 SIM 卡，此开关仅作为线路偏好记录，实际拨号线路由系统决定。\n\n如需免去每次选卡：打开系统设置 → 电话 → 默认通话号码，选择固定线路后，拨号将直接使用该卡。")
        }
        .accessibilityLabel("切换SIM卡")
    }
    
    private func simName(for sim: Int) -> String {
        sim == 1 ? sim1Name : sim2Name
    }
    
    // MARK: - Add Contact Button
    private var addContactButton: some View {
        Button { showAddContact = true } label: {
            Image(systemName: "person.crop.circle.fill.badge.plus")
                .font(.system(size: 16))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().stroke(Color.accentColor.opacity(0.5), lineWidth: 1))
        }
        .accessibilityLabel("添加到通讯录")
    }
    
    // MARK: - Suggestions
    private var suggestionList: some View {
        ScrollView {
            ForEach(viewModel.suggestions, id: \.identifier) { contact in
                SuggestionRow(
                    contact: contact,
                    matchedNumbers: viewModel.matchedNumbers[contact.identifier] ?? [],
                    query: viewModel.dialedNumber,
                    isExpanded: expandedContacts.contains(contact.identifier),
                    onDefaultTap: {
                        let numbers = viewModel.matchedNumbers[contact.identifier] ?? []
                        let fallback = contact.phoneNumbers.first?.value.stringValue
                        if let phone = numbers.first?.value.stringValue, !phone.isEmpty {
                            viewModel.callNumber(phone)
                        } else if let first = fallback, !first.isEmpty {
                            viewModel.callNumber(first)
                        }
                    },
                    onExpandTap: {
                        withAnimation {
                            if expandedContacts.contains(contact.identifier) {
                                expandedContacts.remove(contact.identifier)
                            } else {
                                expandedContacts.insert(contact.identifier)
                            }
                        }
                    },
                    onNumberTap: { number in
                        viewModel.callNumber(number)
                    }
                )
                .padding(.vertical, 2)
            }
        }
        .frame(minHeight: 60, maxHeight: 240)
    }
    
    // MARK: - Keypad Grid
    private var keypadGrid: some View {
        VStack(spacing: 12) {
            ForEach(digitRows.indices, id: \.self) { rowIndex in
                HStack(spacing: 26) {
                    ForEach(digitRows[rowIndex]) { key in
                        DigitButtonView(
                            digit: key.digit,
                            sub: key.sub,
                            longPressAction: key.longPressAction.map { action in
                                { viewModel.digitTapped(action) }
                            },
                            action: { d in
                                viewModel.digitTapped(d)
                            },
                            longPressStart: nil,
                            longPressEnd: nil
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    // MARK: - Delete Button
    
    @ViewBuilder
    private var deleteButton: some View {
        if !viewModel.dialedNumber.isEmpty {
            Image(systemName: "delete.left")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(isDeletePressed ? Color.accentColor : Color(.systemGray))
                .scaleEffect(isDeletePressed ? 1.2 : 1.0)
                .frame(width: 75, height: 75)
                .contentShape(Circle())
                .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
                    withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.7)) {
                        isDeletePressed = pressing
                    }
                    if !pressing {
                        viewModel.stopContinuousDelete()
                    }
                }, perform: {
                    viewModel.startContinuousDelete()
                    justDidLongPress = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        justDidLongPress = false
                    }
                })
                .onTapGesture {
                    if !justDidLongPress {
                        viewModel.deleteTapped()
                    }
                }
                .accessibilityLabel("删除")
                .onDisappear {
                    isDeletePressed = false
                    viewModel.stopContinuousDelete()
                }
        }
    }
    
    // MARK: - Call Button
    private var callButton: some View {
        Button { viewModel.callCurrentNumber() } label: {
            ZStack {
                Circle()
                    .fill(colorScheme == .dark ? Color.t9CallButtonDark : Color.t9CallButtonLight)
                    .frame(width: 75, height: 75)
                
                Image(systemName: "phone.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel("呼叫")
        .applyLongPressQuickDial(enabled: AppSettings.shared.longPressQuickDialEnabled) {
            viewModel.callFirstSuggestion()
        }
    }
    
    // MARK: - Helpers
    private func attributionText(_ attr: PhoneAttribution) -> String {
        if !attr.country.isEmpty {
            // 国外号码：显示国家名
            return attr.country
        } else {
            // 国内号码：显示 "省份 城市"
            let parts = [attr.province, attr.city].filter { !$0.isEmpty }
            return parts.joined(separator: " ")
        }
    }
    
    private func spamIcon(_ label: String) -> String {
        if label.contains("骚扰") || label.contains("诈骗") { return "exclamationmark.shield.fill" }
        if label.contains("推销") || label.contains("广告") { return "megaphone.fill" }
        if label.contains("快递") { return "package.fill" }
        if label.contains("外卖") { return "takeoutbag.and.cup.and.straw.fill" }
        return "info.circle.fill"
    }
    
    private func spamColor(_ label: String) -> Color {
        if label.contains("骚扰") || label.contains("诈骗") { return .red }
        if label.contains("推销") || label.contains("广告") { return .orange }
        if label.contains("快递") || label.contains("外卖") { return .blue }
        return .secondary
    }
}

// MARK: - Suggestion Row
struct SuggestionRow: View {
    let contact: CNContact
    let matchedNumbers: [CNLabeledValue<CNPhoneNumber>]
    let query: String
    let isExpanded: Bool
    let onDefaultTap: () -> Void   // 点击姓名区域 → 默认号码上屏
    let onExpandTap: () -> Void    // 点击角标 → 展开/收起
    let onNumberTap: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                // 姓名区域（点击 → 默认号码上屏）
                VStack(alignment: .leading, spacing: 8) {
                    highlightedNameText
                        .font(.body)
                    
                    // 未展开时显示第一个号码概要
                    if !isExpanded, !matchedNumbers.isEmpty {
                        HStack(spacing: 6) {
                            Text(CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: matchedNumbers[0].label ?? ""))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            highlightNumber(matchedNumbers[0].value.stringValue, query: query, font: .subheadline)
                        }
                    }
                }
                
                Spacer()
                
                // 多号码角标（点击 → 展开/收起）
                if matchedNumbers.count > 1 {
                    Text("\(matchedNumbers.count)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(.systemGray5)))
                        .contentShape(Capsule())
                        .onTapGesture { onExpandTap() }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onDefaultTap() }   // 整行可点选中号码，右手拇指也方便
            
            // 展开：显示全部号码，点击号码行直接拨打
            if isExpanded {
                ForEach(Array(matchedNumbers.enumerated()), id: \.element.identifier) { index, number in
                    Button {
                        onNumberTap(number.value.stringValue)
                    } label: {
                        HStack(spacing: 6) {
                            Text(CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: number.label ?? ""))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            highlightNumber(number.value.stringValue, query: query, font: .body)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading)
                    .padding(.top, index == 0 ? 8 : 4)
                }
            }
        }
        .padding(.vertical, 1)
    }
    
    // MARK: - 姓名高亮（T9 拼音映射）

    private var highlightedNameText: Text {
        let name = Self.contactDisplayName(family: contact.familyName, given: contact.givenName)
        guard !query.isEmpty else { return Text(name) }
        return highlightT9Text(name, query: query)
    }
    
    /// 中文姓名姓在前（张龙），西文名名在前（John Smith）
    private static func contactDisplayName(family: String, given: String) -> String {
        if family.isEmpty { return given }
        if given.isEmpty { return family }
        func isCJK(_ s: String) -> Bool {
            guard let v = s.unicodeScalars.first?.value else { return false }
            return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v)
        }
        return (isCJK(family) || isCJK(given)) ? family + given : given + " " + family
    }

    private func highlightNumber(_ number: String, query: String, font: Font = .caption) -> Text {
        highlightNumberText(number, query: query, font: font)
    }
}

// MARK: - Digit Key Model
struct DigitKey: Identifiable {
    let id = UUID()
    let digit: String
    let sub: String?
    let longPressAction: String?
    
    init(digit: String, sub: String? = nil, longPressAction: String? = nil) {
        self.digit = digit
        self.sub = sub
        self.longPressAction = longPressAction
    }
}

// MARK: - Number Formatter
struct T9NumberFormatter {
    static func formatT9(_ number: String) -> String {
        // 如果包含 * 或 #（特殊拨号代码），不格式化直接原样返回
        if number.contains("*") || number.contains("#") {
            return number
        }
        
        // 纯号码格式化
        let digits = number.filter { $0.isNumber }
        let hasPlus = number.contains("+")
        let prefix = hasPlus ? "+" : ""
        
        if digits.hasPrefix("1") && digits.count == 11 {
            return "\(prefix)\(digits)"
        }
        
        if (digits.hasPrefix("400") || digits.hasPrefix("800")) && digits.count >= 10 {
            return "\(prefix)\(digits)"
        }
        
        if digits.hasPrefix("0") && digits.count >= 10 {
            // 固定电话：区号用「（）」括起来
            let threeDigitCodes = ["010", "020", "021", "022", "023", "024", "025", "027", "028", "029"]
            if threeDigitCodes.contains(String(digits.prefix(3))) {
                let area = String(digits.prefix(3))
                let rest = String(digits.dropFirst(3))
                return "\(prefix)(\(area))\(rest)"
            } else {
                let area = String(digits.prefix(4))
                let rest = String(digits.dropFirst(4))
                return "\(prefix)(\(area))\(rest)"
            }
        }
        
        return "\(prefix)\(digits)"
    }
}

// MARK: - Add Contact Sheet (iOS Native)
struct AddContactView: UIViewControllerRepresentable {
    let phoneNumber: String
    
    func makeUIViewController(context: Context) -> UINavigationController {
        let contact = CNMutableContact()
        let phone = CNLabeledValue(label: CNLabelPhoneNumberMobile,
                                    value: CNPhoneNumber(stringValue: phoneNumber))
        contact.phoneNumbers = [phone]
        let controller = CNContactViewController(forNewContact: contact)
        controller.delegate = context.coordinator
        let nav = UINavigationController(rootViewController: controller)
        return nav
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, CNContactViewControllerDelegate {
        func contactViewController(_ viewController: CNContactViewController,
                                    didCompleteWith contact: CNContact?) {
            viewController.dismiss(animated: true)
        }
    }
}
