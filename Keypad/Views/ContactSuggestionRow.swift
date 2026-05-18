import SwiftUI
import Contacts

/// 联系人建议行 — 在拨号键盘上显示匹配的联系人
/// 支持搜索关键字高亮（姓名/号码中匹配部分用主题色高亮）
struct ContactSuggestionRow: View {
    let contact: CNContact
    let matchedNumber: CNLabeledValue<CNPhoneNumber>?
    let query: String
    let onTap: (String) -> Void

    private var displayName: String {
        let components = [contact.familyName, contact.givenName, contact.middleName]
            .filter { !$0.isEmpty }
        return components.isEmpty ? contact.organizationName : components.joined()
    }

    private var phoneLabel: String {
        guard let number = matchedNumber else { return "" }
        let label = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: number.label ?? "")
        let digits = number.value.stringValue
        return "\(label): \(digits)"
    }

    var body: some View {
        Button {
            if let number = matchedNumber?.value.stringValue {
                onTap(number)
            } else if let firstPhone = contact.phoneNumbers.first?.value.stringValue {
                onTap(firstPhone)
            }
        } label: {
            HStack(spacing: 12) {
                // 头像
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
                                Text(initials)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                            )
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .padding(.leading, 4)

                // 姓名 + 号码（带高亮）
                VStack(alignment: .leading, spacing: 2) {
                    highlightedNameText
                        .font(.body)
                        .foregroundStyle(.primary)

                    if !phoneLabel.isEmpty {
                        highlightedPhoneText
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "phone.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - 高亮文本

    /// 高亮姓名：将拼音匹配到的汉字高亮
    private var highlightedNameText: Text {
        guard !query.isEmpty else { return Text(displayName) }
        return highlightText(displayName, query: query)
    }

    /// 高亮号码：将匹配的数字子串高亮
    private var highlightedPhoneText: Text {
        guard !query.isEmpty else { return Text(phoneLabel) }
        return highlightPhoneText(phoneLabel, query: query)
    }

    /// 高亮通用文本（姓名/公司名）
    private func highlightText(_ text: String, query: String) -> Text {
        highlightT9Text(text, query: query)
    }

    /// 高亮号码文本
    private func highlightPhoneText(_ text: String, query: String) -> Text {
        let digits = query.filter { $0.isNumber }
        guard !digits.isEmpty else { return Text(text) }

        let cleanText = text.filter { $0.isNumber }
        if let range = cleanText.range(of: digits) {
            let lower = cleanText.distance(from: cleanText.startIndex, to: range.lowerBound)
            let upper = cleanText.distance(from: cleanText.startIndex, to: range.upperBound)

            var result = Text("")
            var digitIdx = 0
            for char in text {
                if char.isNumber {
                    if digitIdx >= lower && digitIdx < upper {
                        result = result + Text(String(char)).foregroundStyle(Color.accentColor)
                    } else {
                        result = result + Text(String(char))
                    }
                    digitIdx += 1
                } else {
                    result = result + Text(String(char))
                }
            }
            return result
        }

        return Text(text)
    }

    private var initials: String {
        let last = contact.familyName.first.map { String($0) } ?? ""
        let first = contact.givenName.first.map { String($0) } ?? ""
        return last + first
    }
}
