import SwiftUI
import UIKit

/// 设计令牌。主题：一面放满玻璃瓶的梳妆台。
/// 颜色来自产品本身（每个容器的液体色），界面其余部分保持安静、跟随系统明暗。
enum Theme {
    // Porcelain：浅色下是冷调瓷白，深色下退回纯黑
    static let porcelain = Color(light: "EEF1F4", dark: "000000")
    // Shelf：架板颜色
    static let shelf = Color(light: "D9DEE4", dark: "2C2C2E")
    static let ink = Color.primary
    // 状态色：与液体色区分开，只用于保质期
    static let sage = Color(light: "5E9277", dark: "7FB89A")
    static let honey = Color(light: "C7862B", dark: "E3A54E")
    static let rouge = Color(light: "B8404F", dark: "E06876")
    /// 瓶盖、罐盖、口红管等"实心"部件
    static let cap = Color(light: "3A3A3C", dark: "AEAEB2")
    /// 卡片底色（今日、空瓶页的分组）
    static let card = Color(uiColor: .secondarySystemGroupedBackground)

    /// 液体可选色：取自真实产品（精华的琥珀、乳液的奶白、化妆水的淡蓝、香水的淡紫……）
    static let liquids = ["E7B873", "F1E6D8", "BFD7EA", "D5C6E8", "C8E0CC", "F2C4C9", "E9A07A", "C9505C", "D9B38C"]
    static let liquidNames = ["琥珀", "奶白", "淡蓝", "淡紫", "薄荷", "裸粉", "珊瑚", "正红", "肤色"]

    /// 剩余不足 15%：冷调石板蓝，与保质期的三种状态色区分
    static let low = Color(light: "5B7DB1", dark: "8FAEE0")

    // v1.0 玻璃架板：浅色磨砂玻璃，顶面亮、正面带一点玻璃断面的青绿
    static let plankSurface = Color(light: "FFFFFF", dark: "8E9AA6")
    static let plankEdge = Color(light: "CFE6E0", dark: "4A5A58")
    static let plankShadow = Color(light: "1D2A3A", dark: "000000")

    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.65)
    /// "拿起来"：略带回弹
    static let lift = Animation.spring(response: 0.5, dampingFraction: 0.72)
    /// 弹回原状（挤管、按泵后松手）
    static let springBack = Animation.spring(response: 0.34, dampingFraction: 0.48)
}

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
    /// RGBA 分量（sRGB，0...1）
    var rgba: (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    /// 与另一种颜色按比例混合（t = 0 是自己，1 是 other）
    func mixed(with other: Color, _ t: Double) -> Color {
        let a = rgba, b = other.rgba
        let k = max(0, min(1, t))
        return Color(red: a.r + (b.r - a.r) * k,
                     green: a.g + (b.g - a.g) * k,
                     blue: a.b + (b.b - a.b) * k,
                     opacity: a.a + (b.a - a.a) * k)
    }

    /// 感知亮度（0 暗 ... 1 亮）
    var luminance: Double {
        let c = rgba
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    init(light: String, dark: String) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
    }
}

/// 中文格式化
enum Fmt {
    /// 2027 年 5 月 21 日
    static func day(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0) 年 \(c.month ?? 0) 月 \(c.day ?? 0) 日"
    }
    /// 5 月 21 日
    static func shortDay(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 0) 月 \(c.day ?? 0) 日"
    }
    /// 31 / 0.5（最多一位小数）
    static func amount(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        if r == r.rounded() { return "\(Int(r))" }
        return String(format: "%.1f", r)
    }
    static func money(_ v: Double) -> String {
        v >= 10 ? "¥\(Int(v.rounded()))" : String(format: "¥%.1f", v)
    }
    /// ¥5,565：藏品总值这种四位数以上的金额，带千分位更好读
    static func bigMoney(_ v: Double) -> String {
        "¥" + Int(v.rounded()).formatted()
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
