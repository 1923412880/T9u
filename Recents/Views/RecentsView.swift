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

                    Text("没有通话记录")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text("你还没有通话记录")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            } else {
                List {
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
                .confirmationDialog("清除所有通话记录？", isPresented: $showingDeleteConfirmation) {
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
    
    func loadRecords() {
        let history = UserDefaults.standard.stringArray(forKey: StorageKeys.recentDialHistory) ?? []
        let freq = UserDefaults.standard.dictionary(forKey: StorageKeys.callFrequency) as? [String: Int] ?? [:]
        let contacts = ContactStore.shared.fetchContactsForSearchData()
        
        records = history.enumerated().map { index, number in
            let digits = number.filter { $0.isNumber }
            let contactName: String
            if let matched = contacts.first(where: { data in
                data.phoneNumbers.contains { $0.filter { $0.isNumber } == digits }
            }) {
                let fullName = [matched.familyName, matched.givenName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                contactName = fullName.isEmpty
                    ? (matched.organizationName.isEmpty ? matched.nickname : matched.organizationName)
                    : fullName
            } else {
                contactName = number
            }
            let count = freq[digits] ?? 0
            
            return CallRecord(
                id: "\(number)-\(index)",
                number: number,
                displayName: contactName,
                numberLabel: nil,
                timeString: formatTime(index: index),
                durationString: count > 0 ? "拨打 \(count) 次" : "",
                type: .outgoing
            )
        }
    }
    
    func callNumber(_ number: String) {
        if let url = URL(string: "tel://\(number)") {
            UIApplication.shared.open(url)
        }
    }
    
    func deleteRecord(_ record: CallRecord) {
        var history = UserDefaults.standard.stringArray(forKey: StorageKeys.recentDialHistory) ?? []
        history.removeAll { $0 == record.number }
        UserDefaults.standard.set(history, forKey: StorageKeys.recentDialHistory)
        loadRecords()
    }
    
    func clearAllRecords() {
        UserDefaults.standard.removeObject(forKey: StorageKeys.recentDialHistory)
        records = []
    }
    
    private func formatTime(index: Int) -> String {
        if index == 0 { return "刚刚" }
        if index < 60 { return "\(index)分钟前" }
        if index < 1440 { return "\(index / 60)小时前" }
        return "\(index / 1440)天前"
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

