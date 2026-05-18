import SwiftUI

struct NumberDisplayView: View {
    let number: String

    var body: some View {
        Text(displayText)
            .font(.system(size: 34, weight: .regular))
            .foregroundStyle(Color.primary)
            .lineLimit(1)
            .truncationMode(.head)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(minHeight: 60)
    }

    /// 功能2：智能号码格式化
    /// 使用 NumberFormatter 统一格式化，支持：
    /// - 手机号：138-0013-8001
    /// - 固话：010-12345678
    /// - 400/800：400-800-8800
    /// - 带后缀：138-0013-8001,123;456（支持暂停,和等待;）
    private var displayText: String {
        guard !number.isEmpty else { return "" }

        // 如果包含后缀符号（, 或 ;），分别格式化
        var mainNumber = ""
        var suffix = ""

        if let commaIdx = number.firstIndex(where: { $0 == "," || $0 == ";" }) {
            mainNumber = String(number[..<commaIdx])
            suffix = String(number[commaIdx...])
        } else {
            mainNumber = number
        }

        let formatted = T9NumberFormatter.formatT9(mainNumber)
        return suffix.isEmpty ? formatted : "\(formatted)\(suffix)"
    }
}
