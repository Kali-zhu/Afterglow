import SwiftUI
import UIKit

/// 设计令牌。主题：一面放满玻璃瓶的梳妆台。
/// 颜色来自产品本身（每个瓶子的液体色），界面其余部分保持安静、跟随系统明暗。
enum Theme {
    // Porcelain：浅色下是冷调瓷白，深色下退回系统分组背景
    static let porcelain = Color(light: "EEF1F4", dark: "000000")
    // Shelf：架板颜色
    static let shelf = Color(light: "D9DEE4", dark: "2C2C2E")
    static let ink = Color.primary
    // 状态色：与液体色区分开，只用于保质期
    static let sage = Color(light: "5E9277", dark: "7FB89A")
    static let honey = Color(light: "C7862B", dark: "E3A54E")
    static let rouge = Color(light: "B8404F", dark: "E06876")

    /// 瓶中液体可选色：取自真实产品（精华的琥珀、乳液的奶白、化妆水的淡蓝、香水的淡紫……）
    static let liquids = ["E7B873", "F1E6D8", "BFD7EA", "D5C6E8", "C8E0CC", "F2C4C9", "E9A07A"]

    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.65)
}

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
    }
}

/// 按下时轻微收缩，回应用户的触摸
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Theme.snappy, value: configuration.isPressed)
    }
}

extension View {
    func pressable() -> some View { buttonStyle(PressableStyle()) }
}
