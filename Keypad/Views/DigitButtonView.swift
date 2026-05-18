import SwiftUI

struct DigitButtonView: View {
    let digit: String
    let sub: String?
    let longPressAction: (() -> Void)?  // 功能4：长按动作
    let action: (String) -> Void
    let longPressStart: (() -> Void)?  // 长按开始（连续删除）
    let longPressEnd: (() -> Void)?    // 长按结束（停止连续删除）

    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme

    private var hasLetters: Bool {
        sub != nil && !sub!.isEmpty
    }

    var body: some View {
        Button {
            action(digit)
        } label: {
            ZStack {
                // iOS 26 风格按键
                Circle()
                    .fill(colorScheme == .dark ? Color.t9ButtonBackgroundDark : Color.t9ButtonBackgroundLight)
                    .frame(width: 75, height: 75)
                    .overlay(
                        Circle()
                            .stroke(colorScheme == .dark ? Color.t9ButtonBorderDark : Color.t9ButtonBorderLight, lineWidth: 0.5)
                    )
                    .shadow(color: colorScheme == .light ? Color.black.opacity(0.08) : Color.clear, radius: 3, x: 0, y: 2)

                // 数字内容
                VStack(spacing: -2) {
                    Text(digit)
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(Color.t9DigitText)
                    
                    if hasLetters {
                        Text((sub ?? "").uppercased())
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.t9SubscriptText)
                            .tracking(1.5)
                    } else {
                        Text("")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.clear)
                    }
                }
            }
        }
        .buttonStyle(DigitButtonStyle(isPressed: $isPressed))
        .modifier(LongPressDigitModifier(longPressAction: longPressAction))
        .modifier(LongPressContinuousDeleteModifier(longPressStart: longPressStart, longPressEnd: longPressEnd))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .frame(width: 75, height: 75)
    }

    private var accessibilityLabel: String {
        if let letters = sub, !letters.isEmpty {
            return "\(digit), \(letters)"
        }
        return digit
    }
}

struct DigitButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, newValue in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = newValue
                }
            }
    }
}

// MARK: - Long Press Modifier for Digit Button
private struct LongPressDigitModifier: ViewModifier {
    let longPressAction: (() -> Void)?
    
    func body(content: Content) -> some View {
        if let action = longPressAction {
            content.onLongPressGesture(minimumDuration: 0.5) {
                action()
            }
        } else {
            content
        }
    }
}

// MARK: - Long Press Continuous Delete Modifier
private struct LongPressContinuousDeleteModifier: ViewModifier {
    let longPressStart: (() -> Void)?
    let longPressEnd: (() -> Void)?
    
    func body(content: Content) -> some View {
        if longPressStart != nil || longPressEnd != nil {
            content.onLongPressGesture(minimumDuration: 0.3, pressing: { isPressing in
                if isPressing {
                    longPressStart?()
                } else {
                    longPressEnd?()
                }
            }, perform: {})
        } else {
            content
        }
    }
}
