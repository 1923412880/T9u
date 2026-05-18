import SwiftUI

extension Color {
    // iOS 26 液态玻璃风格 - 使用静态颜色确保生效
    static let t9ButtonBackgroundDark = Color(red: 44/255, green: 44/255, blue: 46/255)
    static let t9ButtonBackgroundLight = Color.white
    
    static let t9ButtonBorderDark = Color(red: 72/255, green: 72/255, blue: 74/255)
    static let t9ButtonBorderLight = Color.clear
    
    static let t9ButtonHighlightDark = Color(red: 58/255, green: 58/255, blue: 60/255)
    static let t9ButtonHighlightLight = Color(red: 235/255, green: 235/255, blue: 240/255)
    
    static let t9CallButtonDark = Color(red: 58/255, green: 122/255, blue: 66/255)
    static let t9CallButtonLight = Color(red: 52/255, green: 199/255, blue: 89/255)
    
    // 兼容旧代码的动态颜色
    static let t9ButtonBackground = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ?
            UIColor(red: 44/255, green: 44/255, blue: 46/255, alpha: 1) :
            UIColor.white
    })
    
    static let t9ButtonBorder = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ?
            UIColor(red: 72/255, green: 72/255, blue: 74/255, alpha: 1) :
            UIColor.clear
    })
    
    static let t9ButtonHighlight = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ?
            UIColor(red: 58/255, green: 58/255, blue: 60/255, alpha: 1) :
            UIColor(red: 235/255, green: 235/255, blue: 240/255, alpha: 1)
    })
    
    static let t9CallButton = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ?
            UIColor(red: 58/255, green: 122/255, blue: 66/255, alpha: 1) :
            UIColor(red: 52/255, green: 199/255, blue: 89/255, alpha: 1)
    })
    
    static let t9DigitText = Color.primary
    static let t9SubscriptText = Color.primary
    static let t9NumberDisplay = Color.primary
    static let t9NumberPlaceholder = Color.secondary.opacity(0.5)
}
