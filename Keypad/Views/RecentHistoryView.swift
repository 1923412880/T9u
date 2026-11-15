import SwiftUI
import Contacts

struct RecentHistoryView: View {
    @ObservedObject var viewModel: KeypadViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("最近拨号")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button("清除") {
                    RecentDialStore.clearAll()
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if viewModel.recentHistory.isEmpty {
                Text("暂无拨号记录")
                    .foregroundStyle(.secondary)
                    .padding(.top, 40)
                Spacer()
            } else {
                List {
                    ForEach(viewModel.recentHistory) { entry in
                        Button {
                            viewModel.dialedNumber = entry.number
                        } label: {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundStyle(.secondary)

                                Text(entry.number)
                                    .foregroundStyle(.primary)

                                Spacer()

                                Text(Self.shortTime(entry.date))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                RecentDialStore.remove(number: entry.number)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(.systemBackground))
    }

    private static func shortTime(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        if cal.isDateInToday(date) {
            fmt.dateFormat = "HH:mm"
            return fmt.string(from: date)
        }
        if cal.isDateInYesterday(date) {
            fmt.dateFormat = "HH:mm"
            return "昨天 " + fmt.string(from: date)
        }
        fmt.dateFormat = "M月d日"
        return fmt.string(from: date)
    }
}
