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
                    viewModel.recentHistory.removeAll()
                    UserDefaults.standard.removeObject(forKey: StorageKeys.recentDialHistory)
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
                    ForEach(viewModel.recentHistory, id: \.self) { number in
                        Button {
                            viewModel.dialedNumber = number
                        } label: {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundStyle(.secondary)
                                
                                Text(number)
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                if let index = viewModel.recentHistory.firstIndex(of: number) {
                                    viewModel.recentHistory.remove(at: index)
                                    UserDefaults.standard.set(viewModel.recentHistory, forKey: StorageKeys.recentDialHistory)
                                }
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
}
