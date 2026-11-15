import SwiftUI
import Contacts

struct RecentsView: View {
    @StateObject private var viewModel = RecentsViewModel()
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            if viewModel.records.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 52))
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 4)

                    Text("没有拨出记录")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text("通过本机拨出的通话会显示在这里")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            } else {
                List {
                    Section {
                        ForEach(viewModel.records) { (record: CallRecord) in
                            HStack {
                                Image(systemName: record.iconName)
                                    .foregroundStyle(record.iconColor)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(record.displayName)
                                            .font(.body)
                                            .foregroundStyle(.primary)

                                        if let label = record.numberLabel {
                                            Text(label)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Text(record.formattedNumber)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(record.timeString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Text(record.durationString)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.callNumber(record.number)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    viewModel.deleteRecord(record)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text("仅记录通过本机真实拨出的通话，时间为实际拨出时间。iOS 不允许第三方应用读取系统通话记录，完整通话记录请在系统「电话」App 中查看。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.plain)
                .navigationTitle("最近通话")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingDeleteConfirmation = true
                        } label: {
                            Text("清除")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .confirmationDialog("清除所有拨出记录？", isPresented: $showingDeleteConfirmation) {
                    Button("清除", role: .destructive) {
                        viewModel.clearAllRecords()
                    }
                    Button("取消", role: .cancel) {}
                }
            }
        }
        .onAppear {
            viewModel.loadRecords()
        }
    }
}

class RecentsViewModel: ObservableObject {
    @Published var records: [CallRecord] = []
    private var historyObserver: NSObjectProtocol?

    init() {
        historyObserver = NotificationCenter.default.addObserver(
            forName: RecentDialStore.historyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadRecords()
        }
    }

    deinit {
        if let observer = historyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func loadRecords() {
        let entries = RecentDialStore.load()
        let contacts = ContactStore.shared.fetchContactsForSearchData()

        records = entries.map { entry -> CallRecord in
            let digits = entry.number.filter { $0.isNumber }
            var contactName: String? = nil
            if let matched = contacts.first(where: { data in
                data.phoneNumbers.contains { $0.filter { $0.isNumber } == digits }
            }) {
                let fullName = [matched.familyName, matched.givenName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                contactName = fullName.isEmpty
                    ? (matched.organizationName.isEmpty ? matched.nickname : matched.organizationName)
                    : fullName
            }

            return CallRecord(
                id: entry.number,
                number: entry.number,
                displayName: contactName ?? entry.number,
                numberLabel: nil,
                timeString: formatTime(entry.date),
                durationString: statusText(entry),
                type: .outgoing
            )
        }
    }

    func callNumber(_ number: String) {
        RecentDialStore.dialVerified(number)
    }

    func deleteRecord(_ record: CallRecord) {
        RecentDialStore.remove(number: record.number)
        loadRecords()
    }

    func clearAllRecords() {
        RecentDialStore.clearAll()
        records = []
    }

    // MARK: - 时间与状态显示

    /// 真实拨出时间（不是估算）
    private func formatTime(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")

        if cal.isDateInToday(date) {
            fmt.dateFormat = "HH:mm"
            return "今天 " + fmt.string(from: date)
        }
        if cal.isDateInYesterday(date) {
            fmt.dateFormat = "HH:mm"
            return "昨天 " + fmt.string(from: date)
        }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day ?? 0
        if days > 0 && days < 7 {
            fmt.dateFormat = "EEE HH:mm"
            return fmt.string(from: date)
        }
        fmt.dateFormat = "M月d日 HH:mm"
        return fmt.string(from: date)
    }

    /// 通话状态（由系统通话实时观察得出）
    private func statusText(_ entry: CallHistoryEntry) -> String {
        if entry.connected == true { return "已接通" }
        if entry.connected == false { return "未接通" }
        return entry.date != nil ? "已拨出" : ""
    }
}

struct CallRecord: Identifiable {
    let id: String
    let number: String
    let displayName: String
    let numberLabel: String?
    let timeString: String
    let durationString: String
    let type: CallType

    // 显示用格式化号码：11 位手机号按 3-4-4 分段
    var formattedNumber: String {
        let digits = number.filter { $0.isNumber }
        if digits.count == 11 && digits.hasPrefix("1") {
            let a = digits.index(digits.startIndex, offsetBy: 3)
            let b = digits.index(a, offsetBy: 4)
            return "\(digits[..<a]) \(digits[a..<b]) \(digits[b...])"
        }
        return number
    }

    var iconName: String {
        switch type {
        case .incoming: return "arrow.down.left"
        case .outgoing: return "arrow.up.right"
        case .missed: return "arrow.down.left"
        }
    }

    var iconColor: Color {
        switch type {
        case .missed: return .red
        default: return .green
        }
    }
}

enum CallType {
    case incoming, outgoing, missed
}
